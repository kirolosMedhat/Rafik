/**
 * Rafik Intelligent Dispatch Engine
 * Enforces 3 KM initial radius matching, service-tier isolation,
 * individual ride offers, and Realtime Database telemetry integration.
 */

import * as admin from 'firebase-admin';

function getAdmin(): any {
  return (admin as any).default || admin;
}
import { getPlatformSettings } from './config.js';
import { haversineDistanceKm } from './spatial.js';
import { RideDocument, RideOfferDocument, RideTier, RTDBDriverLocation } from './types.js';

export interface CandidateDriver {
  driver_id: string;
  distance_km: number;
  lat: number;
  lng: number;
}

/**
 * Queries Realtime Database for all candidate drivers within radiusKm,
 * enforcing status, presence heartbeat, and Rafik Girl gender eligibility.
 */
export async function findNearbyEligibleDrivers(
  pickupLat: number,
  pickupLng: number,
  tier: RideTier,
  radiusKm: number
): Promise<CandidateDriver[]> {
  const settings = await getPlatformSettings();
  const heartbeatLimitMs = settings.dispatch.driver_heartbeat_timeout_seconds * 1000;
  const now = Date.now();

  const rtdb = getAdmin().database();
  const snapshot = await rtdb.ref('driver_locations').once('value');
  const locationsMap = snapshot.val() as Record<string, RTDBDriverLocation> | null;

  if (!locationsMap) {
    return [];
  }

  const eligible: CandidateDriver[] = [];

  for (const [driverId, loc] of Object.entries(locationsMap)) {
    // 1. Verify availability flags
    if (!loc.is_online || loc.is_busy) continue;
    if (loc.status && loc.status !== 'approved') continue;

    // 2. Verify recent telemetry heartbeat (server-authoritative freshness)
    if (!loc.updated_at || typeof loc.updated_at !== 'number') {
      continue;
    }
    // Reject future timestamps (> 5s clock skew buffer) and stale telemetry (> heartbeatLimitMs)
    if (loc.updated_at > now + 5000 || (now - loc.updated_at > heartbeatLimitMs)) {
      continue;
    }

    // 3. Service Tier Restrictions: Rafik Girl requires verified female captain
    if (tier === 'rafik_girl') {
      if (loc.gender !== 'female' || loc.gender_verified !== true) {
        continue;
      }
    }

    // 4. Spatial distance filter
    if (typeof loc.lat !== 'number' || typeof loc.lng !== 'number') continue;
    const distKm = haversineDistanceKm(pickupLat, pickupLng, loc.lat, loc.lng);

    if (distKm <= radiusKm) {
      eligible.push({
        driver_id: driverId,
        distance_km: Math.round(distKm * 100) / 100,
        lat: loc.lat,
        lng: loc.lng,
      });
    }
  }

  // Sort candidate captains by proximity to pickup
  eligible.sort((a, b) => a.distance_km - b.distance_km);

  // Return top closest candidates (capped by config)
  return eligible.slice(0, settings.dispatch.max_candidate_drivers);
}

/**
 * Creates individual targeted ride offers in Firestore and dispatches FCM alerts.
 */
export async function createAndDispatchOffers(
  ride: RideDocument,
  radiusKm: number,
  excludedDriverIds: string[] = []
): Promise<{ count: number; dispatchedDriverIds: string[] }> {
  const settings = await getPlatformSettings();
  const allCandidates = await findNearbyEligibleDrivers(
    ride.pickup_lat,
    ride.pickup_lng,
    ride.tier,
    radiusKm
  );

  // Filter out drivers who already received an offer for this ride
  const candidates = allCandidates.filter(
    (c) => !excludedDriverIds.includes(c.driver_id)
  );

  if (candidates.length === 0) {
    return { count: 0, dispatchedDriverIds: [] };
  }

  const db = getAdmin().firestore();
  const batch = db.batch();
  const offerTtlMs = settings.dispatch.offer_timeout_seconds * 1000;
  const expiresAt = getAdmin().firestore.Timestamp.fromMillis(Date.now() + offerTtlMs);

  const offerIds: string[] = [];
  const targetTokens: string[] = [];
  const newlyDispatchedDriverIds: string[] = [];

  for (const candidate of candidates) {
    const offerRef = db.collection('ride_offers').doc();
    const offerData: RideOfferDocument = {
      offer_id: offerRef.id,
      ride_id: ride.ride_id,
      driver_id: candidate.driver_id,
      tier: ride.tier,
      pickup_address: ride.pickup_address,
      dropoff_address: ride.dropoff_address,
      distance_km: ride.distance_km,
      fare_egp: ride.fare_egp,
      status: 'pending',
      offered_at: getAdmin().firestore.FieldValue.serverTimestamp(),
      expires_at: expiresAt,
    };
    batch.set(offerRef, offerData);
    offerIds.push(offerRef.id);
    newlyDispatchedDriverIds.push(candidate.driver_id);

    // Look up driver's FCM token from RTDB or Firestore active_sessions
    try {
      let token: string | null = null;
      const sessionSnap = await getAdmin().database().ref(`active_sessions/${candidate.driver_id}/fcm_token`).once('value');
      if (sessionSnap.exists() && typeof sessionSnap.val() === 'string') {
        token = sessionSnap.val();
      }
      if (!token) {
        const firestoreSession = await db.collection('active_sessions').doc(candidate.driver_id).get();
        if (firestoreSession.exists && typeof firestoreSession.data()?.fcm_token === 'string') {
          token = firestoreSession.data()?.fcm_token;
        }
      }
      if (token && typeof token === 'string' && token.length > 0) {
        targetTokens.push(token);
      }
    } catch (_) {}
  }

  await batch.commit();

  // Send FCM High-Priority Data Push (Wakeup Alert) to candidate drivers
  if (targetTokens.length > 0) {
    try {
      await getAdmin().messaging().sendEachForMulticast({
        tokens: targetTokens,
        data: {
          type: 'ride_offer',
          ride_id: ride.ride_id,
          tier: ride.tier,
          fare_egp: ride.fare_egp.toString(),
          pickup: ride.pickup_address,
          dropoff: ride.dropoff_address,
          distance_km: ride.distance_km.toString(),
          timeout_seconds: settings.dispatch.offer_timeout_seconds.toString(),
        },
        android: {
          priority: 'high',
          notification: {
            title: ride.tier === 'rafik_girl' ? 'طلب رفيق جيرل جديد 🚗' : 'طلب رحلة جديد في منطقتك 🚗',
            body: `${ride.pickup_address} • ${ride.fare_egp} ج.م`,
            sound: 'default',
            channelId: 'dispatch_offers',
          },
        },
      });
    } catch (pushError) {
      console.warn('[Dispatch] FCM broadcast note:', pushError);
    }
  }

  return { count: offerIds.length, dispatchedDriverIds: newlyDispatchedDriverIds };
}
