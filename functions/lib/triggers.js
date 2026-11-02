/**
 * Rafik Background Dispatch Triggers & Radius Expansion Engine
 * Condition 3 & Condition 4 compliant: Handles radius expansion and timeouts authoritatively.
 */
import * as admin from 'firebase-admin';
import { getPlatformSettings } from './config.js';
import { createAndDispatchOffers } from './dispatch.js';
/**
 * Sweeps expired pending offers, handles 3 KM -> 5 KM -> 7 KM radius expansion,
 * and expires stale requested rides after TTL.
 */
export async function executeRadiusExpansionAndExpirationSweep() {
    const db = admin.firestore();
    const settings = await getPlatformSettings();
    const now = admin.firestore.Timestamp.now();
    const nowMs = Date.now();
    let expiredOffersCount = 0;
    let expandedRidesCount = 0;
    let expiredRidesCount = 0;
    // 1. Expire timed-out pending offers
    const expiredOffersSnap = await db.collection('ride_offers')
        .where('status', '==', 'pending')
        .where('expires_at', '<=', now)
        .get();
    const sweepBatch = db.batch();
    const ridesToInspect = new Set();
    for (const doc of expiredOffersSnap.docs) {
        sweepBatch.update(doc.ref, { status: 'expired' });
        ridesToInspect.add(doc.data().ride_id);
        expiredOffersCount++;
    }
    await sweepBatch.commit();
    // 2. Inspect active requested rides for radius expansion or total expiration
    for (const rideId of ridesToInspect) {
        const rideRef = db.collection('rides').doc(rideId);
        const rideSnap = await rideRef.get();
        if (!rideSnap.exists)
            continue;
        const rideData = rideSnap.data();
        if (rideData.status !== 'requested')
            continue;
        const requestedAtMs = rideData.requested_at?.toMillis() ?? nowMs;
        const elapsedSeconds = (nowMs - requestedAtMs) / 1000;
        // A. Check if total ride lifespan has elapsed (default: 120s)
        if (elapsedSeconds >= settings.dispatch.ride_request_ttl_seconds) {
            await rideRef.update({
                status: 'expired',
                cancelled_by: 'system',
                cancellation_reason: 'No captains available in the expanded radius.',
            });
            expiredRidesCount++;
            // Notify passenger
            try {
                const userDoc = await db.collection('users').doc(rideData.rider_id).get();
                const riderToken = userDoc.data()?.fcm_token;
                if (riderToken) {
                    await admin.messaging().send({
                        token: riderToken,
                        notification: {
                            title: 'لم يتم العثور على كابتن 🚗',
                            body: 'عذراً، لا يوجد كباتن متاحين بالقرب منك حالياً. يرجى إعادة المحاولة بعد قليل.',
                        },
                        data: { type: 'ride_expired', ride_id: rideId },
                    });
                }
            }
            catch (_) { }
            continue;
        }
        // B. Check if all existing offers are expired or declined
        const remainingActiveOffers = await db.collection('ride_offers')
            .where('ride_id', '==', rideId)
            .where('status', '==', 'pending')
            .get();
        if (remainingActiveOffers.empty) {
            // Expand radius to expanded_radius_km (5 KM) or max_radius_km (7 KM)
            const targetRadius = elapsedSeconds > 60
                ? settings.dispatch.max_radius_km
                : settings.dispatch.expanded_radius_km;
            const newOffersCount = await createAndDispatchOffers(rideData, targetRadius);
            if (newOffersCount > 0) {
                expandedRidesCount++;
            }
        }
    }
    return {
        expired_offers: expiredOffersCount,
        expanded_rides: expandedRidesCount,
        expired_rides: expiredRidesCount,
    };
}
//# sourceMappingURL=triggers.js.map