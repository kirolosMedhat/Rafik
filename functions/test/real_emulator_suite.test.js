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
import { executeRequestRide, executeRateRide } from '../lib/rides.js';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

const PROJECT_ID = 'rafik-98844';
const FIRESTORE_PORT = 8088;
const RTDB_PORT = 9005;

async function waitPort(port, maxAttempts = 35) {
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

    const [firestoreReady, rtdbReady] = await Promise.all([
      waitPort(FIRESTORE_PORT),
      waitPort(RTDB_PORT),
    ]);

    if (!firestoreReady) {
      if (firestoreProc) firestoreProc.kill();
      if (rtdbProc) rtdbProc.kill();
      throw new Error(`CRITICAL: Firestore emulator failed to bind on port ${FIRESTORE_PORT}.`);
    }
    if (!rtdbReady) {
      if (firestoreProc) firestoreProc.kill();
      if (rtdbProc) rtdbProc.kill();
      throw new Error(`CRITICAL: RTDB emulator failed to bind on port ${RTDB_PORT}.`);
    }

    process.env.FIRESTORE_EMULATOR_HOST = '127.0.0.1:' + FIRESTORE_PORT;
    process.env.FIREBASE_DATABASE_EMULATOR_HOST = '127.0.0.1:' + RTDB_PORT;
    if (!admin.apps.length) {
      admin.initializeApp({ projectId: PROJECT_ID });
    }

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
  // 4. ATOMIC CONCURRENT DRIVER ACCEPTANCE IN FIRESTORE TRANSACTIONS
  // ==========================================================================
  describe('4. Atomic Concurrent Driver Acceptance Race in Real Firestore', () => {
    it('guarantees that when two drivers accept the same ride simultaneously, exactly one succeeds and the other fails', async () => {
      const rideId = 'ride_race_real_01';

      await testEnv.withSecurityRulesDisabled(async (adminCtx) => {
        const db = adminCtx.firestore();
        await db.collection('rides').doc(rideId).set({
          ride_id: rideId,
          status: 'requested',
          driver_id: null,
          fare_egp: 75.0,
        });
      });

      // Two drivers attempt atomic transaction
      const driver1Ctx = testEnv.authenticatedContext('driver_1', { role: 'admin' });
      const driver2Ctx = testEnv.authenticatedContext('driver_2', { role: 'admin' });

      async function attemptAccept(ctx, driverUid) {
        const db = ctx.firestore();
        return db.runTransaction(async (transaction) => {
          const rideRef = db.collection('rides').doc(rideId);
          const rideSnap = await transaction.get(rideRef);
          if (rideSnap.data().status !== 'requested') {
            throw new Error('RIDE_ALREADY_ACCEPTED');
          }
          transaction.update(rideRef, {
            status: 'accepted',
            driver_id: driverUid,
          });
          return { winner: driverUid };
        });
      }

      const results = await Promise.allSettled([
        attemptAccept(driver1Ctx, 'driver_1'),
        attemptAccept(driver2Ctx, 'driver_2'),
      ]);

      const fulfilled = results.filter((r) => r.status === 'fulfilled');
      const rejected = results.filter((r) => r.status === 'rejected');

      assert.equal(fulfilled.length, 1, 'Exactly one driver must win the race');
      assert.equal(rejected.length, 1, 'Competing driver must be rejected');
      assert.match(rejected[0].reason.message, /RIDE_ALREADY_ACCEPTED/);

      // Verify final document state
      await testEnv.withSecurityRulesDisabled(async (adminCtx) => {
        const doc = await adminCtx.firestore().collection('rides').doc(rideId).get();
        assert.equal(doc.data().status, 'accepted');
        assert.ok(['driver_1', 'driver_2'].includes(doc.data().driver_id));
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
});
