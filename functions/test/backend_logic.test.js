import { describe, it } from 'node:test';
import assert from 'node:assert/strict';

import {
  haversineDistanceKm,
  approximateRoadDistanceKm,
  nationalIdGender,
  normalizeEgyptianPhone,
} from '../lib/spatial.js';

import { computeAuthoritativeFare } from '../lib/pricing.js';
import { DEFAULT_PLATFORM_SETTINGS } from '../lib/config.js';

describe('Rafik Backend Logic & Security Verification', () => {

  describe('1. Spatial & Cairo Distance Formulas', () => {
    it('calculates Haversine distance accurately between Tahrir Square and AUC New Cairo', () => {
      // Tahrir: (30.0444, 31.2357), AUC New Cairo: (30.0131, 31.4989)
      const dist = haversineDistanceKm(30.0444, 31.2357, 30.0131, 31.4989);
      // Direct distance is approximately 25.5 km
      assert.ok(dist >= 25.0 && dist <= 26.5, `Expected ~25.5 km, got ${dist}`);
    });

    it('calculates short distance accurately (under 3 KM radius)', () => {
      // Tahrir (30.0444, 31.2357) to Zamalek 26th July St (30.0571, 31.2215)
      const dist = haversineDistanceKm(30.0444, 31.2357, 30.0571, 31.2215);
      // Distance is ~1.95 km (well within the 3.0 KM dispatch threshold)
      assert.ok(dist < 3.0, `Expected within 3.0 km, got ${dist}`);
    });

    it('applies Cairo traffic multiplier (1.25) to road distance', () => {
      const roadDist = approximateRoadDistanceKm(30.0444, 31.2357, 30.0571, 31.2215, 1.25);
      const direct = haversineDistanceKm(30.0444, 31.2357, 30.0571, 31.2215);
      assert.equal(roadDist, Math.round(direct * 1.25 * 100) / 100);
    });
  });

  describe('2. Egyptian Demographics & Verification', () => {
    it('verifies Egyptian National ID 13th digit parity (Even = Female, Odd = Male)', () => {
      // 14 digits, 13th digit (index 12) is 4 (even -> female)
      assert.equal(nationalIdGender('29804150102844'), 'female');
      // 13th digit is 8 (even -> female)
      assert.equal(nationalIdGender('29810140102468'), 'female');
      // 13th digit is 3 (odd -> male)
      assert.equal(nationalIdGender('29501010101132'), 'male');
      // 13th digit is 1 (odd -> male)
      assert.equal(nationalIdGender('30105020104119'), 'male');
      // Invalid formats
      assert.equal(nationalIdGender('12345'), null);
      assert.equal(nationalIdGender('invalid_nid_14'), null);
    });

    it('validates and normalizes Egyptian mobile numbers to E.164 (+201XXXXXXXXX)', () => {
      // Vodafone (010)
      assert.equal(normalizeEgyptianPhone('01012345678'), '+201012345678');
      assert.equal(normalizeEgyptianPhone('+201012345678'), '+201012345678');
      assert.equal(normalizeEgyptianPhone('00201012345678'), '+201012345678');

      // Orange (012)
      assert.equal(normalizeEgyptianPhone('01229876543'), '+201229876543');

      // Etisalat (011)
      assert.equal(normalizeEgyptianPhone('01145678901'), '+201145678901');

      // WE (015)
      assert.equal(normalizeEgyptianPhone('01598765432'), '+201598765432');

      // Invalid operator / length
      assert.equal(normalizeEgyptianPhone('01312345678'), null); // 013 is not mobile
      assert.equal(normalizeEgyptianPhone('010123456'), null); // too short
      assert.equal(normalizeEgyptianPhone('abcdefghijk'), null);
    });
  });

  describe('3. Dynamic Configurable Pricing Engine', () => {
    it('enforces minimum fare (25 EGP) for short trips under standard settings', async () => {
      // 0.5 km: base 15 + 0.5*10 = 20 -> clamped to 25.00 EGP
      const res = await computeAuthoritativeFare(0.5, 'standard', false, DEFAULT_PLATFORM_SETTINGS);
      assert.equal(res.fare_egp, 25.00);
      assert.equal(res.driver_earnings_egp, 25.00); // 0% commission
      assert.equal(res.platform_fee_egp, 0.00);
    });

    it('calculates fare correctly for a 15 km trip under standard settings', async () => {
      // 15 km: base 15 + 15*10 = 165.00 EGP
      const res = await computeAuthoritativeFare(15.0, 'standard', false, DEFAULT_PLATFORM_SETTINGS);
      assert.equal(res.fare_egp, 165.00);
      assert.equal(res.driver_earnings_egp, 165.00);
      assert.equal(res.platform_fee_egp, 0.00);
    });

    it('supports runtime dynamic settings override without code modification', async () => {
      const customSettings = {
        ...DEFAULT_PLATFORM_SETTINGS,
        pricing: {
          ...DEFAULT_PLATFORM_SETTINGS.pricing,
          base_fare_egp: 20.0,
          per_km_rate_egp: 12.0,
          min_fare_egp: 35.0,
          platform_commission_rate: 0.10, // 10% commission
        },
      };

      // 10 km: base 20 + 10*12 = 140 EGP. Commission: 10% -> 14 EGP. Driver: 126 EGP.
      const res = await computeAuthoritativeFare(10.0, 'standard', false, customSettings);
      assert.equal(res.fare_egp, 140.00);
      assert.equal(res.driver_earnings_egp, 126.00);
      assert.equal(res.platform_fee_egp, 14.00);
    });

    it('respects Rafik Girl premium multiplier when configured', async () => {
      const girlSettings = {
        ...DEFAULT_PLATFORM_SETTINGS,
        pricing: {
          ...DEFAULT_PLATFORM_SETTINGS.pricing,
          rafik_girl_premium_multiplier: 1.15, // 15% safety tier premium
        },
      };

      // 10 km standard: 15 + 100 = 115 EGP. Girl tier (1.15x): 115 * 1.15 = 132.25 EGP
      const resStandard = await computeAuthoritativeFare(10.0, 'standard', false, girlSettings);
      const resGirl = await computeAuthoritativeFare(10.0, 'rafik_girl', false, girlSettings);

      assert.equal(resStandard.fare_egp, 115.00);
      assert.equal(resGirl.fare_egp, 132.25);
    });
  });

  describe('4. Dispatch Filtering & Initial Radius (3 KM)', () => {
    it('verifies that initial matching radius is 3.0 KM', () => {
      assert.equal(DEFAULT_PLATFORM_SETTINGS.dispatch.initial_radius_km, 3.0);
    });

    it('verifies expanded radius tiers (5.0 KM and 7.0 KM)', () => {
      assert.equal(DEFAULT_PLATFORM_SETTINGS.dispatch.expanded_radius_km, 5.0);
      assert.equal(DEFAULT_PLATFORM_SETTINGS.dispatch.max_radius_km, 7.0);
    });

    it('verifies offer timeout (30s) and ride request total TTL (120s)', () => {
      assert.equal(DEFAULT_PLATFORM_SETTINGS.dispatch.offer_timeout_seconds, 30);
      assert.equal(DEFAULT_PLATFORM_SETTINGS.dispatch.ride_request_ttl_seconds, 120);
    });

    it('verifies PIN safety attempt lockout maximum (3 attempts)', () => {
      assert.equal(DEFAULT_PLATFORM_SETTINGS.safety.max_pin_attempts, 3);
    });
  });

});
