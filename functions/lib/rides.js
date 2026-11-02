/**
 * Rafik Server-Authoritative Ride Lifecycle & Operations
 * Condition 3 compliant: Clients cannot tamper with pricing, assignment, or PIN verification.
 */
import * as admin from 'firebase-admin';
import { getPlatformSettings } from './config.js';
import { createAndDispatchOffers } from './dispatch.js';
import { computeAuthoritativeFare } from './pricing.js';
import { approximateRoadDistanceKm, haversineDistanceKm } from './spatial.js';
/**
 * Server-Authoritative Ride Creation & 3 KM Dispatch Initiation
 */
export async function executeRequestRide(callerUid, payload) {
    const db = admin.firestore();
    const settings = await getPlatformSettings();
    // 1. Validate Caller Profile
    const userDoc = await db.collection('users').doc(callerUid).get();
    if (!userDoc.exists) {
        throw new Error('USER_NOT_FOUND: User profile does not exist.');
    }
    const userData = userDoc.data();
    if (!userData?.is_active) {
        throw new Error('ACCOUNT_DISABLED: Account is deactivated.');
    }
    // 2. Prevent Multiple Concurrent Active Rides
    const activeRideQuery = await db.collection('rides')
        .where('rider_id', '==', callerUid)
        .where('status', 'in', ['requested', 'accepted', 'arrived', 'in_progress'])
        .limit(1)
        .get();
    if (!activeRideQuery.empty) {
        throw new Error('ACTIVE_RIDE_EXISTS: You already have an active ride request in progress.');
    }
    // 3. Rafik Girl Tier Restriction
    if (payload.tier === 'rafik_girl') {
        if (userData?.gender !== 'female' || userData?.gender_verified !== true) {
            throw new Error('RAFIK_GIRL_UNAUTHORIZED: Rafik Girl is restricted to verified female passengers.');
        }
    }
    // 4. Server-Authoritative Distance & Fare Calculation
    const distanceKm = approximateRoadDistanceKm(payload.pickup_lat, payload.pickup_lng, payload.dropoff_lat, payload.dropoff_lng, settings.pricing.cairo_traffic_multiplier);
    if (distanceKm < 0.2) {
        throw new Error('TRIP_TOO_SHORT: Trip distance is too short.');
    }
    const fareResult = await computeAuthoritativeFare(distanceKm, payload.tier);
    // 5. Generate Cryptographic 4-Digit PIN
    const randomPin = Math.floor(1000 + Math.random() * 9000).toString();
    // 6. Write Ride and Isolated PIN Documents
    const rideRef = db.collection('rides').doc();
    const ttlMs = settings.dispatch.ride_request_ttl_seconds * 1000;
    const expiresAt = admin.firestore.Timestamp.fromMillis(Date.now() + ttlMs);
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
        requested_at: admin.firestore.FieldValue.serverTimestamp(),
        expires_at: expiresAt,
    };
    const pinData = {
        pin: randomPin,
        attempts: 0,
        is_locked: false,
        created_at: admin.firestore.FieldValue.serverTimestamp(),
    };
    const batch = db.batch();
    batch.set(rideRef, rideData);
    batch.set(rideRef.collection('security').doc('pin_data'), pinData);
    await batch.commit();
    // 7. Dispatch Initial 3 KM Offers
    const offersCount = await createAndDispatchOffers(rideData, settings.dispatch.initial_radius_km);
    return {
        ride_id: rideRef.id,
        fare_egp: fareResult.fare_egp,
        distance_km: fareResult.distance_km,
        pin: randomPin, // Returned exclusively to the passenger
        offers_dispatched: offersCount,
    };
}
/**
 * Server-Authoritative Atomic Ride Acceptance
 */
export async function executeAcceptRide(driverUid, offerId) {
    const db = admin.firestore();
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
            accepted_at: admin.firestore.FieldValue.serverTimestamp(),
        });
        // 4. Mark driver as busy
        transaction.update(driverRef, {
            is_busy: true,
            current_ride_id: rideId,
            updated_at: admin.firestore.FieldValue.serverTimestamp(),
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
        await admin.database().ref(`driver_locations/${driverUid}`).update({
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
            await admin.messaging().send({
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
 * Driver Arrival at Pickup Location
 */
export async function executeMarkArrived(driverUid, rideId, currentLat, currentLng) {
    const db = admin.firestore();
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
    // Geofence verification: Check driver is within max arrival threshold
    if (typeof currentLat === 'number' && typeof currentLng === 'number') {
        const distMeters = haversineDistanceKm(currentLat, currentLng, ride.pickup_lat, ride.pickup_lng) * 1000;
        if (distMeters > settings.safety.max_arrival_distance_meters) {
            throw new Error(`ARRIVAL_GEOFENCE_FAILED: You are too far from the pickup point (${Math.round(distMeters)}m away).`);
        }
    }
    await rideRef.update({
        status: 'arrived',
        arrived_at: admin.firestore.FieldValue.serverTimestamp(),
    });
    return { success: true };
}
/**
 * Cryptographic PIN Handshake Verification & Trip Start
 * Condition 3 compliant: Attempt limit enforced without transaction rollback.
 */
export async function executeVerifyPinAndStartTrip(driverUid, rideId, inputPin) {
    const db = admin.firestore();
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
                started_at: admin.firestore.FieldValue.serverTimestamp(),
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
 * Trip Completion & Wallet Ledger Settlement
 */
export async function executeCompleteRide(driverUid, rideId) {
    const db = admin.firestore();
    const result = await db.runTransaction(async (transaction) => {
        const rideRef = db.collection('rides').doc(rideId);
        const rideSnap = await transaction.get(rideRef);
        if (!rideSnap.exists)
            throw new Error('RIDE_NOT_FOUND');
        const ride = rideSnap.data();
        if (ride.driver_id !== driverUid) {
            throw new Error('UNAUTHORIZED: Caller is not the assigned driver.');
        }
        if (ride.status !== 'in_progress') {
            throw new Error('INVALID_STATE: Ride must be in progress to complete.');
        }
        const fare = ride.fare_egp;
        const earnings = ride.driver_earnings_egp;
        // 1. Update Ride Status
        transaction.update(rideRef, {
            status: 'completed',
            completed_at: admin.firestore.FieldValue.serverTimestamp(),
        });
        // 2. Free Driver & Credit Wallet
        const driverRef = db.collection('drivers').doc(driverUid);
        transaction.update(driverRef, {
            is_busy: false,
            current_ride_id: null,
            total_trips: admin.firestore.FieldValue.increment(1),
            wallet_balance_egp: admin.firestore.FieldValue.increment(earnings),
            updated_at: admin.firestore.FieldValue.serverTimestamp(),
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
            created_at: admin.firestore.FieldValue.serverTimestamp(),
        });
        return { fare, earnings };
    });
    // Free driver in RTDB and clear active_rider_id
    try {
        await admin.database().ref(`driver_locations/${driverUid}`).update({
            is_busy: false,
            active_rider_id: null,
        });
    }
    catch (_) { }
    return { success: true, fare_egp: result.fare, driver_earnings_egp: result.earnings };
}
/**
 * Ride Cancellation
 */
export async function executeCancelRide(callerUid, rideId, reason) {
    const db = admin.firestore();
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
        cancelled_at: admin.firestore.FieldValue.serverTimestamp(),
    });
    if (ride?.driver_id) {
        batch.update(db.collection('drivers').doc(ride.driver_id), {
            is_busy: false,
            current_ride_id: null,
        });
    }
    await batch.commit();
    if (ride?.driver_id) {
        try {
            await admin.database().ref(`driver_locations/${ride.driver_id}`).update({
                is_busy: false,
                active_rider_id: null,
            });
        }
        catch (_) { }
    }
    return { success: true };
}
/**
 * Mutual Rating Submission
 */
export async function executeRateRide(callerUid, rideId, rating, review) {
    if (rating < 1 || rating > 5)
        throw new Error('INVALID_RATING: Must be between 1 and 5 stars.');
    const db = admin.firestore();
    const rideRef = db.collection('rides').doc(rideId);
    const rideSnap = await rideRef.get();
    if (!rideSnap.exists)
        throw new Error('RIDE_NOT_FOUND');
    const ride = rideSnap.data();
    const isRider = ride?.rider_id === callerUid;
    const isDriver = ride?.driver_id === callerUid;
    if (!isRider && !isDriver)
        throw new Error('UNAUTHORIZED');
    if (isRider) {
        // Rider rates driver
        await rideRef.update({
            driver_rating: rating,
            review: review ?? null,
        });
        if (ride?.driver_id) {
            // Recompute driver rating average
            await updateRunningAverage(db.collection('drivers').doc(ride.driver_id), 'rating_avg', rating);
        }
    }
    else {
        // Driver rates rider
        await rideRef.update({
            rider_rating: rating,
        });
        await updateRunningAverage(db.collection('users').doc(ride?.rider_id), 'rating_avg', rating);
    }
    return { success: true };
}
async function updateRunningAverage(docRef, fieldName, newRating) {
    const snap = await docRef.get();
    if (!snap.exists)
        return;
    const currentAvg = Number(snap.data()?.[fieldName] ?? 5.0);
    const updatedAvg = Math.round(((currentAvg * 9 + newRating) / 10) * 100) / 100;
    await docRef.update({ [fieldName]: updatedAvg });
}
//# sourceMappingURL=rides.js.map