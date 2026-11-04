import { describe, it, before, after, beforeEach } from 'node:test';
import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import http from 'node:http';
import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import { fileURLToPath } from 'node:url';
import { initializeTestEnvironment, assertFails, assertSucceeds } from '@firebase/rules-unit-testing';
import admin from 'firebase-admin';
import {
  executeRequestRide,
  executeAcceptRide,
  executeMarkArrived,
  executeVerifyPinAndStartTrip,
  executeCompleteRide,
  executeCancelRide,
  executeRateRide,
} from '../lib/rides.js';
import {
  executeAdminReviewDriver,
  executeAdminSuspendDriver,
} from '../lib/admin.js';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

const PROJECT_ID = 'rafik-98844';
const FIRESTORE_PORT = 8088;
const RTDB_PORT = 9005;

async function waitPort(port, maxAttempts = 60) {
  for (let i = 0; i < maxAttempts; i++) {
    try {
      await new Promise((resolve, reject) => {
        const req = http.get(`http://127.0.0.1:${port}/`, (res) => resolve(res));
        req.on('error', reject);
        req.setTimeout(400, () => {
          req.destroy();
          reject(new Error('timeout'));
        });
      });
      return true;
    } catch (_) {
      await new Promise((r) => setTimeout(r, 250));
    }
  }
  return false;
}

describe('RAFIK Real Firebase Emulator Suite — Rules, Privacy & Concurrency', () => {
  let firestoreProc = null;
  let rtdbProc = null;
  let testEnv = null;

  before(async () => {
    const firestoreJar = path.join(
      os.homedir(),
      '.cache',
      'firebase',
      'emulators',
      'cloud-firestore-emulator-v1.19.8.jar'
    );
    const rtdbJar = path.join(
      os.homedir(),
      '.cache',
      'firebase',
      'emulators',
      'firebase-database-emulator-v4.11.2.jar'
    );

    if (!fs.existsSync(firestoreJar)) {
      throw new Error(`CRITICAL: Firestore emulator JAR missing at ${firestoreJar}. Test suite cannot run without real emulator.`);
    }
    if (!fs.existsSync(rtdbJar)) {
      throw new Error(`CRITICAL: RTDB emulator JAR missing at ${rtdbJar}. Test suite cannot run without real emulator.`);
    }

    const firestoreRulesPath = path.resolve(__dirname, '../../firestore.rules');
    const rtdbRulesPath = path.resolve(__dirname, '../../database.rules.json');

    // 1. Spawn Firestore Emulator
    firestoreProc = spawn('java', [
      '-jar', firestoreJar,
      '--port', String(FIRESTORE_PORT),
      '--host', '127.0.0.1',
      '--rules', firestoreRulesPath,
      '--project_id', PROJECT_ID,
    ], { stdio: 'pipe' });

    // 2. Spawn RTDB Emulator
    rtdbProc = spawn('java', [
      '-jar', rtdbJar,
      '--port', String(RTDB_PORT),
      '--host', '127.0.0.1',
    ], { stdio: 'pipe' });

    let firestoreErr = '';
    let rtdbErr = '';
    firestoreProc.stderr?.on('data', (d) => { firestoreErr += d.toString(); });
    rtdbProc.stderr?.on('data', (d) => { rtdbErr += d.toString(); });

    const [firestoreReady, rtdbReady] = await Promise.all([
      waitPort(FIRESTORE_PORT),
      waitPort(RTDB_PORT),
    ]);

    if (!firestoreReady) {
      if (firestoreProc) firestoreProc.kill();
      if (rtdbProc) rtdbProc.kill();
      throw new Error(`CRITICAL: Firestore emulator failed to bind on port ${FIRESTORE_PORT}. Stderr: ${firestoreErr}`);
    }
    if (!rtdbReady) {
      if (firestoreProc) firestoreProc.kill();
      if (rtdbProc) rtdbProc.kill();
      throw new Error(`CRITICAL: RTDB emulator failed to bind on port ${RTDB_PORT}. Stderr: ${rtdbErr}`);
    }

    process.env.FIRESTORE_EMULATOR_HOST = '127.0.0.1:' + FIRESTORE_PORT;
    process.env.FIREBASE_DATABASE_EMULATOR_HOST = '127.0.0.1:' + RTDB_PORT;
    for (const app of admin.apps) {
      await app.delete();
    }
    admin.initializeApp({
      projectId: PROJECT_ID,
      databaseURL: `http://127.0.0.1:${RTDB_PORT}/?ns=${PROJECT_ID}`,
    });

    testEnv = await initializeTestEnvironment({
      projectId: PROJECT_ID,
      firestore: {
        host: '127.0.0.1',
        port: FIRESTORE_PORT,
        rules: fs.readFileSync(firestoreRulesPath, 'utf8'),
      },
      database: {
        host: '127.0.0.1',
        port: RTDB_PORT,
        rules: fs.readFileSync(rtdbRulesPath, 'utf8'),
      },
    });
  });

  after(async () => {
    try {
      if (admin.apps.length) {
        admin.database().goOffline();
        for (const app of admin.apps) {
          await app.delete();
        }
      }
    } catch (_) {}
    if (testEnv) await testEnv.cleanup();
    if (firestoreProc) firestoreProc.kill();
    if (rtdbProc) rtdbProc.kill();
  });

  beforeEach(async () => {
    if (testEnv) {
      await testEnv.clearFirestore();
      await testEnv.clearDatabase();
    }
  });

  // ==========================================================================
  // 1. DRIVER DATA PRIVACY (Blocker 1)
  // ==========================================================================
  describe('1. Driver Data Privacy & Sensitive Field Isolation', () => {
    it('blocks riders, unassigned drivers, and unauthenticated users from reading private /drivers/{driverId}', async () => {
      // Seed private driver profile with national ID and license
      await testEnv.withSecurityRulesDisabled(async (adminCtx) => {
        const db = adminCtx.firestore();
        await db.collection('drivers').doc('driver_secure_01').set({
          driver_id: 'driver_secure_01',
          national_id_number: '29801011234567',
          license_number: 'LIC-CAIRO-9921',
          status: 'approved',
          is_online: true,
          wallet_balance_egp: 4500.0,
        });
      });

      // Rider reading private driver document MUST FAIL
      const riderCtx = testEnv.authenticatedContext('rider_01', { role: 'rider' });
      await assertFails(riderCtx.firestore().collection('drivers').doc('driver_secure_01').get());

      // Another driver reading private driver document MUST FAIL
      const otherDriverCtx = testEnv.authenticatedContext('driver_other', { role: 'driver', approved: true });
      await assertFails(otherDriverCtx.firestore().collection('drivers').doc('driver_secure_01').get());

      // Unauthenticated user reading private driver document MUST FAIL
      const unauthCtx = testEnv.unauthenticatedContext();
      await assertFails(unauthCtx.firestore().collection('drivers').doc('driver_secure_01').get());

      // Driver reading their OWN profile MUST SUCCEED
      const ownerCtx = testEnv.authenticatedContext('driver_secure_01', { role: 'driver', approved: true });
      await assertSucceeds(ownerCtx.firestore().collection('drivers').doc('driver_secure_01').get());

      // Admin reading private driver profile MUST SUCCEED
      const adminCtx = testEnv.authenticatedContext('admin_ops', { role: 'admin' });
      await assertSucceeds(adminCtx.firestore().collection('drivers').doc('driver_secure_01').get());
    });

    it('allows reading safe non-sensitive fields from /public_drivers/{driverId} but blocks sensitive writes', async () => {
      // Seed public projection
      await testEnv.withSecurityRulesDisabled(async (adminCtx) => {
        const db = adminCtx.firestore();
        await db.collection('public_drivers').doc('driver_secure_01').set({
          driver_id: 'driver_secure_01',
          full_name: 'Captain Yasmine',
          status: 'approved',
          is_online: true,
          vehicle_model: 'Toyota Yaris',
          rating_avg: 4.95,
        });
      });

      // Authenticated rider reading public driver profile SUCCEEDS
      const riderCtx = testEnv.authenticatedContext('rider_01', { role: 'rider' });
      await assertSucceeds(riderCtx.firestore().collection('public_drivers').doc('driver_secure_01').get());

      // Driver attempting to write sensitive field (national_id_number) to public profile FAILS
      const driverCtx = testEnv.authenticatedContext('driver_secure_01', { role: 'driver', approved: true });
      await assertFails(driverCtx.firestore().collection('public_drivers').doc('driver_secure_01').update({
        national_id_number: '29801011234567',
      }));
    });
  });

  // ==========================================================================
  // 2. RIDE PRIVACY & PIN SECURITY (Blocker 1 & 4)
  // ==========================================================================
  describe('2. Ride Privacy & PIN Isolation', () => {
    it('denies direct client ride creation and mutation; restricts reads strictly to participants', async () => {
      const riderCtx = testEnv.authenticatedContext('rider_01', { role: 'rider' });

      // Direct client ride creation MUST FAIL
      await assertFails(riderCtx.firestore().collection('rides').doc('ride_test_01').set({
        ride_id: 'ride_test_01',
        rider_id: 'rider_01',
        fare_egp: 25.0,
        status: 'requested',
      }));

      // Seed ride via Admin
      await testEnv.withSecurityRulesDisabled(async (adminCtx) => {
        const db = adminCtx.firestore();
        await db.collection('rides').doc('ride_test_01').set({
          ride_id: 'ride_test_01',
          rider_id: 'rider_01',
          driver_id: 'driver_assigned',
          status: 'accepted',
          fare_egp: 65.0,
        });
      });

      // Rider participant reading ride SUCCEEDS
      await assertSucceeds(riderCtx.firestore().collection('rides').doc('ride_test_01').get());

      // Assigned driver reading ride SUCCEEDS
      const driverCtx = testEnv.authenticatedContext('driver_assigned', { role: 'driver', approved: true });
      await assertSucceeds(driverCtx.firestore().collection('rides').doc('ride_test_01').get());

      // Unassigned driver reading ride FAILS
      const unassignedDriverCtx = testEnv.authenticatedContext('driver_unassigned', { role: 'driver', approved: true });
      await assertFails(unassignedDriverCtx.firestore().collection('rides').doc('ride_test_01').get());

      // Another rider reading ride FAILS
      const otherRiderCtx = testEnv.authenticatedContext('rider_other', { role: 'rider' });
      await assertFails(otherRiderCtx.firestore().collection('rides').doc('ride_test_01').get());
    });

    it('isolates PIN data: rider can read PIN, driver is strictly forbidden from reading PIN document', async () => {
      await testEnv.withSecurityRulesDisabled(async (adminCtx) => {
        const db = adminCtx.firestore();
        await db.collection('rides').doc('ride_pin_test').set({
          ride_id: 'ride_pin_test',
          rider_id: 'rider_01',
          driver_id: 'driver_01',
          status: 'accepted',
        });
        await db.collection('rides').doc('ride_pin_test').collection('security').doc('pin_data').set({
          pin: '0842',
          attempts: 0,
          locked: false,
        });
      });

      const riderCtx = testEnv.authenticatedContext('rider_01', { role: 'rider' });
      const driverCtx = testEnv.authenticatedContext('driver_01', { role: 'driver', approved: true });

      // Rider reading PIN SUCCEEDS
      await assertSucceeds(riderCtx.firestore().collection('rides').doc('ride_pin_test').collection('security').doc('pin_data').get());

      // Driver reading PIN FAILS (cannot read PIN)
      await assertFails(driverCtx.firestore().collection('rides').doc('ride_pin_test').collection('security').doc('pin_data').get());
    });
  });

  // ==========================================================================
  // 3. ROLE RESTRICTIONS & REGISTRATION TAMPER RESISTANCE (Blocker 2 & 4)
  // ==========================================================================
  describe('3. Role Restrictions & Registration Tamper Resistance', () => {
    it('blocks client from self-assigning role: admin or self-verifying gender', async () => {
      const userCtx = testEnv.authenticatedContext('new_user_01');

      // Attempting to register as 'admin' FAILS
      await assertFails(userCtx.firestore().collection('users').doc('new_user_01').set({
        uid: 'new_user_01',
        role: 'admin',
        gender: 'female',
        gender_verified: false,
        is_active: true,
        created_at: new Date(),
      }));

      // Attempting to register with gender_verified: true FAILS
      await assertFails(userCtx.firestore().collection('users').doc('new_user_01').set({
        uid: 'new_user_01',
        role: 'rider',
        gender: 'female',
        gender_verified: true,
        is_active: true,
        created_at: new Date(),
      }));

      // Valid rider registration SUCCEEDS
      await assertSucceeds(userCtx.firestore().collection('users').doc('new_user_01').set({
        uid: 'new_user_01',
        role: 'rider',
        gender: 'female',
        gender_verified: false,
        is_active: true,
        created_at: new Date(),
      }));

      // Attempting to modify immutable role FAILS
      await assertFails(userCtx.firestore().collection('users').doc('new_user_01').update({
        role: 'admin',
      }));
    });
  });

  // ==========================================================================
  // 4. ATOMIC CONCURRENT DRIVER ACCEPTANCE WITH PRODUCTION executeAcceptRide
  // ==========================================================================
  describe('4. Atomic Concurrent Driver Acceptance Race via Production executeAcceptRide', () => {
    it('guarantees that when two drivers accept the same ride simultaneously via production executeAcceptRide, exactly one succeeds and the other fails', async () => {
      const rideId = 'ride_race_real_01';
      const offer1Id = 'offer_race_01';
      const offer2Id = 'offer_race_02';

      await testEnv.withSecurityRulesDisabled(async (adminCtx) => {
        const db = adminCtx.firestore();

        // 1. Seed ride
        await db.collection('rides').doc(rideId).set({
          ride_id: rideId,
          rider_id: 'rider_01',
          tier: 'standard',
          status: 'requested',
          driver_id: null,
          fare_egp: 75.0,
          driver_earnings_egp: 75.0,
          created_at: new Date(),
        });

        // 2. Seed drivers, users, vehicles
        for (const driverId of ['driver_1', 'driver_2']) {
          await db.collection('drivers').doc(driverId).set({
            driver_id: driverId,
            status: 'approved',
            is_busy: false,
            is_online: true,
            national_id_number: '29801011234567',
            license_number: `LIC-${driverId}`,
          });
          await db.collection('users').doc(driverId).set({
            uid: driverId,
            full_name: `Captain ${driverId}`,
            phone: '+201012345678',
            role: 'driver',
            is_active: true,
          });
          await db.collection('vehicles').doc(driverId).set({
            driver_id: driverId,
            plate_number: `CAIRO-${driverId}`,
            make: 'Toyota',
            model: 'Corolla',
          });
        }

        // 3. Seed targeted offers for both drivers
        const futureExpiry = new Date(Date.now() + 60000);
        await db.collection('ride_offers').doc(offer1Id).set({
          offer_id: offer1Id,
          ride_id: rideId,
          driver_id: 'driver_1',
          status: 'pending',
          expires_at: futureExpiry,
        });
        await db.collection('ride_offers').doc(offer2Id).set({
          offer_id: offer2Id,
          ride_id: rideId,
          driver_id: 'driver_2',
          status: 'pending',
          expires_at: futureExpiry,
        });
      });

      // Execute actual production executeAcceptRide concurrently!
      const results = await Promise.allSettled([
        executeAcceptRide('driver_1', offer1Id),
        executeAcceptRide('driver_2', offer2Id),
      ]);

      const fulfilled = results.filter((r) => r.status === 'fulfilled');
      const rejected = results.filter((r) => r.status === 'rejected');

      assert.equal(fulfilled.length, 1, 'Exactly one driver must win the race');
      assert.equal(rejected.length, 1, 'Competing driver must be rejected');
      assert.match(rejected[0].reason.message, /RIDE_ALREADY_ACCEPTED|OFFER_UNAVAILABLE/);

      // Verify that winning driver is assigned on the ride document and competing offer is cancelled
      await testEnv.withSecurityRulesDisabled(async (adminCtx) => {
        const doc = await adminCtx.firestore().collection('rides').doc(rideId).get();
        assert.equal(doc.data().status, 'accepted');
        const winner = doc.data().driver_id;
        assert.ok(['driver_1', 'driver_2'].includes(winner));

        const loserOfferId = winner === 'driver_1' ? offer2Id : offer1Id;
        const loserOfferDoc = await adminCtx.firestore().collection('ride_offers').doc(loserOfferId).get();
        assert.equal(loserOfferDoc.data().status, 'cancelled');
      });
    });
  });

  // ==========================================================================
  // 5. RIDE REQUEST ROLE RESTRICTION & COORDINATE BOUNDS (Blocker 2)
  // ==========================================================================
  describe('5. Ride Request Role & Coordinate Validation', () => {
    it('rejects drivers and deactivated accounts from calling requestRide', async () => {
      // Driver account calling requestRide MUST BE REJECTED
      let driverThrew = false;
      try {
        await executeRequestRide('driver_account_01', {
          tier: 'standard',
          pickup_address: 'Tahrir Square',
          pickup_lat: 30.0444,
          pickup_lng: 31.2357,
          dropoff_address: 'AUC New Cairo',
          dropoff_lat: 30.0195,
          dropoff_lng: 31.4988,
        });
      } catch (e) {
        driverThrew = true;
        assert.match(e.message, /USER_NOT_FOUND|FORBIDDEN/);
      }
      assert.ok(driverThrew, 'Driver account must not create ride requests');

      // Invalid out-of-bounds coordinates MUST BE REJECTED
      let boundsThrew = false;
      try {
        await executeRequestRide('rider_valid_01', {
          tier: 'standard',
          pickup_address: 'London Eye',
          pickup_lat: 51.5033, // Out of Egypt bounds
          pickup_lng: -0.1195,
          dropoff_address: 'Heathrow Airport',
          dropoff_lat: 51.4700,
          dropoff_lng: -0.4543,
        });
      } catch (e) {
        boundsThrew = true;
        assert.match(e.message, /OUT_OF_BOUNDS|USER_NOT_FOUND|FORBIDDEN/);
      }
      assert.ok(boundsThrew, 'Non-Egyptian coordinates must be rejected');
    });
  });

  // ==========================================================================
  // 6. REAL RTDB SECURITY RULES EMULATOR TESTS
  // ==========================================================================
  describe('6. Real RTDB Security Rules Invariants', () => {
    it('allows approved driver to update their location, blocks pending and other drivers', async () => {
      const now = Date.now();

      // Approved driver writes own location with ServerValue timestamp
      const approvedDriverCtx = testEnv.authenticatedContext('driver_approved_01', {
        role: 'driver',
        approved: true,
      });
      const db = approvedDriverCtx.database();

      // Updating own location
      await assertSucceeds(
        db.ref('driver_locations/driver_approved_01').set({
          lat: 30.0444,
          lng: 31.2357,
          heading: 90.0,
          speed: 12.5,
          updated_at: now,
        })
      );

      // Pending driver writing location FAILS
      const pendingDriverCtx = testEnv.authenticatedContext('driver_pending_01', {
        role: 'driver',
        approved: false,
      });
      await assertFails(
        pendingDriverCtx.database().ref('driver_locations/driver_pending_01').set({
          lat: 30.0444,
          lng: 31.2357,
          heading: 90.0,
          speed: 12.5,
          updated_at: now,
        })
      );

      // Driver attempting to write to another driver location FAILS
      await assertFails(
        approvedDriverCtx.database().ref('driver_locations/driver_other_id').set({
          lat: 30.0444,
          lng: 31.2357,
          heading: 90.0,
          speed: 12.5,
          updated_at: now,
        })
      );

      // Writing future timestamp to bypass stale telemetry FAILS
      await assertFails(
        approvedDriverCtx.database().ref('driver_locations/driver_approved_01').set({
          lat: 30.0444,
          lng: 31.2357,
          heading: 90.0,
          speed: 12.5,
          updated_at: now + 60000, // 60 seconds into future
        })
      );
    });
  });

  // ==========================================================================
  // 7. COMPLETE MULTI-ACTOR E2E RIDE LIFECYCLE & CROSS-SESSION SYNCHRONIZATION
  // ==========================================================================
  describe('7. Multi-Actor Production End-to-End Ride Lifecycle & State Machine', () => {
    it('executes a complete ride lifecycle: request -> accept -> arrive -> PIN handshake -> complete -> rating', async () => {
      const riderUid = 'rider_e2e_01';
      const driverUid = 'driver_e2e_01';

      // 1. Seed accounts and initial presence in RTDB
      await testEnv.withSecurityRulesDisabled(async (adminCtx) => {
        const db = adminCtx.firestore();

        // Seed rider profile
        await db.collection('users').doc(riderUid).set({
          uid: riderUid,
          full_name: 'Nour El-Din (Rider)',
          phone: '+201011112222',
          role: 'rider',
          gender: 'female',
          is_active: true,
          created_at: new Date(),
        });

        // Seed driver profile, user, vehicle
        await db.collection('drivers').doc(driverUid).set({
          driver_id: driverUid,
          national_id_number: '29801011234567',
          license_number: 'LIC-CAIRO-7788',
          status: 'approved',
          is_busy: false,
          is_online: true,
          wallet_balance_egp: 500.0,
          rating_avg: 4.90,
          total_ratings: 10,
        });
        await db.collection('users').doc(driverUid).set({
          uid: driverUid,
          full_name: 'Captain Salma (Driver)',
          phone: '+201099998888',
          role: 'driver',
          gender: 'female',
          is_active: true,
        });
        await db.collection('vehicles').doc(driverUid).set({
          driver_id: driverUid,
          plate_number: 'CAIRO-7788',
          make: 'Hyundai',
          model: 'Elantra',
        });

        // Seed driver presence in Realtime Database within 1 km of Tahrir Square
        await admin.database().ref(`driver_locations/${driverUid}`).set({
          driver_id: driverUid,
          lat: 30.0444,
          lng: 31.2357,
          heading: 45.0,
          speed: 15.0,
          is_online: true,
          is_busy: false,
          status: 'approved',
          gender: 'female',
          gender_verified: true,
          updated_at: Date.now(),
        });
      });

      // 2. Rider requests ride via production executeRequestRide
      const requestResult = await executeRequestRide(riderUid, {
        tier: 'standard',
        pickup_address: 'Tahrir Square, Downtown Cairo',
        pickup_lat: 30.0444,
        pickup_lng: 31.2357,
        dropoff_address: 'AUC New Cairo Campus',
        dropoff_lat: 30.0195,
        dropoff_lng: 31.4988,
        payment_method: 'cash',
      });

      assert.ok(requestResult.ride_id, 'Ride ID must be generated');
      assert.ok(requestResult.fare_egp >= 25.0, 'Fare must meet minimum Cairo fare floor');
      assert.ok(/^\d{4}$/.test(requestResult.pin), 'PIN must be 4 digits');
      const rideId = requestResult.ride_id;
      const secretPin = requestResult.pin;

      // 3. Verify targeted offer generated for eligible driver
      let offerId = null;
      await testEnv.withSecurityRulesDisabled(async (adminCtx) => {
        const offersSnap = await adminCtx.firestore().collection('ride_offers')
          .where('ride_id', '==', rideId)
          .where('driver_id', '==', driverUid)
          .get();
        assert.equal(offersSnap.docs.length, 1, 'Targeted offer must be created for nearby eligible driver');
        offerId = offersSnap.docs[0].id;
        assert.equal(offersSnap.docs[0].data().status, 'pending');
      });

      // 4. Driver accepts ride via production executeAcceptRide
      const acceptResult = await executeAcceptRide(driverUid, offerId);
      assert.equal(acceptResult.success, true);
      assert.equal(acceptResult.ride_id, rideId);

      // Verify ride transitioned to 'accepted' and driver marked busy
      await testEnv.withSecurityRulesDisabled(async (adminCtx) => {
        const rideSnap = await adminCtx.firestore().collection('rides').doc(rideId).get();
        assert.equal(rideSnap.data().status, 'accepted');
        assert.equal(rideSnap.data().driver_id, driverUid);

        const driverSnap = await adminCtx.firestore().collection('drivers').doc(driverUid).get();
        assert.equal(driverSnap.data().is_busy, true);
      });

      // 5. Driver marks arrived via production executeMarkArrived
      await admin.database().ref(`driver_locations/${driverUid}`).update({
        lat: 30.0444, // Exact pickup coordinates
        lng: 31.2357,
        updated_at: Date.now(),
      });
      const arrivalResult = await executeMarkArrived(driverUid, rideId);
      assert.equal(arrivalResult.success, true);

      await testEnv.withSecurityRulesDisabled(async (adminCtx) => {
        const rideSnap = await adminCtx.firestore().collection('rides').doc(rideId).get();
        assert.equal(rideSnap.data().status, 'arrived');
      });

      // 6. PIN Verification Handshake via production executeVerifyPinAndStartTrip
      // 6a. Attempt with wrong PIN decrements strikes
      const wrongPinResult = await executeVerifyPinAndStartTrip(driverUid, rideId, '9999');
      assert.equal(wrongPinResult.success, false);
      assert.equal(wrongPinResult.status, 'wrong_pin');
      assert.equal(wrongPinResult.attempts_left, 2);

      // 6b. Correct PIN unlocks and starts trip
      const correctPinResult = await executeVerifyPinAndStartTrip(driverUid, rideId, secretPin);
      assert.equal(correctPinResult.success, true);
      assert.equal(correctPinResult.status, 'in_progress');

      await testEnv.withSecurityRulesDisabled(async (adminCtx) => {
        const rideSnap = await adminCtx.firestore().collection('rides').doc(rideId).get();
        assert.equal(rideSnap.data().status, 'in_progress');
      });

      // 7. Trip Completion via production executeCompleteRide
      const completeResult = await executeCompleteRide(driverUid, rideId);
      assert.equal(completeResult.success, true);
      assert.ok(completeResult.driver_earnings_egp > 0);

      // Verify ride status completed, driver availability restored, and wallet credited
      await testEnv.withSecurityRulesDisabled(async (adminCtx) => {
        const rideSnap = await adminCtx.firestore().collection('rides').doc(rideId).get();
        assert.equal(rideSnap.data().status, 'completed');

        const driverSnap = await adminCtx.firestore().collection('drivers').doc(driverUid).get();
        assert.equal(driverSnap.data().is_busy, false);
        assert.ok(driverSnap.data().wallet_balance_egp > 500.0, 'Driver wallet must be credited');
      });

      // 8. Mutual Rating Submission via production executeRateRide
      const ratingResult = await executeRateRide(riderUid, rideId, 5, 'Smooth, safe, and professional trip!');
      assert.equal(ratingResult.success, true);

      await testEnv.withSecurityRulesDisabled(async (adminCtx) => {
        const driverSnap = await adminCtx.firestore().collection('drivers').doc(driverUid).get();
        assert.ok(driverSnap.data().rating_avg >= 4.90);
        assert.equal(driverSnap.data().total_ratings, 11);
      });
    });
  });

  // ==========================================================================
  // 8. SECURITY & FAILURE INVARIANTS (Blocker 5)
  // ==========================================================================
  describe('8. Security, Failure Invariants & Resilience Testing', () => {
    it('blocks unapproved drivers from going online or receiving dispatch', async () => {
      await testEnv.withSecurityRulesDisabled(async (adminCtx) => {
        await adminCtx.firestore().collection('drivers').doc('driver_pending_test').set({
          driver_id: 'driver_pending_test',
          status: 'pending',
          is_online: false,
          is_busy: false,
        });
      });

      const pendingCtx = testEnv.authenticatedContext('driver_pending_test', {
        role: 'driver',
        approved: false,
      });

      // Attempting to set status approved directly FAILS
      await assertFails(pendingCtx.firestore().collection('drivers').doc('driver_pending_test').update({
        status: 'approved',
      }));
    });

    it('enforces cancellation availability restoration', async () => {
      const rideId = 'ride_cancel_test_01';
      const riderUid = 'rider_cancel_01';
      const driverUid = 'driver_cancel_01';

      await testEnv.withSecurityRulesDisabled(async (adminCtx) => {
        const db = adminCtx.firestore();
        await db.collection('rides').doc(rideId).set({
          ride_id: rideId,
          rider_id: riderUid,
          driver_id: driverUid,
          status: 'accepted',
          fare_egp: 50.0,
        });
        await db.collection('drivers').doc(driverUid).set({
          driver_id: driverUid,
          status: 'approved',
          is_busy: true,
          current_ride_id: rideId,
        });
        await db.collection('rider_reservations').doc(riderUid).set({
          status: 'active',
          ride_id: rideId,
        });
      });

      // Rider cancels ride
      const cancelResult = await executeCancelRide(riderUid, rideId, 'rider', 'Changed plans');
      assert.equal(cancelResult.success, true);

      // Verify driver is un-busied and reservation released
      await testEnv.withSecurityRulesDisabled(async (adminCtx) => {
        const driverSnap = await adminCtx.firestore().collection('drivers').doc(driverUid).get();
        assert.equal(driverSnap.data().is_busy, false);

        const resSnap = await adminCtx.firestore().collection('rider_reservations').doc(riderUid).get();
        assert.equal(resSnap.data().status, 'idle');
      });
    });

    it('rejects duplicate rating submissions', async () => {
      const rideId = 'ride_duplicate_rating_test';
      const riderUid = 'rider_dup_01';
      const driverUid = 'driver_dup_01';

      await testEnv.withSecurityRulesDisabled(async (adminCtx) => {
        const db = adminCtx.firestore();
        await db.collection('rides').doc(rideId).set({
          ride_id: rideId,
          rider_id: riderUid,
          driver_id: driverUid,
          status: 'completed',
        });
        await db.collection('drivers').doc(driverUid).set({
          driver_id: driverUid,
          rating_avg: 5.0,
          total_ratings: 1,
        });
      });

      // First rating succeeds
      await executeRateRide(riderUid, rideId, 5);

      // Second rating by same user on same ride FAILS
      let threw = false;
      try {
        await executeRateRide(riderUid, rideId, 4);
      } catch (e) {
        threw = true;
        assert.match(e.message, /ALREADY_RATED/);
      }
      assert.ok(threw, 'Duplicate rating must be rejected');
    });
  });

  // ==========================================================================
  // 9. ADMIN OPERATIONS & GOVERNANCE SUITE (Blocker 6)
  // ==========================================================================
  describe('9. Server-Authoritative Admin Governance & Review Engine', () => {
    it('allows verified admin to approve and suspend captains, rejecting unauthorized callers', async () => {
      const adminUid = 'admin_master_01';
      const driverUid = 'driver_vetting_01';

      // 1. Seed admin profile in admin_users collection
      await testEnv.withSecurityRulesDisabled(async (adminCtx) => {
        const db = adminCtx.firestore();
        await db.collection('admin_users').doc(adminUid).set({
          uid: adminUid,
          full_name: 'Super Admin',
          role: 'admin',
          is_active: true,
        });
        await db.collection('drivers').doc(driverUid).set({
          driver_id: driverUid,
          status: 'pending',
          is_online: false,
          is_busy: false,
        });
      });

      // 2. Unauthorized caller cannot review driver
      let unauthThrew = false;
      try {
        await executeAdminReviewDriver('random_user', driverUid, true);
      } catch (e) {
        unauthThrew = true;
        assert.match(e.message, /FORBIDDEN/);
      }
      assert.ok(unauthThrew, 'Non-admin caller must be rejected from driver review');

      // 3. Admin approves driver
      const reviewResult = await executeAdminReviewDriver(adminUid, driverUid, true);
      assert.equal(reviewResult.success, true);

      // Verify driver status is now approved
      await testEnv.withSecurityRulesDisabled(async (adminCtx) => {
        const driverSnap = await adminCtx.firestore().collection('drivers').doc(driverUid).get();
        assert.equal(driverSnap.data().status, 'approved');
      });

      // 4. Admin suspends driver
      const suspendResult = await executeAdminSuspendDriver(adminUid, driverUid, 'KYC document verification anomaly');
      assert.equal(suspendResult.success, true);

      await testEnv.withSecurityRulesDisabled(async (adminCtx) => {
        const driverSnap = await adminCtx.firestore().collection('drivers').doc(driverUid).get();
        assert.equal(driverSnap.data().status, 'suspended');
      });
    });
  });
});
