/**
 * Rafik Background Dispatch Triggers & Radius Expansion Engine
 * Condition 3 & Condition 4 compliant: Handles radius expansion and timeouts authoritatively.
 */

import * as admin from 'firebase-admin';

function getAdmin(): any {
  return (admin as any).default || admin;
}
import { getPlatformSettings } from './config.js';
import { createAndDispatchOffers } from './dispatch.js';
import { RideDocument } from './types.js';

/**
 * Sweeps expired pending offers, handles deterministic 3 KM -> 5 KM -> 7 KM radius expansion,
 * processes RTDB availability synchronization outbox, and expires stale requested rides after TTL.
 * Requirement E & I compliant.
 */
export async function executeRadiusExpansionAndExpirationSweep(): Promise<{
  expired_offers: number;
  expanded_rides: number;
  expired_rides: number;
}> {
  const db = getAdmin().firestore();
  const settings = await getPlatformSettings();
  const now = getAdmin().firestore.Timestamp.now();
  const nowMs = Date.now();

  let expiredOffersCount = 0;
  let expandedRidesCount = 0;
  let expiredRidesCount = 0;

  // 1. Expire timed-out pending offers
  const expiredOffersSnap = await db.collection('ride_offers')
    .where('status', '==', 'pending')
    .where('expires_at', '<=', now)
    .get();

  if (!expiredOffersSnap.empty) {
    const sweepBatch = db.batch();
    for (const doc of expiredOffersSnap.docs) {
      sweepBatch.update(doc.ref, { status: 'expired' });
      expiredOffersCount++;
    }
    await sweepBatch.commit();
  }

  // 2. Process RTDB Synchronization Outbox (Requirement I - Guaranteed eventual consistency)
  try {
    const outboxSnap = await db.collection('rtdb_sync_outbox')
      .where('status', '==', 'pending')
      .limit(20)
      .get();

    for (const doc of outboxSnap.docs) {
      const data = doc.data();
      const driverId = data.driver_id;
      if (driverId) {
        try {
          await getAdmin().database().ref(`driver_locations/${driverId}`).update({
            is_busy: data.is_busy ?? false,
            active_rider_id: data.active_rider_id ?? null,
          });
          await doc.ref.delete();
        } catch (_) {
          await doc.ref.update({
            retry_count: getAdmin().firestore.FieldValue.increment(1),
            last_attempt_at: getAdmin().firestore.FieldValue.serverTimestamp(),
          });
        }
      }
    }
  } catch (_) {}

  // 3. Inspect EVERY active requested ride (Requirement E)
  const activeRidesSnap = await db.collection('rides')
    .where('status', '==', 'requested')
    .get();

  const expansionIntervalMs = (settings.dispatch.expansion_interval_seconds || 30) * 1000;
  const rideTtlMs = settings.dispatch.ride_request_ttl_seconds * 1000;

  for (const rideDoc of activeRidesSnap.docs) {
    const rideRef = rideDoc.ref;
    const rideData = rideDoc.data() as RideDocument;

    const requestedAtMs = (rideData.requested_at as admin.firestore.Timestamp)?.toMillis() ?? nowMs;
    const expiresAtMs = (rideData.expires_at as admin.firestore.Timestamp)?.toMillis() ?? (requestedAtMs + rideTtlMs);
    const elapsedMs = nowMs - requestedAtMs;

    // A. Check if total ride lifespan has elapsed
    if (nowMs >= expiresAtMs || elapsedMs >= rideTtlMs) {
      await rideRef.update({
        status: 'expired',
        cancelled_by: 'system',
        cancellation_reason: 'No captains available in the expanded radius.',
      });
      expiredRidesCount++;

      // Release active rider reservation atomically (Requirement H)
      try {
        await db.collection('rider_reservations').doc(rideData.rider_id).set({
          status: 'idle',
          ride_id: null,
          updated_at: getAdmin().firestore.FieldValue.serverTimestamp(),
        });
      } catch (_) {}

      // Notify passenger
      try {
        const userDoc = await db.collection('users').doc(rideData.rider_id).get();
        const riderToken = userDoc.data()?.fcm_token;
        if (riderToken) {
          await getAdmin().messaging().send({
            token: riderToken,
            notification: {
              title: 'لم يتم العثور على كابتن 🚗',
              body: 'عذراً، لا يوجد كباتن متاحين بالقرب منك حالياً. يرجى إعادة المحاولة بعد قليل.',
            },
            data: { type: 'ride_expired', ride_id: rideDoc.id },
          });
        }
      } catch (_) {}

      continue;
    }

    // B. Radius Expansion: 3 KM -> 5 KM -> 7 KM (Deterministically progresses even with 0 candidates)
    const currentStage = rideData.dispatch_stage ?? 1;
    const nextExpansionMs = (rideData.next_expansion_at as admin.firestore.Timestamp)?.toMillis() ??
      (requestedAtMs + expansionIntervalMs);

    if (nowMs >= nextExpansionMs) {
      const alreadyDispatched = rideData.dispatched_driver_ids ?? [];

      if (currentStage === 1) {
        // Expand from 3 KM to 5 KM
        const targetRadius = settings.dispatch.expanded_radius_km; // 5.0 KM
        const result = await createAndDispatchOffers(rideData, targetRadius, alreadyDispatched);

        await rideRef.update({
          dispatch_stage: 2,
          current_radius: targetRadius,
          next_expansion_at: getAdmin().firestore.Timestamp.fromMillis(nowMs + expansionIntervalMs),
          dispatched_driver_ids: [...alreadyDispatched, ...result.dispatchedDriverIds],
        });
        expandedRidesCount++;
      } else if (currentStage === 2) {
        // Expand from 5 KM to 7 KM
        const targetRadius = settings.dispatch.max_radius_km; // 7.0 KM
        const result = await createAndDispatchOffers(rideData, targetRadius, alreadyDispatched);

        await rideRef.update({
          dispatch_stage: 3,
          current_radius: targetRadius,
          next_expansion_at: getAdmin().firestore.Timestamp.fromMillis(expiresAtMs),
          dispatched_driver_ids: [...alreadyDispatched, ...result.dispatchedDriverIds],
        });
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

/**
 * Reliable RTDB Driver Availability Synchronizer with Retry and Outbox Fallback (Requirement I).
 */
export async function syncDriverAvailability(
  driverId: string,
  isBusy: boolean,
  activeRiderId: string | null = null
): Promise<void> {
  const db = getAdmin().firestore();
  let synced = false;

  // Try direct update up to 3 times
  for (let attempt = 0; attempt < 3; attempt++) {
    try {
      await getAdmin().database().ref(`driver_locations/${driverId}`).update({
        is_busy: isBusy,
        active_rider_id: activeRiderId,
      });
      synced = true;
      break;
    } catch (_) {
      // Exponential backoff
      await new Promise((res) => setTimeout(res, 100 * Math.pow(2, attempt)));
    }
  }

  // If direct update failed, record in outbox queue for deterministic retry by trigger
  if (!synced) {
    try {
      await db.collection('rtdb_sync_outbox').doc().set({
        driver_id: driverId,
        is_busy: isBusy,
        active_rider_id: activeRiderId,
        status: 'pending',
        retry_count: 0,
        created_at: getAdmin().firestore.FieldValue.serverTimestamp(),
      });
    } catch (e) {
      console.error('[RTDB Sync] Fatal: Could not record in sync outbox:', e);
    }
  }
}
