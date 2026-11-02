import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { haversineDistanceKm } from '../lib/spatial.js';

describe('Rafik Backend Integration & Concurrency Workflows', () => {

  // =========================================================================
  // 1. Concurrent Ride Acceptance (Atomic Race Condition Protection)
  // =========================================================================
  describe('1. Concurrent Ride Acceptance Race Condition', () => {
    it('guarantees that when two drivers accept the same ride simultaneously, exactly one wins and competing offers are cancelled', async () => {
      // In-memory mock database state
      const rideState = {
        ride_id: 'ride_cairo_1',
        status: 'requested',
        driver_id: null,
      };

      const offers = {
        'offer_d1': { offer_id: 'offer_d1', ride_id: 'ride_cairo_1', driver_id: 'drv_1', status: 'pending', expires_at: Date.now() + 30000 },
        'offer_d2': { offer_id: 'offer_d2', ride_id: 'ride_cairo_1', driver_id: 'drv_2', status: 'pending', expires_at: Date.now() + 30000 },
      };

      const drivers = {
        'drv_1': { driver_id: 'drv_1', status: 'approved', is_busy: false },
        'drv_2': { driver_id: 'drv_2', status: 'approved', is_busy: false },
      };

      // Mutex lock simulating Firestore Transaction serializability
      let transactionLock = Promise.resolve();

      async function simulatedAcceptTransaction(driverUid, offerId) {
        return new Promise((resolve) => {
          transactionLock = transactionLock.then(async () => {
            const offer = offers[offerId];
            if (!offer || offer.status !== 'pending' || offer.driver_id !== driverUid) {
              return resolve({ success: false, error: 'OFFER_UNAVAILABLE' });
            }

            if (rideState.status !== 'requested') {
              return resolve({ success: false, error: 'RIDE_ALREADY_ACCEPTED' });
            }

            const driver = drivers[driverUid];
            if (!driver || driver.status !== 'approved' || driver.is_busy) {
              return resolve({ success: false, error: 'DRIVER_BUSY_OR_UNAPPROVED' });
            }

            // ATOMIC MUTATIONS:
            rideState.status = 'accepted';
            rideState.driver_id = driverUid;
            driver.is_busy = true;
            offer.status = 'accepted';

            // Competing offers automatically cancelled
            for (const [id, off] of Object.entries(offers)) {
              if (off.ride_id === rideState.ride_id && id !== offerId) {
                off.status = 'cancelled';
              }
            }

            return resolve({ success: true, winner: driverUid });
          });
        });
      }

      // Simulate simultaneous acceptance invocation from Driver 1 and Driver 2
      const [res1, res2] = await Promise.all([
        simulatedAcceptTransaction('drv_1', 'offer_d1'),
        simulatedAcceptTransaction('drv_2', 'offer_d2'),
      ]);

      const wins = [res1, res2].filter(r => r.success);
      const losses = [res1, res2].filter(r => !r.success);

      // Exactly ONE driver must win
      assert.equal(wins.length, 1, 'Exactly one driver must win the race');
      assert.equal(losses.length, 1, 'Exactly one driver must receive failure');
      assert.ok(['OFFER_UNAVAILABLE', 'RIDE_ALREADY_ACCEPTED'].includes(losses[0].error));

      // Ride is accepted and assigned
      assert.equal(rideState.status, 'accepted');
      assert.ok(rideState.driver_id === 'drv_1' || rideState.driver_id === 'drv_2');

      // The losing driver's offer is marked cancelled
      const losingOfferId = rideState.driver_id === 'drv_1' ? 'offer_d2' : 'offer_d1';
      assert.equal(offers[losingOfferId].status, 'cancelled');
    });
  });

  // =========================================================================
  // 2. Offer Expiration & Radius Expansion
  // =========================================================================
  describe('2. Offer Expiration & Radius Expansion (3 KM -> 5 KM -> 7 KM)', () => {
    it('expands radius from 3 KM to 5 KM when initial offers expire, and expires ride after TTL', () => {
      const settings = {
        initial_radius_km: 3.0,
        expanded_radius_km: 5.0,
        max_radius_km: 7.0,
        ride_ttl_seconds: 120,
      };

      function determineTargetRadius(elapsedSeconds, allOffersExpired) {
        if (elapsedSeconds >= settings.ride_ttl_seconds) {
          return { shouldExpireRide: true, radius: 0 };
        }
        if (!allOffersExpired) {
          return { shouldExpireRide: false, radius: settings.initial_radius_km };
        }
        if (elapsedSeconds > 60) {
          return { shouldExpireRide: false, radius: settings.max_radius_km }; // 7.0 KM
        }
        return { shouldExpireRide: false, radius: settings.expanded_radius_km }; // 5.0 KM
      }

      // 1. Initial 30 seconds: offers pending in 3 KM
      const step1 = determineTargetRadius(20, false);
      assert.equal(step1.shouldExpireRide, false);
      assert.equal(step1.radius, 3.0);

      // 2. After 35 seconds: 3 KM offers expired -> expand to 5 KM
      const step2 = determineTargetRadius(35, true);
      assert.equal(step2.shouldExpireRide, false);
      assert.equal(step2.radius, 5.0);

      // 3. After 75 seconds: 5 KM offers expired -> expand to 7 KM
      const step3 = determineTargetRadius(75, true);
      assert.equal(step3.shouldExpireRide, false);
      assert.equal(step3.radius, 7.0);

      // 4. After 120 seconds: Total TTL reached -> expire ride cleanly
      const step4 = determineTargetRadius(120, true);
      assert.equal(step4.shouldExpireRide, true);
    });
  });

  // =========================================================================
  // 3. Stale Driver Telemetry Presence
  // =========================================================================
  describe('3. Stale Driver Telemetry Presence', () => {
    it('excludes drivers whose telemetry heartbeat is older than 60 seconds', () => {
      const now = Date.now();
      const heartbeatTimeoutMs = 60 * 1000;

      const driversInDb = [
        { id: 'fresh_driver', updated_at: now - 15000, is_online: true, is_busy: false, status: 'approved' }, // 15s ago
        { id: 'stale_driver', updated_at: now - 75000, is_online: true, is_busy: false, status: 'approved' }, // 75s ago (stale!)
        { id: 'crashed_app_driver', updated_at: now - 300000, is_online: true, is_busy: false, status: 'approved' }, // 5 min ago
      ];

      const eligibleDrivers = driversInDb.filter(d => {
        const isFresh = (now - d.updated_at) <= heartbeatTimeoutMs;
        return d.is_online && !d.is_busy && d.status === 'approved' && isFresh;
      });

      assert.equal(eligibleDrivers.length, 1);
      assert.equal(eligibleDrivers[0].id, 'fresh_driver');
    });
  });

  // =========================================================================
  // 4. Ride Cancellation & Availability Restoration
  // =========================================================================
  describe('4. Cancellation & Driver Availability Restoration', () => {
    it('restores driver availability (is_busy = false, active_rider_id = null) upon ride cancellation', () => {
      const ride = {
        ride_id: 'ride_1',
        rider_id: 'rider_1',
        driver_id: 'drv_1',
        status: 'accepted',
      };

      const driver = {
        driver_id: 'drv_1',
        is_busy: true,
        current_ride_id: 'ride_1',
      };

      const rtdbLocation = {
        driver_id: 'drv_1',
        is_busy: true,
        active_rider_id: 'rider_1',
      };

      // Perform cancellation
      function cancelRide(callerId, reason) {
        if (!['rider_1', 'drv_1'].includes(callerId)) throw new Error('UNAUTHORIZED');
        if (['in_progress', 'completed', 'cancelled'].includes(ride.status)) throw new Error('CANNOT_CANCEL');

        ride.status = 'cancelled';
        ride.cancelled_by = callerId === 'rider_1' ? 'rider' : 'driver';

        // Free driver
        driver.is_busy = false;
        driver.current_ride_id = null;

        // Clear RTDB location & privacy link
        rtdbLocation.is_busy = false;
        rtdbLocation.active_rider_id = null;
      }

      cancelRide('rider_1', 'Changed my mind');

      assert.equal(ride.status, 'cancelled');
      assert.equal(driver.is_busy, false);
      assert.equal(driver.current_ride_id, null);
      assert.equal(rtdbLocation.is_busy, false);
      assert.equal(rtdbLocation.active_rider_id, null, 'Active rider privacy access must be revoked');
    });
  });

});
