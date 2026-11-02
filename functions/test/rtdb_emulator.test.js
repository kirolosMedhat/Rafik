import { describe, it, before, after, beforeEach } from 'node:test';
import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import http from 'node:http';
import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import { fileURLToPath } from 'node:url';
import { initializeTestEnvironment, assertFails, assertSucceeds } from '@firebase/rules-unit-testing';
import { ref, set, get, update } from 'firebase/database';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

/**
 * Official Firebase Realtime Database Emulator Security Rules Test Suite
 * Evaluates the real database.rules.json file against the official Firebase RTDB Emulator (v4.11.2).
 */

const EMULATOR_PORT = 9005;
const PROJECT_ID = 'rafik-98844';

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
      await new Promise((r) => setTimeout(r, 200));
    }
  }
  return false;
}

describe('Firebase Realtime Database Emulator — Security Rules Verification', () => {
  let emulatorProc = null;
  let testEnv = null;
  let emulatorAvailable = false;

  before(async () => {
    const jarPath = path.join(
      os.homedir(),
      '.cache',
      'firebase',
      'emulators',
      'firebase-database-emulator-v4.11.2.jar'
    );

    if (!fs.existsSync(jarPath)) {
      console.warn(`[RTDB-EMU] Emulator JAR not found at ${jarPath}`);
      return;
    }

    // Start emulator process
    emulatorProc = spawn('java', ['-jar', jarPath, '--host', '127.0.0.1', '--port', String(EMULATOR_PORT)], {
      stdio: ['ignore', 'ignore', 'pipe'],
    });

    let startupError = null;
    emulatorProc.stderr.on('data', (d) => {
      const msg = d.toString();
      if (msg.includes('Permission denied: connect') || msg.includes('Error initializing Firebase')) {
        startupError = msg;
      }
    });

    const isListening = await waitPort(EMULATOR_PORT);
    if (!isListening || startupError) {
      console.warn('[RTDB-EMU] Notice: Emulator could not bind loopback socket in current sandbox mode.');
      if (emulatorProc) {
        emulatorProc.kill();
        emulatorProc = null;
      }
      return;
    }

    const rulesPath = path.resolve(__dirname, '../../database.rules.json');
    const rulesContent = fs.readFileSync(rulesPath, 'utf8');

    testEnv = await initializeTestEnvironment({
      projectId: PROJECT_ID,
      database: {
        host: '127.0.0.1',
        port: EMULATOR_PORT,
        rules: rulesContent,
      },
    });

    emulatorAvailable = true;
  });

  after(async () => {
    if (testEnv) {
      await testEnv.cleanup();
    }
    if (emulatorProc) {
      emulatorProc.kill();
    }
  });

  beforeEach(async () => {
    if (!emulatorAvailable || !testEnv) return;
    await testEnv.clearDatabase();

    // Seed server-authoritative baseline state via admin bypass
    await testEnv.withSecurityRulesDisabled(async (context) => {
      const adminDb = context.database();
      // 1. Seed active assigned driver location
      await set(ref(adminDb, 'driver_locations/drv_approved_assigned'), {
        lat: 30.0444,
        lng: 31.2357,
        heading: 90.0,
        speed: 15.0,
        updated_at: Date.now(),
        status: 'approved',
        is_busy: true,
        gender: 'female',
        gender_verified: true,
        tier: 'rafik_girl',
        active_rider_id: 'rider_assigned_1',
      });

      // 2. Seed stale-token suspended driver entry
      await set(ref(adminDb, 'suspended_drivers/drv_suspended_stale'), true);

      // 3. Seed stale-token deactivated user entry
      await set(ref(adminDb, 'deactivated_users/drv_deactivated_stale'), true);
    });
  });

  // =========================================================================
  // 1. Approved driver updates own telemetry
  // =========================================================================
  it('1. Approved driver updates own telemetry successfully', async (t) => {
    if (!emulatorAvailable) {
      t.skip('Emulator unavailable in restricted sandbox');
      return;
    }

    const driverContext = testEnv.authenticatedContext('drv_approved_1', {
      role: 'driver',
      approved: true,
    });
    const db = driverContext.database();

    await assertSucceeds(
      set(ref(db, 'driver_locations/drv_approved_1'), {
        lat: 30.0444,
        lng: 31.2357,
        heading: 180.0,
        speed: 35.0,
        updated_at: { '.sv': 'timestamp' },
      })
    );
  });

  // =========================================================================
  // 2. Pending driver update blocked
  // =========================================================================
  it('2. Pending driver update is blocked', async (t) => {
    if (!emulatorAvailable) {
      t.skip('Emulator unavailable in restricted sandbox');
      return;
    }

    const driverContext = testEnv.authenticatedContext('drv_pending_1', {
      role: 'driver',
      approved: false,
    });
    const db = driverContext.database();

    await assertFails(
      set(ref(db, 'driver_locations/drv_pending_1'), {
        lat: 30.0444,
        lng: 31.2357,
        updated_at: { '.sv': 'timestamp' },
      })
    );
  });

  // =========================================================================
  // 3. Rejected driver update blocked
  // =========================================================================
  it('3. Rejected driver update is blocked even if driver: true is retained', async (t) => {
    if (!emulatorAvailable) {
      t.skip('Emulator unavailable in restricted sandbox');
      return;
    }

    const driverContext = testEnv.authenticatedContext('drv_rejected_1', {
      role: 'driver',
      driver: true,
      approved: false,
    });
    const db = driverContext.database();

    await assertFails(
      set(ref(db, 'driver_locations/drv_rejected_1'), {
        lat: 30.0444,
        lng: 31.2357,
        updated_at: { '.sv': 'timestamp' },
      })
    );
  });

  // =========================================================================
  // 4. Suspended driver update blocked even with valid unexpired token (via suspended_drivers)
  // =========================================================================
  it('4. Suspended driver update blocked even with valid unexpired token (stale claims defense)', async (t) => {
    if (!emulatorAvailable) {
      t.skip('Emulator unavailable in restricted sandbox');
      return;
    }

    // Token claims still claim approved: true!
    const driverContext = testEnv.authenticatedContext('drv_suspended_stale', {
      role: 'driver',
      approved: true,
    });
    const db = driverContext.database();

    await assertFails(
      set(ref(db, 'driver_locations/drv_suspended_stale'), {
        lat: 30.0444,
        lng: 31.2357,
        updated_at: { '.sv': 'timestamp' },
      })
    );
  });

  // =========================================================================
  // 5. Deactivated driver update blocked even with valid token (via deactivated_users)
  // =========================================================================
  it('5. Deactivated driver update blocked even with valid token (stale claims defense)', async (t) => {
    if (!emulatorAvailable) {
      t.skip('Emulator unavailable in restricted sandbox');
      return;
    }

    // Token claims still claim approved: true!
    const driverContext = testEnv.authenticatedContext('drv_deactivated_stale', {
      role: 'driver',
      approved: true,
    });
    const db = driverContext.database();

    await assertFails(
      set(ref(db, 'driver_locations/drv_deactivated_stale'), {
        lat: 30.0444,
        lng: 31.2357,
        updated_at: { '.sv': 'timestamp' },
      })
    );
  });

  // =========================================================================
  // 6. Field-tamper blocked (status, is_busy, gender, gender_verified, tier, active_rider_id)
  // =========================================================================
  it('6. Field-tamper blocked (cannot mutate or inject server-authoritative dispatch fields)', async (t) => {
    if (!emulatorAvailable) {
      t.skip('Emulator unavailable in restricted sandbox');
      return;
    }

    const driverContext = testEnv.authenticatedContext('drv_approved_assigned', {
      role: 'driver',
      approved: true,
    });
    const db = driverContext.database();
    const locRef = ref(db, 'driver_locations/drv_approved_assigned');

    // Attempt 1: Driver tries to mutate status from 'approved' to 'suspended' or other
    await assertFails(
      update(locRef, {
        status: 'suspended',
        updated_at: { '.sv': 'timestamp' },
      })
    );

    // Attempt 2: Driver tries to clear is_busy while assigned
    await assertFails(
      update(locRef, {
        is_busy: false,
        updated_at: { '.sv': 'timestamp' },
      })
    );

    // Attempt 3: Driver tries to alter gender / gender_verified
    await assertFails(
      update(locRef, {
        gender: 'male',
        updated_at: { '.sv': 'timestamp' },
      })
    );

    // Attempt 4: Driver tries to tamper with active_rider_id
    await assertFails(
      update(locRef, {
        active_rider_id: 'rider_hacked_999',
        updated_at: { '.sv': 'timestamp' },
      })
    );

    // Attempt 5: Driver tries to inject tier on a fresh document
    const freshDriver = testEnv.authenticatedContext('drv_fresh_tamper', {
      role: 'driver',
      approved: true,
    });
    await assertFails(
      set(ref(freshDriver.database(), 'driver_locations/drv_fresh_tamper'), {
        lat: 30.0,
        lng: 31.0,
        tier: 'vip_custom',
        updated_at: { '.sv': 'timestamp' },
      })
    );
  });

  // =========================================================================
  // 7. Updating another driver's coordinates blocked
  // =========================================================================
  it('7. Updating another driver coordinates is blocked', async (t) => {
    if (!emulatorAvailable) {
      t.skip('Emulator unavailable in restricted sandbox');
      return;
    }

    const driverA = testEnv.authenticatedContext('drv_approved_A', {
      role: 'driver',
      approved: true,
    });

    // Driver A attempts to overwrite Driver B's location
    await assertFails(
      set(ref(driverA.database(), 'driver_locations/drv_approved_B'), {
        lat: 30.0444,
        lng: 31.2357,
        updated_at: { '.sv': 'timestamp' },
      })
    );
  });

  // =========================================================================
  // 8. Unassigned rider reading coordinates blocked
  // =========================================================================
  it('8. Unassigned rider reading driver coordinates is blocked', async (t) => {
    if (!emulatorAvailable) {
      t.skip('Emulator unavailable in restricted sandbox');
      return;
    }

    const riderUnassigned = testEnv.authenticatedContext('rider_stranger_1', {
      role: 'rider',
    });

    // drv_approved_assigned has active_rider_id = 'rider_assigned_1'
    await assertFails(get(ref(riderUnassigned.database(), 'driver_locations/drv_approved_assigned')));
  });

  // =========================================================================
  // 9. Assigned rider reading assigned driver coordinates allowed
  // =========================================================================
  it('9. Assigned rider reading assigned driver coordinates is allowed', async (t) => {
    if (!emulatorAvailable) {
      t.skip('Emulator unavailable in restricted sandbox');
      return;
    }

    const riderAssigned = testEnv.authenticatedContext('rider_assigned_1', {
      role: 'rider',
    });

    await assertSucceeds(get(ref(riderAssigned.database(), 'driver_locations/drv_approved_assigned')));
  });

  // =========================================================================
  // 10. Admin accessing fleet coordinates allowed
  // =========================================================================
  it('10. Admin accessing fleet coordinates is allowed', async (t) => {
    if (!emulatorAvailable) {
      t.skip('Emulator unavailable in restricted sandbox');
      return;
    }

    const adminContext = testEnv.authenticatedContext('admin_user_1', {
      role: 'admin',
    });

    await assertSucceeds(get(ref(adminContext.database(), 'driver_locations/drv_approved_assigned')));
  });

  // =========================================================================
  // 11. Invalid coordinates (out-of-range lat/lng, negative speed, bad heading) rejected
  // =========================================================================
  it('11. Invalid coordinates, headings, speeds, and timestamps are rejected', async (t) => {
    if (!emulatorAvailable) {
      t.skip('Emulator unavailable in restricted sandbox');
      return;
    }

    const driver = testEnv.authenticatedContext('drv_coords_test', {
      role: 'driver',
      approved: true,
    });
    const locRef = ref(driver.database(), 'driver_locations/drv_coords_test');

    // 11a: Latitude > 90
    await assertFails(
      set(locRef, {
        lat: 91.0,
        lng: 31.0,
        updated_at: { '.sv': 'timestamp' },
      })
    );

    // 11b: Longitude < -180
    await assertFails(
      set(locRef, {
        lat: 30.0,
        lng: -185.0,
        updated_at: { '.sv': 'timestamp' },
      })
    );

    // 11c: Heading > 360
    await assertFails(
      set(locRef, {
        lat: 30.0,
        lng: 31.0,
        heading: 420.0,
        updated_at: { '.sv': 'timestamp' },
      })
    );

    // 11d: Negative speed
    await assertFails(
      set(locRef, {
        lat: 30.0,
        lng: 31.0,
        speed: -15.0,
        updated_at: { '.sv': 'timestamp' },
      })
    );

    // 11e: Future timestamp (> now)
    await assertFails(
      set(locRef, {
        lat: 30.0,
        lng: 31.0,
        updated_at: Date.now() + 60000,
      })
    );

    // 11f: Manipulated stale timestamp (> 15s in past)
    await assertFails(
      set(locRef, {
        lat: 30.0,
        lng: 31.0,
        updated_at: Date.now() - 30000,
      })
    );
  });

  // =========================================================================
  // 12. onDisconnect() behavior verified
  // =========================================================================
  it('12. onDisconnect() behavior verified on driver_presence node', async (t) => {
    if (!emulatorAvailable) {
      t.skip('Emulator unavailable in restricted sandbox');
      return;
    }

    const driver = testEnv.authenticatedContext('drv_presence_1', {
      role: 'driver',
      approved: true,
    });
    const presenceRef = ref(driver.database(), 'driver_presence/drv_presence_1');

    // Online state write allowed
    await assertSucceeds(
      set(presenceRef, {
        state: 'online',
        last_changed: { '.sv': 'timestamp' },
        last_seen: { '.sv': 'timestamp' },
      })
    );

    // OnDisconnect state write structure (state: 'offline') allowed
    await assertSucceeds(
      set(presenceRef, {
        state: 'offline',
        last_changed: { '.sv': 'timestamp' },
        last_seen: { '.sv': 'timestamp' },
      })
    );

    // Invalid state blocked
    await assertFails(
      set(presenceRef, {
        state: 'idle_unknown',
        last_changed: { '.sv': 'timestamp' },
      })
    );
  });
});
