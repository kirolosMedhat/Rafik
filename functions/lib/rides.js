/**
 * Rafik Server-Authoritative Ride Lifecycle & Operations
 * Condition 3 compliant: Clients cannot tamper with pricing, assignment, or PIN verification.
 */
import * as admin from 'firebase-admin';
function getAdmin() {
    return admin.default || admin;
}
import * as crypto from 'crypto';
import { getPlatformSettings } from './config.js';
import { createAndDispatchOffers } from './dispatch.js';
import { computeAuthoritativeFare } from './pricing.js';
import { approximateRoadDistanceKm, haversineDistanceKm } from './spatial.js';
import { syncDriverAvailability } from './triggers.js';
/**
 * Server-Authoritative Ride Creation & 3 KM Dispatch Initiation
 */
export async function executeRequestRide(callerUid, payload) {
    const db = getAdmin().firestore();
    const settings = await getPlatformSettings();
    // 1. Validate Caller Profile & Strict Role Enforcement
    const userDoc = await db.collection('users').doc(callerUid).get();
    if (!userDoc.exists) {
        throw new Error('USER_NOT_FOUND: User profile does not exist.');
    }
    const userData = userDoc.data();
    if (!userData?.is_active) {
        throw new Error('ACCOUNT_DISABLED: Account is deactivated.');
    }
    if (userData?.role !== 'rider') {
        throw new Error('FORBIDDEN: Only registered rider accounts can create ride requests.');
    }
    // 1b. Validate Payload & Egyptian Coordinates Bounds
    if (!payload.tier || !['standard', 'rafik_girl'].includes(payload.tier)) {
        throw new Error('INVALID_TIER: Tier must be standard or rafik_girl.');
    }
    if (typeof payload.pickup_lat !== 'number' ||
        typeof payload.pickup_lng !== 'number' ||
        typeof payload.dropoff_lat !== 'number' ||
        typeof payload.dropoff_lng !== 'number' ||
        !Number.isFinite(payload.pickup_lat) ||
        !Number.isFinite(payload.pickup_lng) ||
        !Number.isFinite(payload.dropoff_lat) ||
        !Number.isFinite(payload.dropoff_lng)) {
        throw new Error('INVALID_COORDINATES: Pickup and dropoff coordinates must be finite numbers.');
    }
    // Cairo / Egypt coordinate boundaries: Lat [21.0, 32.5], Lng [24.0, 37.0]
    if (payload.pickup_lat < 21.0 || payload.pickup_lat > 32.5 ||
        payload.pickup_lng < 24.0 || payload.pickup_lng > 37.0 ||
        payload.dropoff_lat < 21.0 || payload.dropoff_lat > 32.5 ||
        payload.dropoff_lng < 24.0 || payload.dropoff_lng > 37.0) {
        throw new Error('OUT_OF_BOUNDS: Coordinates must be within Egyptian operational service boundaries.');
    }
    if (!payload.pickup_address ||
        typeof payload.pickup_address !== 'string' ||
        payload.pickup_address.trim().length === 0 ||
        payload.pickup_address.length > 200) {
        throw new Error('INVALID_ADDRESS: Pickup address is missing or exceeds allowed length.');
    }
    if (!payload.dropoff_address ||
        typeof payload.dropoff_address !== 'string' ||
        payload.dropoff_address.trim().length === 0 ||
        payload.dropoff_address.length > 200) {
        throw new Error('INVALID_ADDRESS: Dropoff address is missing or exceeds allowed length.');
    }
    if (payload.payment_method && !['cash', 'wallet', 'card', 'instapay'].includes(payload.payment_method)) {
        throw new Error('INVALID_PAYMENT_METHOD: Unsupported payment method.');
    }
    // 2. Rafik Girl Tier Restriction
    if (payload.tier === 'rafik_girl') {
        if (userData?.gender !== 'female' || userData?.gender_verified !== true) {
            throw new Error('RAFIK_GIRL_UNAUTHORIZED: Rafik Girl is restricted to verified female passengers.');
        }
    }
    // 3. Server-Authoritative Distance & Fare Calculation
    const distanceKm = approximateRoadDistanceKm(payload.pickup_lat, payload.pickup_lng, payload.dropoff_lat, payload.dropoff_lng, settings.pricing.cairo_traffic_multiplier);
    if (distanceKm < 0.2) {
        throw new Error('TRIP_TOO_SHORT: Trip distance is too short.');
    }
    const fareResult = await computeAuthoritativeFare(distanceKm, payload.tier);
    // 4. Cryptographic 4-Digit PIN Generation (Requirement C: crypto.randomInt(0, 10000))
    const pinNum = crypto.randomInt(0, 10000);
    const randomPin = pinNum.toString().padStart(4, '0');
    // 5. Timings & Expansion Checkpoints
    const rideRef = db.collection('rides').doc();
    const ttlMs = settings.dispatch.ride_request_ttl_seconds * 1000;
    const expansionIntervalMs = (settings.dispatch.expansion_interval_seconds || 30) * 1000;
    const expiresAt = getAdmin().firestore.Timestamp.fromMillis(Date.now() + ttlMs);
    const nextExpansionAt = getAdmin().firestore.Timestamp.fromMillis(Date.now() + expansionIntervalMs);
    const rideData = {
        ride_id: rideRef.id,
        rider_id: callerUid,
        rider_name: userData?.full_name ?? 'Passenger',
        rider_phone: userData?.phone ?? '',
        driver_id: null,
        driver_name: null,
        driver_phone: null,
        vehicle_plate: null,
        vehicle_model: null,
        tier: payload.tier,
        status: 'requested',
        pickup_address: payload.pickup_address,
        pickup_lat: payload.pickup_lat,
        pickup_lng: payload.pickup_lng,
        dropoff_address: payload.dropoff_address,
        dropoff_lat: payload.dropoff_lat,
        dropoff_lng: payload.dropoff_lng,
        distance_km: fareResult.distance_km,
        fare_egp: fareResult.fare_egp,
        driver_earnings_egp: fareResult.driver_earnings_egp,
        platform_fee_egp: fareResult.platform_fee_egp,
        payment_method: payload.payment_method ?? 'cash',
        attempts: 0,
        dispatch_stage: 1,
        current_radius: settings.dispatch.initial_radius_km,
        next_expansion_at: nextExpansionAt,
        dispatched_driver_ids: [],
        requested_at: getAdmin().firestore.FieldValue.serverTimestamp(),
        expires_at: expiresAt,
    };
    const pinData = {
        pin: randomPin,
        attempts: 0,
        is_locked: false,
        created_at: getAdmin().firestore.FieldValue.serverTimestamp(),
    };
    // 6. Atomic Active Ride Reservation & Document Creation (Requirement H)
    const riderReservationRef = db.collection('rider_reservations').doc(callerUid);
    await db.runTransaction(async (transaction) => {
        const reservationSnap = await transaction.get(riderReservationRef);
        if (reservationSnap.exists && reservationSnap.data()?.status === 'active') {
            throw new Error('ACTIVE_RIDE_EXISTS: You already have an active ride request in progress.');
        }
        transaction.set(riderReservationRef, {
            status: 'active',
            ride_id: rideRef.id,
            updated_at: getAdmin().firestore.FieldValue.serverTimestamp(),
        });
        transaction.set(rideRef, rideData);
        transaction.set(rideRef.collection('security').doc('pin_data'), pinData);
    });
    // 7. Dispatch Initial 3 KM Offers
    const dispatchResult = await createAndDispatchOffers(rideData, settings.dispatch.initial_radius_km, []);
    if (dispatchResult.dispatchedDriverIds.length > 0) {
        await rideRef.update({
            dispatched_driver_ids: dispatchResult.dispatchedDriverIds,
        });
    }
    return {
        ride_id: rideRef.id,
        fare_egp: fareResult.fare_egp,
        distance_km: fareResult.distance_km,
        pin: randomPin, // Returned exclusively to the passenger
        offers_dispatched: dispatchResult.count,
    };
}
/**
 * Server-Authoritative Atomic Ride Acceptance
 */
export async function executeAcceptRide(driverUid, offerId) {
    const db = getAdmin().firestore();
    const result = await db.runTransaction(async (transaction) => {
        // 1. Read Offer
        const offerRef = db.collection('ride_offers').doc(offerId);
        const offerSnap = await transaction.get(offerRef);
        if (!offerSnap.exists) {
            throw new Error('OFFER_NOT_FOUND: The ride offer does not exist.');
        }
        const offerData = offerSnap.data();
        if (offerData?.driver_id !== driverUid) {
            throw new Error('UNAUTHORIZED_DRIVER: You cannot accept an offer assigned to another driver.');
        }
        if (offerData?.status !== 'pending') {
            throw new Error('OFFER_UNAVAILABLE: Offer has already been responded to.');
        }
        if (offerData?.expires_at?.toMillis() < Date.now()) {
            throw new Error('OFFER_EXPIRED: Offer has timed out.');
        }
        const rideId = offerData.ride_id;
        const rideRef = db.collection('rides').doc(rideId);
        const rideSnap = await transaction.get(rideRef);
        if (!rideSnap.exists) {
            throw new Error('RIDE_NOT_FOUND: Ride was cancelled or removed.');
        }
        const rideData = rideSnap.data();
        if (rideData?.status !== 'requested') {
            throw new Error('RIDE_ALREADY_ACCEPTED: Ride has already been claimed by another captain.');
        }
        // 2. Read Driver Profile & Vehicle Details
        const driverRef = db.collection('drivers').doc(driverUid);
        const driverSnap = await transaction.get(driverRef);
        if (!driverSnap.exists || driverSnap.data()?.status !== 'approved') {
            throw new Error('DRIVER_NOT_APPROVED: Only approved captains can accept rides.');
        }
        if (driverSnap.data()?.is_busy) {
            throw new Error('DRIVER_BUSY: You already have an active ride.');
        }
        const userSnap = await transaction.get(db.collection('users').doc(driverUid));
        const vehicleSnap = await transaction.get(db.collection('vehicles').doc(driverUid));
        const driverName = userSnap.data()?.full_name ?? 'Captain';
        const driverPhone = userSnap.data()?.phone ?? '';
        const vehiclePlate = vehicleSnap.data()?.plate_number ?? 'Cairo Plate';
        const vehicleModel = `${vehicleSnap.data()?.make ?? ''} ${vehicleSnap.data()?.model ?? ''}`.trim() || 'Sedan';
        // 3. Atomically assign ride to driver
        transaction.update(rideRef, {
            status: 'accepted',
            driver_id: driverUid,
            driver_name: driverName,
            driver_phone: driverPhone,
            vehicle_plate: vehiclePlate,
            vehicle_model: vehicleModel,
            accepted_at: getAdmin().firestore.FieldValue.serverTimestamp(),
        });
        // 4. Mark driver as busy
        transaction.update(driverRef, {
            is_busy: true,
            current_ride_id: rideId,
            updated_at: getAdmin().firestore.FieldValue.serverTimestamp(),
        });
        // 5. Mark this offer accepted
        transaction.update(offerRef, {
            status: 'accepted',
        });
        return { rideId, riderId: rideData.rider_id, driverName };
    });
    // 6. Outside Transaction: Invalidate all other pending offers for this ride
    const competingOffers = await db.collection('ride_offers')
        .where('ride_id', '==', result.rideId)
        .where('status', '==', 'pending')
        .get();
    const cancelBatch = db.batch();
    for (const doc of competingOffers.docs) {
        if (doc.id !== offerId) {
            cancelBatch.update(doc.ref, { status: 'cancelled' });
        }
    }
    await cancelBatch.commit();
    // 7. Update RTDB driver availability flag & active_rider_id for live tracking
    try {
        await getAdmin().database().ref(`driver_locations/${driverUid}`).update({
            is_busy: true,
            active_rider_id: result.riderId,
        });
    }
    catch (_) { }
    // 8. Send FCM Notification to Passenger
    try {
        const userDoc = await db.collection('users').doc(result.riderId).get();
        // Look up rider token if available
        const riderToken = userDoc.data()?.fcm_token;
        if (riderToken) {
            await getAdmin().messaging().send({
                token: riderToken,
                notification: {
                    title: 'تم قبول طلبك! 🚗',
                    body: `الكابتن ${result.driverName} في الطريق إليك.`,
                },
                data: {
                    type: 'ride_accepted',
                    ride_id: result.rideId,
                },
            });
        }
    }
    catch (_) { }
    return { success: true, ride_id: result.rideId };
}
/**
 * Driver Arrival at Pickup Location (Requirement D: Server-Authoritative RTDB Geofence)
 * Does NOT trust client coordinates; reads fresh telemetry from RTDB directly.
 */
export async function executeMarkArrived(driverUid, rideId) {
    const db = getAdmin().firestore();
    const settings = await getPlatformSettings();
    const rideRef = db.collection('rides').doc(rideId);
    const rideSnap = await rideRef.get();
    if (!rideSnap.exists)
        throw new Error('RIDE_NOT_FOUND');
    const ride = rideSnap.data();
    if (ride?.driver_id !== driverUid) {
        throw new Error('UNAUTHORIZED: Caller is not the assigned driver.');
    }
    if (ride?.status !== 'accepted') {
        throw new Error('INVALID_STATE: Ride must be in accepted status.');
    }
    // 1. Fetch live telemetry coordinates directly from RTDB using Admin SDK
    const rtdb = getAdmin().database();
    const telemetrySnap = await rtdb.ref(`driver_locations/${driverUid}`).once('value');
    if (!telemetrySnap.exists()) {
        throw new Error('MISSING_TELEMETRY: No live location telemetry found for driver.');
    }
    const telemetry = telemetrySnap.val();
    if (typeof telemetry?.lat !== 'number' || typeof telemetry?.lng !== 'number') {
        throw new Error('INVALID_TELEMETRY: Driver coordinates are missing or invalid.');
    }
    // 2. Validate Telemetry Timestamp Freshness
    const now = Date.now();
    const heartbeatLimitMs = (settings.dispatch.driver_heartbeat_timeout_seconds || 60) * 1000;
    if (typeof telemetry.updated_at !== 'number' || (now - telemetry.updated_at) > heartbeatLimitMs) {
        throw new Error('STALE_TELEMETRY: Driver telemetry is outdated or stale. Cannot verify arrival.');
    }
    if (telemetry.updated_at > now + 5000) {
        throw new Error('INVALID_TELEMETRY_TIMESTAMP: Future timestamp detected in telemetry.');
    }
    // 3. Unconditionally Enforce Server-Authoritative Arrival Geofence
    const distMeters = haversineDistanceKm(telemetry.lat, telemetry.lng, ride.pickup_lat, ride.pickup_lng) * 1000;
    const maxAllowedMeters = settings.safety.max_arrival_distance_meters || 500;
    if (distMeters > maxAllowedMeters) {
        throw new Error(`ARRIVAL_GEOFENCE_FAILED: Driver is ${Math.round(distMeters)}m from pickup (maximum allowed: ${maxAllowedMeters}m).`);
    }
    await rideRef.update({
        status: 'arrived',
        arrived_at: getAdmin().firestore.FieldValue.serverTimestamp(),
    });
    return { success: true };
}
/**
 * Cryptographic PIN Handshake Verification & Trip Start
 * Condition 3 compliant: Attempt limit enforced without transaction rollback.
 */
export async function executeVerifyPinAndStartTrip(driverUid, rideId, inputPin) {
    // Validate PIN format on backend (Requirement C)
    if (!inputPin || !/^\d{4}$/.test(inputPin.trim())) {
        throw new Error('INVALID_PIN_FORMAT: PIN must be exactly 4 numeric digits.');
    }
    const db = getAdmin().firestore();
    const settings = await getPlatformSettings();
    const maxAttempts = settings.safety.max_pin_attempts;
    const rideRef = db.collection('rides').doc(rideId);
    const pinRef = rideRef.collection('security').doc('pin_data');
    return db.runTransaction(async (transaction) => {
        const rideSnap = await transaction.get(rideRef);
        if (!rideSnap.exists)
            throw new Error('RIDE_NOT_FOUND');
        const ride = rideSnap.data();
        if (ride?.driver_id !== driverUid) {
            throw new Error('UNAUTHORIZED: Caller is not the assigned driver.');
        }
        if (ride?.status !== 'arrived') {
            throw new Error('INVALID_STATE: Ride must be in arrived state to verify PIN.');
        }
        const pinSnap = await transaction.get(pinRef);
        if (!pinSnap.exists)
            throw new Error('PIN_NOT_FOUND: Security PIN data missing.');
        const pinData = pinSnap.data();
        if (pinData.is_locked || pinData.attempts >= maxAttempts) {
            return { success: false, status: 'locked', attempts_left: 0, is_locked: true };
        }
        if (pinData.pin.trim() === inputPin.trim()) {
            // PIN Correct: Start Trip
            transaction.update(rideRef, {
                status: 'in_progress',
                started_at: getAdmin().firestore.FieldValue.serverTimestamp(),
            });
            return { success: true, status: 'in_progress', attempts_left: maxAttempts - pinData.attempts, is_locked: false };
        }
        else {
            // PIN Incorrect: Increment attempts and persist counter
            const newAttempts = pinData.attempts + 1;
            const locked = newAttempts >= maxAttempts;
            transaction.update(pinRef, {
                attempts: newAttempts,
                is_locked: locked,
            });
            transaction.update(rideRef, {
                attempts: newAttempts,
            });
            return {
                success: false,
                status: locked ? 'locked' : 'wrong_pin',
                attempts_left: Math.max(0, maxAttempts - newAttempts),
                is_locked: locked,
            };
        }
    });
}
/**
 * Trip Completion & Wallet Ledger Settlement (Idempotent & Safe Availability Sync)
 */
export async function executeCompleteRide(driverUid, rideId) {
    const db = getAdmin().firestore();
    const result = await db.runTransaction(async (transaction) => {
        const rideRef = db.collection('rides').doc(rideId);
        const rideSnap = await transaction.get(rideRef);
        if (!rideSnap.exists)
            throw new Error('RIDE_NOT_FOUND');
        const ride = rideSnap.data();
        if (ride.driver_id !== driverUid) {
            throw new Error('UNAUTHORIZED: Caller is not the assigned driver.');
        }
        if (ride.status === 'completed') {
            throw new Error('ALREADY_COMPLETED: Ride has already been completed.');
        }
        if (ride.status !== 'in_progress') {
            throw new Error('INVALID_STATE: Ride must be in progress to complete.');
        }
        const fare = ride.fare_egp;
        const earnings = ride.driver_earnings_egp;
        // 1. Update Ride Status
        transaction.update(rideRef, {
            status: 'completed',
            completed_at: getAdmin().firestore.FieldValue.serverTimestamp(),
        });
        // 2. Free Driver & Credit Wallet
        const driverRef = db.collection('drivers').doc(driverUid);
        transaction.update(driverRef, {
            is_busy: false,
            current_ride_id: null,
            total_trips: getAdmin().firestore.FieldValue.increment(1),
            wallet_balance_egp: getAdmin().firestore.FieldValue.increment(earnings),
            updated_at: getAdmin().firestore.FieldValue.serverTimestamp(),
        });
        // 3. Create Immutable Ledger Record
        const paymentRef = db.collection('payments').doc();
        transaction.set(paymentRef, {
            payment_id: paymentRef.id,
            ride_id: rideId,
            driver_id: driverUid,
            rider_id: ride.rider_id,
            amount_egp: earnings,
            kind: 'trip_earnings',
            status: 'settled',
            created_at: getAdmin().firestore.FieldValue.serverTimestamp(),
        });
        // 4. Release Rider Active Reservation (Requirement H)
        const riderReservationRef = db.collection('rider_reservations').doc(ride.rider_id);
        transaction.set(riderReservationRef, {
            status: 'idle',
            ride_id: null,
            updated_at: getAdmin().firestore.FieldValue.serverTimestamp(),
        });
        return { fare, earnings, riderId: ride.rider_id };
    });
    // 5. Reliable RTDB availability synchronization with retry and outbox fallback (Requirement I)
    await syncDriverAvailability(driverUid, false, null);
    return { success: true, fare_egp: result.fare, driver_earnings_egp: result.earnings };
}
/**
 * Ride Cancellation (Idempotent & Safe Availability Sync)
 */
export async function executeCancelRide(callerUid, rideId, reason) {
    const db = getAdmin().firestore();
    const rideRef = db.collection('rides').doc(rideId);
    const rideSnap = await rideRef.get();
    if (!rideSnap.exists)
        throw new Error('RIDE_NOT_FOUND');
    const ride = rideSnap.data();
    const isRider = ride?.rider_id === callerUid;
    const isDriver = ride?.driver_id === callerUid;
    if (!isRider && !isDriver) {
        throw new Error('UNAUTHORIZED: Caller is not a participant of this ride.');
    }
    if (ride?.status === 'in_progress' || ride?.status === 'completed' || ride?.status === 'cancelled') {
        throw new Error('CANNOT_CANCEL: Trip is already in progress, completed, or cancelled.');
    }
    const batch = db.batch();
    batch.update(rideRef, {
        status: 'cancelled',
        cancelled_by: isRider ? 'rider' : 'driver',
        cancellation_reason: reason,
        cancelled_at: getAdmin().firestore.FieldValue.serverTimestamp(),
    });
    if (ride?.driver_id) {
        batch.update(db.collection('drivers').doc(ride.driver_id), {
            is_busy: false,
            current_ride_id: null,
        });
    }
    // Release Rider Reservation (Requirement H)
    batch.set(db.collection('rider_reservations').doc(ride.rider_id), {
        status: 'idle',
        ride_id: null,
        updated_at: getAdmin().firestore.FieldValue.serverTimestamp(),
    });
    await batch.commit();
    // Reliable RTDB availability sync with retry & outbox (Requirement I)
    if (ride?.driver_id) {
        await syncDriverAvailability(ride.driver_id, false, null);
    }
    return { success: true };
}
/**
 * Mutual Rating Submission (Requirement G: Atomic Transaction & Integrity)
 */
export async function executeRateRide(callerUid, rideId, rating, review) {
    // 1. Validate rating bounds (finite number between 1.0 and 5.0)
    if (typeof rating !== 'number' || !Number.isFinite(rating) || rating < 1.0 || rating > 5.0) {
        throw new Error('INVALID_RATING: Rating must be a finite number between 1.0 and 5.0.');
    }
    const db = getAdmin().firestore();
    const rideRef = db.collection('rides').doc(rideId);
    const ratingRecordRef = rideRef.collection('ratings').doc(callerUid);
    return db.runTransaction(async (transaction) => {
        const rideSnap = await transaction.get(rideRef);
        if (!rideSnap.exists)
            throw new Error('RIDE_NOT_FOUND: Ride does not exist.');
        const ride = rideSnap.data();
        // 2. Ratings only permitted after ride completion
        if (ride.status !== 'completed') {
            throw new Error('INVALID_STATE: Ratings are only permitted after ride completion.');
        }
        // 3. Only ride participants may rate
        const isRider = ride.rider_id === callerUid;
        const isDriver = ride.driver_id === callerUid;
        if (!isRider && !isDriver) {
            throw new Error('UNAUTHORIZED: Only ride participants may submit ratings.');
        }
        // 4. One rating per participant per ride (prevent duplicate manipulation)
        const existingRatingSnap = await transaction.get(ratingRecordRef);
        if (existingRatingSnap.exists) {
            throw new Error('ALREADY_RATED: You have already submitted a rating for this ride.');
        }
        const targetUserId = isRider ? ride.driver_id : ride.rider_id;
        if (!targetUserId)
            throw new Error('TARGET_NOT_FOUND: Target user not found.');
        const targetUserRef = isRider
            ? db.collection('drivers').doc(targetUserId)
            : db.collection('users').doc(targetUserId);
        const targetUserSnap = await transaction.get(targetUserRef);
        if (!targetUserSnap.exists)
            throw new Error('TARGET_USER_NOT_FOUND: Profile not found.');
        const targetData = targetUserSnap.data() || {};
        const currentRating = typeof targetData.rating_avg === 'number' ? targetData.rating_avg : 5.0;
        const currentTotalRatings = typeof targetData.total_ratings === 'number' ? targetData.total_ratings : 0;
        // 5. Rolling average calculation
        const newTotalRatings = currentTotalRatings + 1;
        const previousPoints = currentRating * currentTotalRatings;
        const newAverage = Number(((previousPoints + rating) / newTotalRatings).toFixed(2));
        // Record individual rating document
        transaction.set(ratingRecordRef, {
            rater_id: callerUid,
            target_id: targetUserId,
            role: isRider ? 'rider' : 'driver',
            rating: rating,
            review: review ?? null,
            created_at: getAdmin().firestore.FieldValue.serverTimestamp(),
        });
        // Update ride document
        if (isRider) {
            transaction.update(rideRef, {
                driver_rating: rating,
                rider_rated: true,
                rider_review: review ?? null,
            });
        }
        else {
            transaction.update(rideRef, {
                rider_rating: rating,
                driver_rated: true,
            });
        }
        // Update target user document rolling average
        transaction.update(targetUserRef, {
            rating_avg: newAverage,
            total_ratings: newTotalRatings,
        });
        return { success: true };
    });
}
//# sourceMappingURL=rides.js.map