/**
 * Rafik Dynamic Configuration Service
 * Enforces Condition 4: All business rules, pricing parameters, dispatch radiuses,
 * and timeouts are dynamically fetched from Firestore (/app_settings/global).
 * Nothing is hardcoded.
 */

import * as admin from 'firebase-admin';

function getAdmin(): any {
  return (admin as any).default || admin;
}
import { PlatformSettings } from './types.js';

// Default baseline configuration if Firestore document is not yet initialized
export const DEFAULT_PLATFORM_SETTINGS: PlatformSettings = {
  pricing: {
    base_fare_egp: 15.0,
    per_km_rate_egp: 10.0,
    min_fare_egp: 25.0,
    cairo_traffic_multiplier: 1.25,
    platform_commission_rate: 0.0, // 0% platform commission on promotional trips
    night_multiplier: 1.0,
    rafik_girl_premium_multiplier: 1.10,
  },
  dispatch: {
    initial_radius_km: 3.0, // 3 KM initial matching radius confirmed by architecture decision
    expanded_radius_km: 5.0,
    max_radius_km: 7.0,
    expansion_interval_seconds: 30,
    offer_timeout_seconds: 30,
    ride_request_ttl_seconds: 120,
    max_candidate_drivers: 10,
    driver_heartbeat_timeout_seconds: 60,
  },
  safety: {
    max_pin_attempts: 3,
    require_national_id_parity_for_female: true,
    max_arrival_distance_meters: 200,
  },
};

let cachedSettings: PlatformSettings | null = null;
let lastFetchTime = 0;
const CACHE_TTL_MS = 60 * 1000; // 1-minute in-memory cache

export async function getPlatformSettings(forceRefresh = false): Promise<PlatformSettings> {
  const now = Date.now();
  if (!forceRefresh && cachedSettings && (now - lastFetchTime < CACHE_TTL_MS)) {
    return cachedSettings;
  }

  try {
    const db = getAdmin().firestore();
    const docSnap = await db.collection('app_settings').doc('global').get();

    if (docSnap.exists) {
      const data = docSnap.data();
      cachedSettings = {
        pricing: {
          base_fare_egp: Number(data?.pricing?.base_fare_egp ?? DEFAULT_PLATFORM_SETTINGS.pricing.base_fare_egp),
          per_km_rate_egp: Number(data?.pricing?.per_km_rate_egp ?? DEFAULT_PLATFORM_SETTINGS.pricing.per_km_rate_egp),
          min_fare_egp: Number(data?.pricing?.min_fare_egp ?? DEFAULT_PLATFORM_SETTINGS.pricing.min_fare_egp),
          cairo_traffic_multiplier: Number(data?.pricing?.cairo_traffic_multiplier ?? DEFAULT_PLATFORM_SETTINGS.pricing.cairo_traffic_multiplier),
          platform_commission_rate: Number(data?.pricing?.platform_commission_rate ?? DEFAULT_PLATFORM_SETTINGS.pricing.platform_commission_rate),
          night_multiplier: Number(data?.pricing?.night_multiplier ?? DEFAULT_PLATFORM_SETTINGS.pricing.night_multiplier),
          rafik_girl_premium_multiplier: Number(data?.pricing?.rafik_girl_premium_multiplier ?? DEFAULT_PLATFORM_SETTINGS.pricing.rafik_girl_premium_multiplier),
        },
        dispatch: {
          initial_radius_km: Number(data?.dispatch?.initial_radius_km ?? DEFAULT_PLATFORM_SETTINGS.dispatch.initial_radius_km),
          expanded_radius_km: Number(data?.dispatch?.expanded_radius_km ?? DEFAULT_PLATFORM_SETTINGS.dispatch.expanded_radius_km),
          max_radius_km: Number(data?.dispatch?.max_radius_km ?? DEFAULT_PLATFORM_SETTINGS.dispatch.max_radius_km),
          expansion_interval_seconds: Number(data?.dispatch?.expansion_interval_seconds ?? DEFAULT_PLATFORM_SETTINGS.dispatch.expansion_interval_seconds),
          offer_timeout_seconds: Number(data?.dispatch?.offer_timeout_seconds ?? DEFAULT_PLATFORM_SETTINGS.dispatch.offer_timeout_seconds),
          ride_request_ttl_seconds: Number(data?.dispatch?.ride_request_ttl_seconds ?? DEFAULT_PLATFORM_SETTINGS.dispatch.ride_request_ttl_seconds),
          max_candidate_drivers: Number(data?.dispatch?.max_candidate_drivers ?? DEFAULT_PLATFORM_SETTINGS.dispatch.max_candidate_drivers),
          driver_heartbeat_timeout_seconds: Number(data?.dispatch?.driver_heartbeat_timeout_seconds ?? DEFAULT_PLATFORM_SETTINGS.dispatch.driver_heartbeat_timeout_seconds),
        },
        safety: {
          max_pin_attempts: Number(data?.safety?.max_pin_attempts ?? DEFAULT_PLATFORM_SETTINGS.safety.max_pin_attempts),
          require_national_id_parity_for_female: Boolean(data?.safety?.require_national_id_parity_for_female ?? DEFAULT_PLATFORM_SETTINGS.safety.require_national_id_parity_for_female),
          max_arrival_distance_meters: Number(data?.safety?.max_arrival_distance_meters ?? DEFAULT_PLATFORM_SETTINGS.safety.max_arrival_distance_meters),
        },
      };
    } else {
      // First-time bootstrap: write default settings into Firestore
      await db.collection('app_settings').doc('global').set(DEFAULT_PLATFORM_SETTINGS);
      cachedSettings = DEFAULT_PLATFORM_SETTINGS;
    }
  } catch (error) {
    console.warn('[Config] Failed to fetch settings from Firestore, using defaults:', error);
    cachedSettings = cachedSettings ?? DEFAULT_PLATFORM_SETTINGS;
  }

  lastFetchTime = now;
  return cachedSettings;
}

export function invalidateSettingsCache(): void {
  cachedSettings = null;
  lastFetchTime = 0;
}
