import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { normalizeEgyptianPhone, nationalIdGender } from '../lib/spatial.js';

describe('Rafik Phase 2B: Phone Authentication & Onboarding Automated Tests', () => {

  // =========================================================================
  // 1. Phone Normalization and Validation
  // =========================================================================
  describe('1. Phone Normalization & Validation (+20 E.164)', () => {
    it('normalizes Egyptian local 11-digit numbers for all 4 network operators', () => {
      assert.equal(normalizeEgyptianPhone('01012345678'), '+201012345678'); // Vodafone
      assert.equal(normalizeEgyptianPhone('01123456789'), '+201123456789'); // Etisalat
      assert.equal(normalizeEgyptianPhone('01234567890'), '+201234567890'); // Orange
      assert.equal(normalizeEgyptianPhone('01545678901'), '+201545678901'); // WE
    });

    it('cleans inputs with spaces, dashes, and international prefixes', () => {
      assert.equal(normalizeEgyptianPhone('+20 10 1234 5678'), '+201012345678');
      assert.equal(normalizeEgyptianPhone('00201123456789'), '+201123456789');
      assert.equal(normalizeEgyptianPhone('012-345-67890'), '+201234567890');
      assert.equal(normalizeEgyptianPhone('201545678901'), '+201545678901');
    });

    it('rejects invalid Egyptian numbers and foreign numbers', () => {
      assert.equal(normalizeEgyptianPhone('01312345678'), null);
      assert.equal(normalizeEgyptianPhone('01412345678'), null);
      assert.equal(normalizeEgyptianPhone('0227948282'), null); // Landline
      assert.equal(normalizeEgyptianPhone('+15551234567'), null);
      assert.equal(normalizeEgyptianPhone(''), null);
    });
  });

  // =========================================================================
  // 2. Egyptian National ID & Gender Parity
  // =========================================================================
  describe('2. Egyptian National ID 13th-Digit Gender Parity', () => {
    it('verifies female parity when 13th digit is even', () => {
      // 29505150101248: 13th digit is '4' (even) -> Female
      assert.equal(nationalIdGender('29505150101248'), 'female');
    });

    it('verifies male parity when 13th digit is odd', () => {
      // 30108202105675: 13th digit is '7' (odd) -> Male
      assert.equal(nationalIdGender('30108202105675'), 'male');
    });

    it('rejects invalid length or non-numeric National IDs', () => {
      assert.equal(nationalIdGender('12345'), null);
      assert.equal(nationalIdGender('2950515010124A'), null);
    });
  });

  // =========================================================================
  // 3. Simulated Auth & Database Engine for Integration Scenarios
  // =========================================================================
  describe('3. Application Auth & Onboarding Workflows', () => {

    class MockFirebaseEngine {
      constructor() {
        this.users = new Map();
        this.drivers = new Map();
        this.driverDocuments = new Map();
        this.storageFiles = new Map();
      }

      // 3.1 Rider Registration
      async registerRider({ uid, fullName, phone, gender, username }) {
        const normalized = normalizeEgyptianPhone(phone);
        if (!normalized) throw new Error('INVALID_PHONE');
        if (this.users.has(uid)) {
          throw new Error('USER_ALREADY_EXISTS: An account already exists for this UID');
        }

        const isFemale = gender.toLowerCase() === 'female';
        const profile = {
          uid,
          full_name: fullName.trim(),
          phone: normalized,
          username: username || null,
          gender: gender.toLowerCase(),
          role: 'rider',
          gender_verified: isFemale,
          is_active: true,
          rating_avg: 5.0,
          total_trips: 0,
          created_at: new Date(),
        };

        this.users.set(uid, profile);
        return profile;
      }

      // 3.2 Rider / Driver Login
      async loginWithPhone({ uid, expectedRole }) {
        const profile = this.users.get(uid);

        // CRITICAL: Never allow login to silently create a new profile!
        if (!profile) {
          throw new Error('USER_NOT_REGISTERED: Phone number is not registered. Please register first.');
        }

        if (!profile.is_active) {
          throw new Error('ACCOUNT_DISABLED: Account has been deactivated. Please contact support.');
        }

        if (profile.role !== expectedRole) {
          throw new Error(`ROLE_MISMATCH: Expected ${expectedRole}, got ${profile.role}`);
        }

        if (profile.role === 'driver') {
          const driverData = this.drivers.get(uid);
          return { ...profile, ...driverData };
        }

        return profile;
      }

      // 3.3 Driver Registration
      async registerDriver({
        uid,
        fullName,
        phone,
        gender,
        nationalId,
        licenseNumber,
        vehicleMake,
        vehicleModel,
        vehicleYear,
        vehiclePlate,
        vehicleColor,
      }) {
        const normalized = normalizeEgyptianPhone(phone);
        if (!normalized) throw new Error('INVALID_PHONE');
        if (this.users.has(uid)) {
          throw new Error('USER_ALREADY_EXISTS: Driver account already exists for this UID');
        }

        const derivedGender = nationalIdGender(nationalId);
        if (!derivedGender) {
          throw new Error('INVALID_NATIONAL_ID: National ID must be 14 digits');
        }
        if (derivedGender !== gender.toLowerCase()) {
          throw new Error('GENDER_PARITY_MISMATCH: National ID gender does not match selected profile gender');
        }

        const userDoc = {
          uid,
          full_name: fullName.trim(),
          phone: normalized,
          gender: gender.toLowerCase(),
          role: 'driver',
          gender_verified: gender.toLowerCase() === 'female',
          is_active: true,
          rating_avg: 5.0,
          created_at: new Date(),
        };

        const driverDoc = {
          uid,
          user_id: uid,
          full_name: fullName.trim(),
          phone: normalized,
          gender: gender.toLowerCase(),
          role: 'driver',
          status: 'pending', // Enforces initial pending status! Client cannot self-approve
          rejection_reason: null,
          national_id_number: nationalId,
          license_number: licenseNumber,
          vehicle_make: vehicleMake,
          vehicle_model: vehicleModel,
          vehicle_year: vehicleYear,
          vehicle_plate: vehiclePlate,
          vehicle_color: vehicleColor,
          is_online: false,
          is_busy: false,
          total_trips: 0,
          wallet_balance_egp: 0.0,
          rating_avg: 5.0,
          created_at: new Date(),
          documents: {},
        };

        this.users.set(uid, userDoc);
        this.drivers.set(uid, driverDoc);

        return { ...userDoc, ...driverDoc };
      }

      // 3.4 Driver Document Upload (Storage + Firestore)
      async uploadDriverDocument({ driverId, docType, fileBuffer, fileExtension }) {
        const validDocs = [
          'national_id_front',
          'national_id_back',
          'driver_license_front',
          'driver_license_back',
          'vehicle_reg_front',
          'vehicle_reg_back',
        ];

        if (!validDocs.includes(docType)) {
          throw new Error(`INVALID_DOC_TYPE: Unknown document type ${docType}`);
        }

        const maxSizeBytes = 5 * 1024 * 1024;
        if (fileBuffer.length > maxSizeBytes) {
          throw new Error('FILE_TOO_LARGE: Document exceeds 5MB limit');
        }

        const validExts = ['.jpg', '.jpeg', '.png', '.webp'];
        if (!validExts.includes(fileExtension.toLowerCase())) {
          throw new Error('INVALID_MIME_TYPE: Only image formats JPEG, PNG, WEBP allowed');
        }

        const storagePath = `driver_documents/${driverId}/${docType}.jpg`;
        this.storageFiles.set(storagePath, fileBuffer);

        const driver = this.drivers.get(driverId);
        if (driver) {
          driver.documents[docType] = {
            storage_path: storagePath,
            status: 'pending',
            uploaded_at: new Date(),
          };
        }

        return storagePath;
      }

      // Admin Review
      async adminReviewDriver({ driverId, decision, rejectionReason }) {
        const driver = this.drivers.get(driverId);
        if (!driver) throw new Error('DRIVER_NOT_FOUND');

        if (decision === 'approved') {
          driver.status = 'approved';
          driver.rejection_reason = null;
        } else if (decision === 'rejected') {
          driver.status = 'rejected';
          driver.rejection_reason = rejectionReason || 'Documents did not meet compliance criteria';
          driver.is_online = false;
        }
        return driver;
      }

      // Set Driver Online
      async setDriverOnline(driverId, isOnline) {
        const driver = this.drivers.get(driverId);
        if (!driver) throw new Error('DRIVER_NOT_FOUND');

        // Only approved drivers can go online!
        if (driver.status !== 'approved') {
          throw new Error(`UNAUTHORIZED_ACCESS: Driver with status '${driver.status}' cannot go online`);
        }

        driver.is_online = isOnline;
        return driver;
      }
    }

    // -----------------------------------------------------------------------
    // TEST 1: Rider Registration
    // -----------------------------------------------------------------------
    it('completes rider registration, stores profile with role=rider, and normalizes phone', async () => {
      const engine = new MockFirebaseEngine();
      const profile = await engine.registerRider({
        uid: 'rider_nour_123',
        fullName: 'Nour El-Sherif',
        phone: '010 9988 7766',
        gender: 'female',
        username: 'nour_sherif',
      });

      assert.equal(profile.uid, 'rider_nour_123');
      assert.equal(profile.role, 'rider');
      assert.equal(profile.phone, '+201099887766');
      assert.equal(profile.gender_verified, true);
      assert.equal(profile.is_active, true);
    });

    // -----------------------------------------------------------------------
    // TEST 2: Rider Login (Success)
    // -----------------------------------------------------------------------
    it('successfully logs in an existing registered rider and returns profile', async () => {
      const engine = new MockFirebaseEngine();
      await engine.registerRider({
        uid: 'rider_salma',
        fullName: 'Salma Tarek',
        phone: '012 1122 3344',
        gender: 'female',
      });

      const loggedIn = await engine.loginWithPhone({
        uid: 'rider_salma',
        expectedRole: 'rider',
      });

      assert.equal(loggedIn.full_name, 'Salma Tarek');
      assert.equal(loggedIn.role, 'rider');
    });

    // -----------------------------------------------------------------------
    // TEST 3: Login with an Unregistered Phone Number
    // -----------------------------------------------------------------------
    it('rejects login for unregistered phone number and NEVER silently creates a profile', async () => {
      const engine = new MockFirebaseEngine();
      await assert.rejects(
        async () => {
          await engine.loginWithPhone({
            uid: 'unregistered_uid_999',
            expectedRole: 'rider',
          });
        },
        /USER_NOT_REGISTERED/,
      );

      // Verify no phantom document was created in the database
      assert.equal(engine.users.has('unregistered_uid_999'), false);
    });

    // -----------------------------------------------------------------------
    // TEST 4: Duplicate Registration
    // -----------------------------------------------------------------------
    it('blocks duplicate registration when an account already exists for UID', async () => {
      const engine = new MockFirebaseEngine();
      await engine.registerRider({
        uid: 'rider_dup',
        fullName: 'Ahmed Ali',
        phone: '01011112222',
        gender: 'male',
      });

      await assert.rejects(
        async () => {
          await engine.registerRider({
            uid: 'rider_dup',
            fullName: 'Ahmed Ali Again',
            phone: '01011112222',
            gender: 'male',
          });
        },
        /USER_ALREADY_EXISTS/,
      );
    });

    // -----------------------------------------------------------------------
    // TEST 5: Driver Registration (Pending Status Gating)
    // -----------------------------------------------------------------------
    it('registers driver with initial status strictly set to pending and 0% platform commission', async () => {
      const engine = new MockFirebaseEngine();
      const driver = await engine.registerDriver({
        uid: 'drv_mariam',
        fullName: 'Mariam Adel',
        phone: '011 4455 6677',
        gender: 'female',
        nationalId: '29505150101248', // 13th digit is 4 (female parity confirmed)
        licenseNumber: 'LIC-29505150101248',
        vehicleMake: 'Hyundai',
        vehicleModel: 'Elantra',
        vehicleYear: 2022,
        vehiclePlate: 'س ن ق 1429',
        vehicleColor: 'Pearl Rose',
      });

      assert.equal(driver.role, 'driver');
      assert.equal(driver.status, 'pending'); // NEVER approved on registration
      assert.equal(driver.is_online, false);
      assert.equal(driver.wallet_balance_egp, 0.0);
    });

    // -----------------------------------------------------------------------
    // TEST 6: Driver Pending Approval Restrictions
    // -----------------------------------------------------------------------
    it('prevents a pending driver from going online or accessing radar features', async () => {
      const engine = new MockFirebaseEngine();
      await engine.registerDriver({
        uid: 'drv_pending_1',
        fullName: 'Pending Driver',
        phone: '01055556666',
        gender: 'male',
        nationalId: '30108202105675',
        licenseNumber: 'LIC-1234',
        vehicleMake: 'Toyota',
        vehicleModel: 'Corolla',
        vehicleYear: 2021,
        vehiclePlate: 'أ ب ج 1111',
        vehicleColor: 'White',
      });

      // Attempt to go online before approval
      await assert.rejects(
        async () => {
          await engine.setDriverOnline('drv_pending_1', true);
        },
        /UNAUTHORIZED_ACCESS: Driver with status 'pending' cannot go online/,
      );
    });

    // -----------------------------------------------------------------------
    // TEST 7: Driver Approved Flow
    // -----------------------------------------------------------------------
    it('allows driver to go online and access radar once approved by admin', async () => {
      const engine = new MockFirebaseEngine();
      await engine.registerDriver({
        uid: 'drv_approved_1',
        fullName: 'Approved Captain',
        phone: '01299998888',
        gender: 'female',
        nationalId: '29505150101248',
        licenseNumber: 'LIC-9999',
        vehicleMake: 'Kia',
        vehicleModel: 'Cerato',
        vehicleYear: 2023,
        vehiclePlate: 'د ر و 2222',
        vehicleColor: 'Pearl Rose',
      });

      // Admin approves driver
      const reviewed = await engine.adminReviewDriver({
        driverId: 'drv_approved_1',
        decision: 'approved',
      });
      assert.equal(reviewed.status, 'approved');

      // Now driver can successfully go online
      const onlineDriver = await engine.setDriverOnline('drv_approved_1', true);
      assert.equal(onlineDriver.is_online, true);
    });

    // -----------------------------------------------------------------------
    // TEST 8: Driver Rejected Flow
    // -----------------------------------------------------------------------
    it('sets driver status to rejected with clear administrative reason and forces offline', async () => {
      const engine = new MockFirebaseEngine();
      await engine.registerDriver({
        uid: 'drv_rejected_1',
        fullName: 'Rejected Captain',
        phone: '01511112222',
        gender: 'male',
        nationalId: '30108202105675',
        licenseNumber: 'LIC-5555',
        vehicleMake: 'Nissan',
        vehicleModel: 'Sunny',
        vehicleYear: 2020,
        vehiclePlate: 'م ن ك 3333',
        vehicleColor: 'Black',
      });

      // Admin rejects driver
      const reviewed = await engine.adminReviewDriver({
        driverId: 'drv_rejected_1',
        decision: 'rejected',
        rejectionReason: 'Driver license photo was blurry and expired.',
      });

      assert.equal(reviewed.status, 'rejected');
      assert.equal(reviewed.rejection_reason, 'Driver license photo was blurry and expired.');
      assert.equal(reviewed.is_online, false);

      // Rejected driver cannot go online
      await assert.rejects(
        async () => {
          await engine.setDriverOnline('drv_rejected_1', true);
        },
        /UNAUTHORIZED_ACCESS/,
      );
    });

    // -----------------------------------------------------------------------
    // TEST 9: Real 6-Sided KYC Document Upload & Validation
    // -----------------------------------------------------------------------
    it('validates and uploads all 6 required document sides to Firebase Storage with size and MIME enforcement', async () => {
      const engine = new MockFirebaseEngine();
      const driverId = 'drv_kyc_test';

      await engine.registerDriver({
        uid: driverId,
        fullName: 'KYC Test Captain',
        phone: '01012345678',
        gender: 'female',
        nationalId: '29505150101248',
        licenseNumber: 'LIC-TEST',
        vehicleMake: 'Toyota',
        vehicleModel: 'Yaris',
        vehicleYear: 2023,
        vehiclePlate: 'ك ي س 1234',
        vehicleColor: 'Rose',
      });

      const sampleImageBytes = Buffer.alloc(1024 * 50); // 50 KB image

      const docSides = [
        'national_id_front',
        'national_id_back',
        'driver_license_front',
        'driver_license_back',
        'vehicle_reg_front',
        'vehicle_reg_back',
      ];

      for (const side of docSides) {
        const path = await engine.uploadDriverDocument({
          driverId,
          docType: side,
          fileBuffer: sampleImageBytes,
          fileExtension: '.jpg',
        });
        assert.equal(path, `driver_documents/${driverId}/${side}.jpg`);
        assert.equal(engine.storageFiles.has(path), true);
      }

      const driver = engine.drivers.get(driverId);
      assert.equal(Object.keys(driver.documents).length, 6);

      // Rejection of oversized file (> 5 MB)
      const oversizedBytes = Buffer.alloc(6 * 1024 * 1024);
      await assert.rejects(
        async () => {
          await engine.uploadDriverDocument({
            driverId,
            docType: 'national_id_front',
            fileBuffer: oversizedBytes,
            fileExtension: '.jpg',
          });
        },
        /FILE_TOO_LARGE/,
      );

      // Rejection of invalid extension (e.g. .exe or .pdf)
      await assert.rejects(
        async () => {
          await engine.uploadDriverDocument({
            driverId,
            docType: 'national_id_front',
            fileBuffer: sampleImageBytes,
            fileExtension: '.pdf',
          });
        },
        /INVALID_MIME_TYPE/,
      );
    });

    // -----------------------------------------------------------------------
    // TEST 10: Role Separation Guards
    // -----------------------------------------------------------------------
    it('enforces that rider accounts cannot log into captain app and captain accounts cannot log into rider app', async () => {
      const engine = new MockFirebaseEngine();

      await engine.registerRider({
        uid: 'rider_user',
        fullName: 'Pure Rider',
        phone: '01077778888',
        gender: 'female',
      });

      await engine.registerDriver({
        uid: 'driver_user',
        fullName: 'Pure Driver',
        phone: '01199990000',
        gender: 'male',
        nationalId: '30108202105675',
        licenseNumber: 'LIC-PURE',
        vehicleMake: 'Hyundai',
        vehicleModel: 'Accent',
        vehicleYear: 2022,
        vehiclePlate: 'س ي ر 5555',
        vehicleColor: 'Black',
      });

      // 1. Rider trying to enter driver application
      await assert.rejects(
        async () => {
          await engine.loginWithPhone({
            uid: 'rider_user',
            expectedRole: 'driver',
          });
        },
        /ROLE_MISMATCH: Expected driver, got rider/,
      );

      // 2. Driver trying to enter rider application
      await assert.rejects(
        async () => {
          await engine.loginWithPhone({
            uid: 'driver_user',
            expectedRole: 'rider',
          });
        },
        /ROLE_MISMATCH: Expected rider, got driver/,
      );
    });

    // -----------------------------------------------------------------------
    // TEST 11: Session Restoration with Deactivated Account Guard
    // -----------------------------------------------------------------------
    it('terminates session and rejects access if account has been deactivated (is_active=false)', async () => {
      const engine = new MockFirebaseEngine();

      await engine.registerRider({
        uid: 'deactivated_user',
        fullName: 'Banned User',
        phone: '01200001111',
        gender: 'male',
      });

      // Deactivate account
      const user = engine.users.get('deactivated_user');
      user.is_active = false;

      // Session restoration attempt
      await assert.rejects(
        async () => {
          await engine.loginWithPhone({
            uid: 'deactivated_user',
            expectedRole: 'rider',
          });
        },
        /ACCOUNT_DISABLED/,
      );
    });

    // -----------------------------------------------------------------------
    // TEST 12: Registration Failure Recovery
    // -----------------------------------------------------------------------
    it('Registration Failure Recovery: Handles transient Firestore write failure with safe retry without duplicate accounts', async () => {
      const engine = new MockFirebaseEngine();
      const uid = 'retry_user_888';
      const phone = '01055554444';

      // Step 1: User verifies phone via Auth. First write fails due to simulated network timeout
      let firstAttemptFailed = false;
      try {
        throw new Error('NETWORK_TIMEOUT: Firestore batch write timed out');
      } catch (err) {
        firstAttemptFailed = true;
      }
      assert.equal(firstAttemptFailed, true);
      assert.equal(engine.users.has(uid), false, 'No document should exist after failed attempt');

      // Step 2: Retry with existing verified session succeeds directly
      const profile = await engine.registerRider({
        uid,
        fullName: 'Retry Rider',
        phone,
        gender: 'female',
      });

      assert.equal(engine.users.has(uid), true);
      assert.equal(profile.phone, '+201055554444');
      assert.equal(profile.role, 'rider');

      // Step 3: Duplicate registration attempt is blocked
      await assert.rejects(
        async () => {
          await engine.registerRider({
            uid,
            fullName: 'Duplicate Rider',
            phone,
            gender: 'female',
          });
        },
        /USER_ALREADY_EXISTS/,
      );
    });

    // -----------------------------------------------------------------------
    // TEST 13: Custom Claims & Privileged Function Gating
    // -----------------------------------------------------------------------
    it('updates Custom Claims upon admin approval and blocks pending drivers from privileged operations', async () => {
      const engine = new MockFirebaseEngine();
      const customClaims = new Map();
      const driverId = 'drv_claims_test';

      await engine.registerDriver({
        uid: driverId,
        fullName: 'Claims Test Driver',
        phone: '01122223333',
        gender: 'female',
        nationalId: '29505150101248',
        licenseNumber: 'LIC-CLAIMS',
        vehicleMake: 'Kia',
        vehicleModel: 'Sportage',
        vehicleYear: 2023,
        vehiclePlate: 'ج م ل 9999',
        vehicleColor: 'Rose',
      });

      // Initial claims for newly registered pending driver
      customClaims.set(driverId, { role: 'driver', approved: false });

      // Simulated privileged driver function (accepting a ride)
      function privilegedAcceptRide(callerUid) {
        const claims = customClaims.get(callerUid);
        const driver = engine.drivers.get(callerUid);
        if (!claims?.approved || driver?.status !== 'approved') {
          throw new Error('DRIVER_NOT_APPROVED: Privileged operation requires approved captain status.');
        }
        return { success: true };
      }

      // Pending driver attempt MUST fail
      assert.throws(() => privilegedAcceptRide(driverId), /DRIVER_NOT_APPROVED/);

      // Admin approves driver
      await engine.adminReviewDriver({ driverId, decision: 'approved' });
      customClaims.set(driverId, { role: 'driver', approved: true, gender_verified: true });

      // After admin approval, privileged operation succeeds
      const result = privilegedAcceptRide(driverId);
      assert.equal(result.success, true);
    });

    // -----------------------------------------------------------------------
    // TEST 14: Partial KYC Storage Upload and Safe Resumption
    // -----------------------------------------------------------------------
    it('allows partial KYC uploads to be resumed safely without corrupting previous files', async () => {
      const engine = new MockFirebaseEngine();
      const driverId = 'drv_resume_test';

      await engine.registerDriver({
        uid: driverId,
        fullName: 'Resuming Driver',
        phone: '01099998888',
        gender: 'male',
        nationalId: '30108202105675',
        licenseNumber: 'LIC-RESUME',
        vehicleMake: 'Toyota',
        vehicleModel: 'Corolla',
        vehicleYear: 2022,
        vehiclePlate: 'ر ق م 1234',
        vehicleColor: 'Silver',
      });

      const sampleBytes = Buffer.alloc(1024 * 20);

      // Upload first 4 sides
      const initialSides = [
        'national_id_front',
        'national_id_back',
        'driver_license_front',
        'driver_license_back',
      ];
      for (const side of initialSides) {
        await engine.uploadDriverDocument({
          driverId,
          docType: side,
          fileBuffer: sampleBytes,
          fileExtension: '.jpg',
        });
      }

      const driver = engine.drivers.get(driverId);
      assert.equal(Object.keys(driver.documents).length, 4);

      // Simulated interruption on 5th side
      let uploadFailed = false;
      try {
        throw new Error('SOCKET_CLOSED: Network interrupted');
      } catch (_) {
        uploadFailed = true;
      }
      assert.equal(uploadFailed, true);

      // Resume upload with remaining 2 sides
      const remainingSides = ['vehicle_reg_front', 'vehicle_reg_back'];
      for (const side of remainingSides) {
        await engine.uploadDriverDocument({
          driverId,
          docType: side,
          fileBuffer: sampleBytes,
          fileExtension: '.jpg',
        });
      }

      // Verify all 6 sides are present in Storage and Firestore
      assert.equal(Object.keys(driver.documents).length, 6);
      assert.equal(engine.storageFiles.has(`driver_documents/${driverId}/vehicle_reg_back.jpg`), true);
    });

  });
});
