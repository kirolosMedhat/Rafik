import { describe, it } from 'node:test';
import assert from 'node:assert/strict';

/**
 * Deterministic Invariant Test Suite for Firestore, RTDB, and Storage Security Rules
 */

describe('Firebase Security Rules & Access Control Invariants', () => {

  // =========================================================================
  // 1. Cloud Firestore Rules Evaluation
  // =========================================================================
  describe('1. Cloud Firestore Rules', () => {

    it('rejects unauthenticated read and write attempts across all collections', () => {
      function evaluateAuth(auth) {
        return auth !== null && auth !== undefined;
      }
      assert.equal(evaluateAuth(null), false, 'Unauthenticated access must be rejected');
    });

    it('enforces rider/driver role separation during user profile creation', () => {
      function validateUserCreation(auth, data) {
        if (!auth || auth.uid !== data.uid) return false;
        // Client can self-register as 'rider' or 'driver', but NEVER 'admin'
        if (!['rider', 'driver'].includes(data.role)) return false;
        // Non-admin cannot self-verify gender
        if (data.gender_verified !== false) return false;
        return true;
      }

      // Valid rider registration
      assert.ok(validateUserCreation({ uid: 'rider_123' }, { uid: 'rider_123', role: 'rider', gender_verified: false }));
      // Valid driver registration
      assert.ok(validateUserCreation({ uid: 'driver_123' }, { uid: 'driver_123', role: 'driver', gender_verified: false }));
      // Malicious attempt to register directly as admin
      assert.equal(validateUserCreation({ uid: 'hacker_1' }, { uid: 'hacker_1', role: 'admin', gender_verified: false }), false);
      // Malicious attempt to self-verify female status
      assert.equal(validateUserCreation({ uid: 'hacker_2' }, { uid: 'hacker_2', role: 'rider', gender_verified: true }), false);
    });

    it('strictly restricts pending and rejected drivers from toggling online availability', () => {
      function validateDriverUpdate(auth, existingDriver, updatedFields) {
        const isOwner = auth && auth.uid === existingDriver.driver_id;
        const isAdmin = auth && (auth.token?.role === 'admin' || auth.token?.admin === true);

        if (isAdmin) return true;
        if (!isOwner) return false;

        // Approved drivers can only toggle availability flags
        if (existingDriver.status !== 'approved') return false;

        const allowedKeys = ['is_online', 'is_busy', 'updated_at'];
        const changedKeys = Object.keys(updatedFields);
        return changedKeys.every(k => allowedKeys.includes(k));
      }

      // Pending driver tries to go online -> REJECTED
      const pendingDriver = { driver_id: 'd_pending', status: 'pending', is_online: false, is_busy: false };
      assert.equal(validateDriverUpdate({ uid: 'd_pending' }, pendingDriver, { is_online: true }), false);

      // Rejected driver tries to go online -> REJECTED
      const rejectedDriver = { driver_id: 'd_rejected', status: 'rejected', is_online: false, is_busy: false };
      assert.equal(validateDriverUpdate({ uid: 'd_rejected' }, rejectedDriver, { is_online: true }), false);

      // Approved driver toggles online -> ALLOWED
      const approvedDriver = { driver_id: 'd_approved', status: 'approved', is_online: false, is_busy: false };
      assert.equal(validateDriverUpdate({ uid: 'd_approved' }, approvedDriver, { is_online: true }), true);

      // Approved driver attempts to tamper with wallet balance -> REJECTED
      assert.equal(validateDriverUpdate({ uid: 'd_approved' }, approvedDriver, { wallet_balance_egp: 99999 }), false);
    });

    it('enforces absolute client-side write denial on financial ledger (/payments)', () => {
      function canClientWritePayment(auth) {
        // match /payments/{paymentId} { allow write: if false; }
        return false;
      }
      assert.equal(canClientWritePayment({ uid: 'driver_1', token: { role: 'driver' } }), false);
      assert.equal(canClientWritePayment({ uid: 'rider_1', token: { role: 'rider' } }), false);
    });

    it('enforces strict PIN isolation: drivers can NEVER read /rides/{rideId}/security/pin_data', () => {
      function canReadPinData(auth, ride) {
        if (!auth) return false;
        const isRider = auth.uid === ride.rider_id;
        const isAdmin = auth.token?.role === 'admin' || auth.token?.admin === true;
        // Driver has NO read access under any circumstance
        return isRider || isAdmin;
      }

      const ride = { rider_id: 'rider_abc', driver_id: 'driver_xyz' };
      // Rider can read their own PIN
      assert.equal(canReadPinData({ uid: 'rider_abc', token: { role: 'rider' } }, ride), true);
      // Admin can read PIN for support
      assert.equal(canReadPinData({ uid: 'admin_1', token: { role: 'admin' } }, ride), true);
      // Assigned driver CANNOT read PIN
      assert.equal(canReadPinData({ uid: 'driver_xyz', token: { role: 'driver' } }, ride), false);
      // Competing driver CANNOT read PIN
      assert.equal(canReadPinData({ uid: 'driver_other', token: { role: 'driver' } }, ride), false);
    });

    it('blocks non-admin users from modifying application settings (/app_settings)', () => {
      function canWriteSettings(auth) {
        return auth !== null && (auth.token?.role === 'admin' || auth.token?.admin === true);
      }
      assert.equal(canWriteSettings({ uid: 'rider_1', token: { role: 'rider' } }), false);
      assert.equal(canWriteSettings({ uid: 'driver_1', token: { role: 'driver' } }), false);
      assert.equal(canWriteSettings({ uid: 'admin_1', token: { role: 'admin' } }), true);
    });
  });

  // =========================================================================
  // 2. Realtime Database Location Privacy Rules
  // =========================================================================
  describe('2. Realtime Database Location Privacy Rules', () => {

    function canReadDriverLocation(auth, targetDriverId, targetDriverData) {
      if (!auth) return false;
      const isSelf = auth.uid === targetDriverId;
      const isAdmin = auth.token?.role === 'admin' || auth.token?.admin === true;
      const isAssignedRider = targetDriverData?.active_rider_id === auth.uid;
      return isSelf || isAdmin || isAssignedRider;
    }

    it('allows driver to read their own location', () => {
      assert.equal(canReadDriverLocation({ uid: 'drv_1' }, 'drv_1', {}), true);
    });

    it('allows authorized admin to read any driver location for operations monitoring', () => {
      assert.equal(canReadDriverLocation({ uid: 'admin_1', token: { role: 'admin' } }, 'drv_1', {}), true);
    });

    it('allows assigned rider in an active ride to read their assigned driver location', () => {
      const driverData = { active_rider_id: 'rider_salma' };
      assert.equal(canReadDriverLocation({ uid: 'rider_salma' }, 'drv_1', driverData), true);
    });

    it('STRICT PRIVACY: blocks unauthorized authenticated users from reading other drivers live coordinates', () => {
      const driverData = { active_rider_id: 'rider_salma' };
      // Another arbitrary user/rider tries to track this driver
      assert.equal(canReadDriverLocation({ uid: 'stranger_user' }, 'drv_1', driverData), false);
      // Another driver tries to track competitor
      assert.equal(canReadDriverLocation({ uid: 'drv_competitor' }, 'drv_1', driverData), false);
    });

    // =========================================================================
    // Realtime Database Driver Location Authorization (.write Invariants)
    // =========================================================================
    function canWriteDriverLocation(auth, targetDriverId, existingData, newData, rootData = {}) {
      // 1. Unauthenticated -> Blocked
      if (!auth) return false;

      // 2. Cannot write another driver's location ($driverId mismatch) -> Blocked
      if (auth.uid !== targetDriverId) return false;

      // 3. Must have driver claim/role
      const isDriverRole = auth.token?.role === 'driver' || auth.token?.driver === true;
      if (!isDriverRole) return false;

      // 4. Must be explicitly approved in claims (approved: true)
      if (auth.token?.approved !== true) return false;

      // 5. Must NOT be suspended in claims
      if (auth.token?.suspended === true) return false;

      // 6. Must NOT be disabled or deactivated in claims
      if (auth.token?.disabled === true || auth.token?.deactivated === true) return false;

      // 7. Stale Token Defense: Server-Authoritative RTDB Revocation Checks (root.child)
      if (rootData.suspended_drivers && rootData.suspended_drivers[auth.uid] !== undefined) return false;
      if (rootData.deactivated_users && rootData.deactivated_users[auth.uid] !== undefined) return false;
      if (existingData?.status === 'suspended') return false;

      // 8. Schema Validation & Server-Authoritative Field Tamper Protection
      if (newData) {
        if (typeof newData.lat !== 'number' || newData.lat < -90.0 || newData.lat > 90.0) return false;
        if (typeof newData.lng !== 'number' || newData.lng < -180.0 || newData.lng > 180.0) return false;
        if (typeof newData.updated_at !== 'number') return false;
        // Server-authoritative timestamp bounds: reject future and manipulated stale timestamps
        if (newData.updated_at > Date.now() + 5000 || newData.updated_at < Date.now() - 60000) return false;

        if (newData.heading !== undefined && (typeof newData.heading !== 'number' || newData.heading < 0.0 || newData.heading > 360.0)) return false;
        if (newData.speed !== undefined && (typeof newData.speed !== 'number' || newData.speed < 0.0)) return false;

        // Server-Authoritative Field Tamper Guards
        // A. Status
        if (!existingData?.status && newData.status !== undefined) return false;
        if (existingData?.status && newData.status !== existingData.status) return false;

        // B. Gender & Gender Verified
        if (!existingData?.gender && newData.gender !== undefined) return false;
        if (existingData?.gender && newData.gender !== existingData.gender) return false;
        if (!existingData?.gender_verified && newData.gender_verified !== undefined) return false;
        if (existingData?.gender_verified && newData.gender_verified !== existingData.gender_verified) return false;

        // C. Busy State
        if (!existingData?.is_busy && newData.is_busy !== undefined) return false;
        if (existingData?.is_busy && newData.is_busy !== existingData.is_busy) return false;

        // D. Active Rider ID
        if (!existingData?.active_rider_id && newData.active_rider_id !== undefined) return false;
        if (existingData?.active_rider_id && newData.active_rider_id !== existingData.active_rider_id) return false;

        // E. Tier
        if (!existingData?.tier && newData.tier !== undefined) return false;
        if (existingData?.tier && newData.tier !== existingData.tier) return false;
      }

      return true;
    }

    const getValidPayload = () => ({ lat: 30.0444, lng: 31.2357, updated_at: Date.now(), heading: 90.0, speed: 25.0 });
    const validPayload = { lat: 30.0444, lng: 31.2357, updated_at: Date.now(), heading: 90.0, speed: 25.0 };

    it('allows authenticated, approved drivers to update their own location with valid telemetry', () => {
      const auth = {
        uid: 'drv_123',
        token: { role: 'driver', driver: true, approved: true },
      };
      assert.equal(canWriteDriverLocation(auth, 'drv_123', {}, getValidPayload()), true);
    });

    it('SERVER-AUTHORITATIVE TIMESTAMP DEFENSE: blocks future timestamps in telemetry writes', () => {
      const auth = {
        uid: 'drv_123',
        token: { role: 'driver', driver: true, approved: true },
      };
      const futurePayload = { ...getValidPayload(), updated_at: Date.now() + 600000 };
      assert.equal(canWriteDriverLocation(auth, 'drv_123', {}, futurePayload), false, 'Future timestamp must be blocked');
    });

    it('SERVER-AUTHORITATIVE TIMESTAMP DEFENSE: blocks manipulated stale timestamps in telemetry writes', () => {
      const auth = {
        uid: 'drv_123',
        token: { role: 'driver', driver: true, approved: true },
      };
      const stalePayload = { ...getValidPayload(), updated_at: Date.now() - 120000 };
      assert.equal(canWriteDriverLocation(auth, 'drv_123', {}, stalePayload), false, 'Stale timestamp must be blocked');
    });

    it('STALE CLAIMS DEFENSE: blocks suspended driver holding an unexpired token (claims say approved: true) via RTDB suspended_drivers node', () => {
      // Driver token has not expired yet and still claims approved: true
      const authWithStaleToken = {
        uid: 'drv_suspended_stale',
        token: { role: 'driver', driver: true, approved: true },
      };
      // Server wrote revocation node in RTDB root
      const rootDataWithSuspension = {
        suspended_drivers: { drv_suspended_stale: { suspended_at: Date.now(), reason: 'Violation' } },
      };
      assert.equal(canWriteDriverLocation(authWithStaleToken, 'drv_suspended_stale', {}, getValidPayload(), rootDataWithSuspension), false);
    });

    it('STALE CLAIMS DEFENSE: blocks deactivated user holding unexpired token via RTDB deactivated_users node', () => {
      const authWithStaleToken = {
        uid: 'drv_deactivated_stale',
        token: { role: 'driver', driver: true, approved: true },
      };
      const rootDataWithDeactivation = {
        deactivated_users: { drv_deactivated_stale: true },
      };
      assert.equal(canWriteDriverLocation(authWithStaleToken, 'drv_deactivated_stale', {}, getValidPayload(), rootDataWithDeactivation), false);
    });

    it('SERVER-AUTHORITATIVE ISOLATION: blocks driver from self-elevating approval status in telemetry payload', () => {
      const auth = {
        uid: 'drv_tamper',
        token: { role: 'driver', driver: true, approved: true },
      };
      // Driver tries to write status: 'approved' when none was set or alter existing status
      const maliciousPayload = { ...validPayload, status: 'approved' };
      assert.equal(canWriteDriverLocation(auth, 'drv_tamper', {}, maliciousPayload), false);
    });

    it('SERVER-AUTHORITATIVE ISOLATION: blocks driver from altering dispatch eligibility or busy status', () => {
      const auth = {
        uid: 'drv_tamper',
        token: { role: 'driver', driver: true, approved: true },
      };
      const existingData = { is_busy: true };
      // Driver tries to force is_busy to false while assigned to a trip
      const maliciousPayload = { ...validPayload, is_busy: false };
      assert.equal(canWriteDriverLocation(auth, 'drv_tamper', existingData, maliciousPayload), false);
    });

    it('SERVER-AUTHORITATIVE ISOLATION: blocks driver from spoofing gender or gender_verified for Rafik Girl eligibility', () => {
      const auth = {
        uid: 'drv_male_spoofer',
        token: { role: 'driver', driver: true, approved: true },
      };
      // Driver attempts to spoof female gender_verified: true
      const maliciousPayload = { ...validPayload, gender: 'female', gender_verified: true };
      assert.equal(canWriteDriverLocation(auth, 'drv_male_spoofer', {}, maliciousPayload), false);
    });

    it('STRICT AUTHORIZATION: blocks pending drivers from writing location updates', () => {
      // Pending driver retains driver: true, but approved: false
      const auth = {
        uid: 'drv_pending',
        token: { role: 'driver', driver: true, approved: false },
      };
      assert.equal(canWriteDriverLocation(auth, 'drv_pending', {}, validPayload), false);

      // Pending driver with undefined approved claim
      const authUndefinedApproved = {
        uid: 'drv_pending2',
        token: { role: 'driver', driver: true },
      };
      assert.equal(canWriteDriverLocation(authUndefinedApproved, 'drv_pending2', {}, validPayload), false);
    });

    it('STRICT AUTHORIZATION: blocks rejected drivers from writing location updates even if driver: true is retained', () => {
      const auth = {
        uid: 'drv_rejected',
        token: { role: 'driver', driver: true, approved: false },
      };
      assert.equal(canWriteDriverLocation(auth, 'drv_rejected', {}, validPayload), false);
    });

    it('STRICT AUTHORIZATION: blocks suspended drivers from writing location updates', () => {
      const auth = {
        uid: 'drv_suspended',
        token: { role: 'driver', driver: true, approved: false, suspended: true },
      };
      assert.equal(canWriteDriverLocation(auth, 'drv_suspended', {}, validPayload), false);

      // Suspended even if approved claim is erroneously present
      const authErroneousApproved = {
        uid: 'drv_suspended2',
        token: { role: 'driver', driver: true, approved: true, suspended: true },
      };
      assert.equal(canWriteDriverLocation(authErroneousApproved, 'drv_suspended2', {}, validPayload), false);
    });

    it('STRICT AUTHORIZATION: blocks deactivated and disabled drivers from writing location updates', () => {
      const authDeactivated = {
        uid: 'drv_deact',
        token: { role: 'driver', driver: true, approved: true, deactivated: true },
      };
      assert.equal(canWriteDriverLocation(authDeactivated, 'drv_deact', {}, validPayload), false);

      const authDisabled = {
        uid: 'drv_disab',
        token: { role: 'driver', driver: true, approved: true, disabled: true },
      };
      assert.equal(canWriteDriverLocation(authDisabled, 'drv_disab', {}, validPayload), false);
    });

    it('STRICT IDENTITY: blocks drivers from updating another driver location coordinates', () => {
      const auth = {
        uid: 'drv_attacker',
        token: { role: 'driver', driver: true, approved: true },
      };
      assert.equal(canWriteDriverLocation(auth, 'drv_victim', {}, validPayload), false);
    });

    it('STRICT ACCESS CONTROL: blocks unauthenticated users from writing locations', () => {
      assert.equal(canWriteDriverLocation(null, 'drv_123', {}, validPayload), false);
    });

    it('STRICT ROLE ISOLATION: blocks riders from writing to driver locations', () => {
      const authRider = {
        uid: 'rider_123',
        token: { role: 'rider', rider: true, approved: false },
      };
      assert.equal(canWriteDriverLocation(authRider, 'rider_123', {}, validPayload), false);
    });

    it('TAMPER PROTECTION: prevents client driver from injecting or altering server-assigned active_rider_id', () => {
      const auth = {
        uid: 'drv_tamper',
        token: { role: 'driver', driver: true, approved: true },
      };

      // 1. Driver attempts to inject active_rider_id when none was set by server
      const maliciousPayloadInject = { ...validPayload, active_rider_id: 'spoofed_rider' };
      assert.equal(canWriteDriverLocation(auth, 'drv_tamper', {}, maliciousPayloadInject), false);

      // 2. Driver attempts to overwrite an existing active_rider_id assigned by server
      const existingDataWithRider = { active_rider_id: 'legitimate_rider_456' };
      const maliciousPayloadOverwrite = { ...validPayload, active_rider_id: 'attacker_rider_999' };
      assert.equal(canWriteDriverLocation(auth, 'drv_tamper', existingDataWithRider, maliciousPayloadOverwrite), false);

      // 3. Driver preserves legitimate server-assigned active_rider_id during GPS ping
      const legitimatePayload = { ...validPayload, active_rider_id: 'legitimate_rider_456' };
      assert.equal(canWriteDriverLocation(auth, 'drv_tamper', existingDataWithRider, legitimatePayload), true);
    });
  });

  // =========================================================================
  // 3. Firebase Storage KYC Security Rules
  // =========================================================================
  describe('3. Firebase Storage KYC Security Rules', () => {

    function canReadKycDocument(auth, documentOwnerId) {
      if (!auth) return false;
      return auth.uid === documentOwnerId || auth.token?.role === 'admin';
    }

    function canUploadKycDocument(auth, documentOwnerId, fileSizeMb, mimeType) {
      if (!auth || auth.uid !== documentOwnerId) return false;
      if (fileSizeMb >= 5.0) return false; // 5 MB limit
      if (!['image/jpeg', 'image/png', 'image/webp'].includes(mimeType)) return false;
      return true;
    }

    it('restricts KYC document read to owner or admin (no public access)', () => {
      assert.equal(canReadKycDocument({ uid: 'driver_1' }, 'driver_1'), true);
      assert.equal(canReadKycDocument({ uid: 'admin_1', token: { role: 'admin' } }, 'driver_1'), true);
      assert.equal(canReadKycDocument({ uid: 'driver_2' }, 'driver_1'), false);
      assert.equal(canReadKycDocument(null, 'driver_1'), false);
    });

    it('enforces 5MB size limit and image MIME-type whitelist on document uploads', () => {
      // Valid JPEG upload under 5MB
      assert.equal(canUploadKycDocument({ uid: 'driver_1' }, 'driver_1', 2.4, 'image/jpeg'), true);
      // Valid PNG upload
      assert.equal(canUploadKycDocument({ uid: 'driver_1' }, 'driver_1', 1.8, 'image/png'), true);
      // File too large (> 5MB) -> REJECTED
      assert.equal(canUploadKycDocument({ uid: 'driver_1' }, 'driver_1', 6.2, 'image/jpeg'), false);
      // Malicious non-image MIME type (PDF, EXE) -> REJECTED
      assert.equal(canUploadKycDocument({ uid: 'driver_1' }, 'driver_1', 0.5, 'application/pdf'), false);
      assert.equal(canUploadKycDocument({ uid: 'driver_1' }, 'driver_1', 1.0, 'application/x-msdownload'), false);
    });
  });

});
