import { describe, it } from 'node:test';
import assert from 'node:assert/strict';

/**
 * Rafik Phase 2C - Real-Time Telemetry & Driver Presence Test Suite
 * Validates RTDB telemetry serialization, coordinate bounds, presence lifecycle,
 * server-authoritative field isolation, stale unexpired token defenses, and dispatch filtering.
 */

describe('Rafik Phase 2C - Real-Time Telemetry & Presence Engine', () => {

  // =========================================================================
  // 1. Telemetry Coordinate Validation & Bounds
  // =========================================================================
  describe('1. Telemetry Serialization & Coordinate Bounds', () => {

    function validateTelemetryPayload(payload) {
      if (!payload || typeof payload !== 'object') return false;
      const { lat, lng, updated_at, heading, speed } = payload;

      // Required fields
      if (typeof lat !== 'number' || lat < -90.0 || lat > 90.0) return false;
      if (typeof lng !== 'number' || lng < -180.0 || lng > 180.0) return false;
      if (typeof updated_at !== 'number' || updated_at <= 0) return false;

      // Optional telemetry fields
      if (heading !== undefined && (typeof heading !== 'number' || heading < 0.0 || heading > 360.0)) return false;
      if (speed !== undefined && (typeof speed !== 'number' || speed < 0.0)) return false;

      return true;
    }

    it('accepts valid Cairo coordinate telemetry within bounds', () => {
      const cairoTahrir = {
        lat: 30.0444,
        lng: 31.2357,
        heading: 180.0,
        speed: 35.5,
        updated_at: Date.now(),
      };
      assert.ok(validateTelemetryPayload(cairoTahrir));
    });

    it('rejects coordinates exceeding Earth geographic bounds', () => {
      // Latitude > 90
      assert.equal(validateTelemetryPayload({ lat: 95.0, lng: 31.2, updated_at: Date.now() }), false);
      // Latitude < -90
      assert.equal(validateTelemetryPayload({ lat: -92.5, lng: 31.2, updated_at: Date.now() }), false);
      // Longitude > 180
      assert.equal(validateTelemetryPayload({ lat: 30.0, lng: 185.0, updated_at: Date.now() }), false);
      // Longitude < -180
      assert.equal(validateTelemetryPayload({ lat: 30.0, lng: -185.0, updated_at: Date.now() }), false);
    });

    it('rejects invalid heading angles and negative speed values', () => {
      // Heading > 360
      assert.equal(validateTelemetryPayload({ lat: 30.0, lng: 31.0, heading: 400.0, updated_at: Date.now() }), false);
      // Negative heading
      assert.equal(validateTelemetryPayload({ lat: 30.0, lng: 31.0, heading: -15.0, updated_at: Date.now() }), false);
      // Negative speed
      assert.equal(validateTelemetryPayload({ lat: 30.0, lng: 31.0, speed: -10.0, updated_at: Date.now() }), false);
    });

    it('rejects non-numeric coordinate types or missing timestamps', () => {
      assert.equal(validateTelemetryPayload({ lat: '30.04', lng: 31.23, updated_at: Date.now() }), false);
      assert.equal(validateTelemetryPayload({ lat: 30.04, lng: 31.23 }), false);
    });

    it('rejects future timestamps and manipulated timestamps in security rule validator', () => {
      const now = Date.now();
      function validateTimestampRule(val) {
        // Enforces: isNumber() && val <= now && val >= (now - 15000)
        return typeof val === 'number' && val <= now && val >= (now - 15000);
      }

      // Valid current timestamp (within 15s window)
      assert.ok(validateTimestampRule(now));
      assert.ok(validateTimestampRule(now - 5000));

      // Forged future timestamp (e.g. 1 minute or 1 day ahead) -> REJECTED
      assert.equal(validateTimestampRule(now + 60000), false, 'Future timestamp must be rejected');
      assert.equal(validateTimestampRule(now + 1000), false, 'Clock-skewed future timestamp must be rejected');

      // Stale manipulated timestamp (> 15 seconds in the past) -> REJECTED
      assert.equal(validateTimestampRule(now - 30000), false, 'Old manipulated timestamp must be rejected');
      assert.equal(validateTimestampRule(1000), false, 'Arbitrary historical timestamp must be rejected');
    });
  });

  // =========================================================================
  // 2. Server-Authoritative Field Isolation
  // =========================================================================
  describe('2. Server-Authoritative Field Isolation', () => {

    function evaluateFieldTampering(existingData, newData) {
      const serverControlledFields = ['status', 'gender', 'gender_verified', 'is_busy', 'active_rider_id', 'tier'];

      for (const field of serverControlledFields) {
        const existed = existingData && existingData[field] !== undefined;
        const inNew = newData && newData[field] !== undefined;

        // Rule 1: If field did not exist, client cannot introduce it
        if (!existed && inNew) return { allowed: false, reason: `INJECTED_${field.toUpperCase()}` };

        // Rule 2: If field existed, client cannot alter its value
        if (existed && inNew && newData[field] !== existingData[field]) {
          return { allowed: false, reason: `MUTATED_${field.toUpperCase()}` };
        }
      }

      return { allowed: true };
    }

    it('blocks client driver from elevating their own approval status', () => {
      const existing = { status: 'pending' };
      const malicious = { lat: 30.0, lng: 31.0, updated_at: Date.now(), status: 'approved' };
      const check = evaluateFieldTampering(existing, malicious);
      assert.equal(check.allowed, false);
      assert.equal(check.reason, 'MUTATED_STATUS');
    });

    it('blocks client driver from injecting an active_rider_id to snoop on passengers', () => {
      const existing = {};
      const malicious = { lat: 30.0, lng: 31.0, updated_at: Date.now(), active_rider_id: 'victim_rider_1' };
      const check = evaluateFieldTampering(existing, malicious);
      assert.equal(check.allowed, false);
      assert.equal(check.reason, 'INJECTED_ACTIVE_RIDER_ID');
    });

    it('blocks client driver from altering is_busy while assigned to a ride', () => {
      const existing = { is_busy: true };
      const malicious = { lat: 30.0, lng: 31.0, updated_at: Date.now(), is_busy: false };
      const check = evaluateFieldTampering(existing, malicious);
      assert.equal(check.allowed, false);
      assert.equal(check.reason, 'MUTATED_IS_BUSY');
    });

    it('blocks male driver from spoofing gender or gender_verified for Rafik Girl', () => {
      const existing = { gender: 'male', gender_verified: false };
      const malicious = { lat: 30.0, lng: 31.0, updated_at: Date.now(), gender: 'female', gender_verified: true };
      const check = evaluateFieldTampering(existing, malicious);
      assert.equal(check.allowed, false);
    });

    it('allows client driver to update GPS coordinates while preserving server state', () => {
      const existing = {
        status: 'approved',
        gender: 'female',
        gender_verified: true,
        is_busy: false,
        active_rider_id: 'rider_salma',
      };
      const legitimate = {
        lat: 30.0512,
        lng: 31.2401,
        heading: 90.0,
        speed: 28.0,
        updated_at: Date.now(),
        status: 'approved',
        gender: 'female',
        gender_verified: true,
        is_busy: false,
        active_rider_id: 'rider_salma',
      };
      const check = evaluateFieldTampering(existing, legitimate);
      assert.equal(check.allowed, true);
    });
  });

  // =========================================================================
  // 3. Stale Token Defense & Server Revocation
  // =========================================================================
  describe('3. Stale Token Defense & Server Revocation', () => {

    function canWriteRTDB(auth, targetUid, rootState) {
      if (!auth) return false;
      if (auth.uid !== targetUid) return false;

      // 1. Claims check
      if (auth.token?.role !== 'driver' && auth.token?.driver !== true) return false;
      if (auth.token?.approved !== true) return false;
      if (auth.token?.suspended === true) return false;
      if (auth.token?.disabled === true || auth.token?.deactivated === true) return false;

      // 2. Real-time Server-Authoritative Database Revocation Check (root.child)
      if (rootState.suspended_drivers && rootState.suspended_drivers[auth.uid] !== undefined) {
        return false; // Instant revocation regardless of unexpired token
      }
      if (rootState.deactivated_users && rootState.deactivated_users[auth.uid] !== undefined) {
        return false;
      }

      return true;
    }

    it('blocks driver whose account was suspended in RTDB even when holding an unexpired JWT with approved: true', () => {
      // Driver logged in 10 minutes ago, JWT is valid for another 50 minutes with approved: true
      const staleAuth = {
        uid: 'drv_hacker',
        token: { role: 'driver', driver: true, approved: true, exp: Date.now() + 3000000 },
      };

      // Admin just executed executeAdminSuspendDriver: RTDB has suspended_drivers node
      const rootState = {
        suspended_drivers: {
          drv_hacker: { suspended_at: Date.now(), reason: 'Safety complaint' },
        },
      };

      assert.equal(canWriteRTDB(staleAuth, 'drv_hacker', rootState), false);
    });

    it('blocks deactivated driver whose account was deactivated in RTDB regardless of unexpired token', () => {
      const staleAuth = {
        uid: 'drv_deactivated',
        token: { role: 'driver', driver: true, approved: true },
      };
      const rootState = {
        deactivated_users: { drv_deactivated: true },
      };
      assert.equal(canWriteRTDB(staleAuth, 'drv_deactivated', rootState), false);
    });

    it('allows approved, unsuspended driver with valid token to publish', () => {
      const validAuth = {
        uid: 'drv_good',
        token: { role: 'driver', driver: true, approved: true },
      };
      const rootState = {
        suspended_drivers: {},
        deactivated_users: {},
      };
      assert.equal(canWriteRTDB(validAuth, 'drv_good', rootState), true);
    });
  });

  // =========================================================================
  // 4. Location Privacy & Access Control
  // =========================================================================
  describe('4. Location Privacy & Access Control', () => {

    function canReadDriverLocation(auth, targetDriverId, driverData) {
      if (!auth) return false;
      const isSelf = auth.uid === targetDriverId;
      const isAdmin = auth.token?.role === 'admin' || auth.token?.admin === true;
      const isAssignedRider = driverData?.active_rider_id === auth.uid;

      return isSelf || isAdmin || isAssignedRider;
    }

    it('allows assigned rider to stream live telemetry of their assigned captain', () => {
      const authRider = { uid: 'rider_fatima', token: { role: 'rider' } };
      const driverData = { active_rider_id: 'rider_fatima', lat: 30.04, lng: 31.23 };
      assert.equal(canReadDriverLocation(authRider, 'drv_captain', driverData), true);
    });

    it('blocks unrelated riders from streaming other drivers coordinates', () => {
      const authStranger = { uid: 'rider_stranger', token: { role: 'rider' } };
      const driverData = { active_rider_id: 'rider_fatima', lat: 30.04, lng: 31.23 };
      assert.equal(canReadDriverLocation(authStranger, 'drv_captain', driverData), false);
    });

    it('blocks competing drivers from spying on competitor captain coordinates', () => {
      const authCompetitor = { uid: 'drv_competitor', token: { role: 'driver' } };
      const driverData = { active_rider_id: 'rider_fatima', lat: 30.04, lng: 31.23 };
      assert.equal(canReadDriverLocation(authCompetitor, 'drv_captain', driverData), false);
    });

    it('allows admin full fleet monitoring access', () => {
      const authAdmin = { uid: 'admin_ops', token: { role: 'admin' } };
      const driverData = { active_rider_id: 'rider_fatima', lat: 30.04, lng: 31.23 };
      assert.equal(canReadDriverLocation(authAdmin, 'drv_captain', driverData), true);
    });
  });

  // =========================================================================
  // 5. Presence Lifecycle & onDisconnect Invariants
  // =========================================================================
  describe('5. Presence Lifecycle & onDisconnect Invariants', () => {

    class MockRTDBPresenceSession {
      constructor(driverId) {
        this.driverId = driverId;
        this.isConnected = false;
        this.presence = { state: 'offline', last_changed: 0 };
        this.location = { is_online: false, updated_at: 0 };
        this.onDisconnectHandlers = [];
      }

      connect() {
        this.isConnected = true;
        // Register onDisconnect handler
        this.onDisconnectHandlers.push(() => {
          this.presence.state = 'offline';
          this.presence.last_changed = Date.now();
          this.location.is_online = false;
          this.location.updated_at = Date.now();
        });
      }

      goOnline() {
        if (!this.isConnected) throw new Error('NOT_CONNECTED');
        this.presence.state = 'online';
        this.presence.last_changed = Date.now();
        this.location.is_online = true;
        this.location.updated_at = Date.now();
      }

      goOffline() {
        this.presence.state = 'offline';
        this.presence.last_changed = Date.now();
        this.location.is_online = false;
        this.location.updated_at = Date.now();
      }

      simulateNetworkDrop() {
        // Firebase Server triggers onDisconnect handlers
        this.isConnected = false;
        for (const handler of this.onDisconnectHandlers) {
          handler();
        }
        this.onDisconnectHandlers = [];
      }
    }

    it('correctly transitions presence from offline -> online -> network drop (onDisconnect triggers offline)', () => {
      const session = new MockRTDBPresenceSession('drv_001');
      assert.equal(session.presence.state, 'offline');
      assert.equal(session.location.is_online, false);

      // Connect & go online
      session.connect();
      session.goOnline();
      assert.equal(session.presence.state, 'online');
      assert.equal(session.location.is_online, true);

      // Sudden connection loss (app crash, cellular deadzone)
      session.simulateNetworkDrop();
      assert.equal(session.presence.state, 'offline');
      assert.equal(session.location.is_online, false);
      assert.ok(session.presence.last_changed > 0);
    });

    it('correctly cleans up presence when captain manually toggles offline', () => {
      const session = new MockRTDBPresenceSession('drv_002');
      session.connect();
      session.goOnline();
      assert.equal(session.location.is_online, true);

      session.goOffline();
      assert.equal(session.presence.state, 'offline');
      assert.equal(session.location.is_online, false);
    });
  });

  // =========================================================================
  // 6. Stale Telemetry Filter & 3 KM Matching
  // =========================================================================
  describe('6. Stale Telemetry Heartbeat & 3 KM Dispatch Filter', () => {

    function filterEligibleDrivers(drivers, pickupLat, pickupLng, radiusKm, maxHeartbeatMs = 60000) {
      const now = Date.now();
      const eligible = [];

      function haversineKm(lat1, lon1, lat2, lon2) {
        const R = 6371.0;
        const dLat = (lat2 - lat1) * Math.PI / 180.0;
        const dLon = (lon2 - lon1) * Math.PI / 180.0;
        const a = Math.sin(dLat / 2) ** 2 +
          Math.cos(lat1 * Math.PI / 180.0) * Math.cos(lat2 * Math.PI / 180.0) * Math.sin(dLon / 2) ** 2;
        return R * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
      }

      for (const [id, d] of Object.entries(drivers)) {
        if (!d.is_online || d.is_busy) continue;
        if (d.status !== 'approved') continue;
        // Server-authoritative telemetry heartbeat freshness
        if (!d.updated_at || typeof d.updated_at !== 'number') continue;
        if (d.updated_at > now + 5000 || (now - d.updated_at > maxHeartbeatMs)) continue;

        const dist = haversineKm(pickupLat, pickupLng, d.lat, d.lng);
        if (dist <= radiusKm) {
          eligible.push({ driver_id: id, distance_km: Math.round(dist * 100) / 100 });
        }
      }

      return eligible.sort((a, b) => a.distance_km - b.distance_km);
    }

    const pickupLat = 30.0444; // Tahrir Square
    const pickupLng = 31.2357;

    it('excludes drivers whose telemetry heartbeat is older than 60 seconds', () => {
      const now = Date.now();
      const drivers = {
        // Driver 1: 1.2 KM away, fresh heartbeat (5 seconds ago) -> ELIGIBLE
        drv_fresh: {
          lat: 30.0520, lng: 31.2410,
          is_online: true, is_busy: false, status: 'approved',
          updated_at: now - 5000,
        },
        // Driver 2: 0.8 KM away, but stale heartbeat (85 seconds ago) -> EXCLUDED
        drv_stale: {
          lat: 30.0480, lng: 31.2390,
          is_online: true, is_busy: false, status: 'approved',
          updated_at: now - 85000,
        },
      };

      const result = filterEligibleDrivers(drivers, pickupLat, pickupLng, 3.0);
      assert.equal(result.length, 1);
      assert.equal(result[0].driver_id, 'drv_fresh');
    });

    it('excludes drivers who submitted future timestamps to spoof continuous freshness', () => {
      const now = Date.now();
      const drivers = {
        // Driver 1: 1.0 KM away, fresh heartbeat (2s ago) -> ELIGIBLE
        drv_legit: {
          lat: 30.0500, lng: 31.2400,
          is_online: true, is_busy: false, status: 'approved',
          updated_at: now - 2000,
        },
        // Driver 2: 0.5 KM away, but injected future timestamp (1 hour in the future) -> EXCLUDED
        drv_forged_future: {
          lat: 30.0460, lng: 31.2370,
          is_online: true, is_busy: false, status: 'approved',
          updated_at: now + 3600000,
        },
      };

      const result = filterEligibleDrivers(drivers, pickupLat, pickupLng, 3.0);
      assert.equal(result.length, 1);
      assert.equal(result[0].driver_id, 'drv_legit');
    });

    it('excludes drivers with missing, null, or non-numeric timestamps from dispatch', () => {
      const now = Date.now();
      const drivers = {
        drv_missing: {
          lat: 30.0500, lng: 31.2400,
          is_online: true, is_busy: false, status: 'approved',
        },
        drv_string_time: {
          lat: 30.0500, lng: 31.2400,
          is_online: true, is_busy: false, status: 'approved',
          updated_at: '2026-11-02T13:00:00Z',
        },
      };

      const result = filterEligibleDrivers(drivers, pickupLat, pickupLng, 3.0);
      assert.equal(result.length, 0, 'Drivers with missing or non-numeric timestamps must be excluded');
    });

    it('enforces 3 KM radius cutoff for candidate drivers', () => {
      const now = Date.now();
      const drivers = {
        // 2.2 KM away -> within 3 KM
        drv_inside: {
          lat: 30.0600, lng: 31.2450,
          is_online: true, is_busy: false, status: 'approved',
          updated_at: now - 2000,
        },
        // 5.8 KM away (Nasr City) -> outside 3 KM initial radius
        drv_outside: {
          lat: 30.0600, lng: 31.2950,
          is_online: true, is_busy: false, status: 'approved',
          updated_at: now - 2000,
        },
      };

      const result = filterEligibleDrivers(drivers, pickupLat, pickupLng, 3.0);
      assert.equal(result.length, 1);
      assert.equal(result[0].driver_id, 'drv_inside');
    });
  });

});
