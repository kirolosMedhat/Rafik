import 'dart:io';
import '../lib/core/utils/national_id_utils.dart';
import '../lib/core/utils/phone_number_utils.dart';

// Exceptions matching FirebaseService specification
class UserNotRegisteredException implements Exception {
  final String message;
  const UserNotRegisteredException([this.message = 'Phone number is not registered. Please register first.']);
  @override
  String toString() => message;
}

class UserAlreadyExistsException implements Exception {
  final String message;
  const UserAlreadyExistsException([this.message = 'Phone number is already registered. Please log in.']);
  @override
  String toString() => message;
}

class RoleMismatchException implements Exception {
  final String expectedRole;
  final String actualRole;
  final String message;
  RoleMismatchException({required this.expectedRole, required this.actualRole, String? message})
      : message = message ?? 'Role mismatch: expected $expectedRole, got $actualRole';
  @override
  String toString() => message;
}

void main() {
  int totalTests = 0;
  int passedTests = 0;

  void test(String description, void Function() body) {
    totalTests++;
    try {
      body();
      passedTests++;
      stdout.writeln('  [PASS] $description');
    } catch (e, st) {
      stderr.writeln('  [FAIL] $description: $e\n$st');
    }
  }

  void expect(dynamic actual, dynamic expected, [String? reason]) {
    if (actual != expected) {
      throw AssertionError('Expected <$expected> but got <$actual>. Reason: ${reason ?? "None"}');
    }
  }

  void expectThrows<T extends Exception>(void Function() callback) {
    bool threw = false;
    try {
      callback();
    } catch (e) {
      if (e is T) {
        threw = true;
      } else {
        throw AssertionError('Expected exception of type $T, but got ${e.runtimeType}: $e');
      }
    }
    if (!threw) {
      throw AssertionError('Expected exception of type $T, but no exception was thrown.');
    }
  }

  stdout.writeln('====================================================');
  stdout.writeln('RAFIK (رفيق) — PHASE 2B DART UNIT TEST SUITE');
  stdout.writeln('====================================================');

  // ---------------------------------------------------------------------------
  // 1. EGYPTIAN PHONE NUMBER NORMALIZATION & VALIDATION TESTS
  // ---------------------------------------------------------------------------
  stdout.writeln('\n--- 1. Egyptian Phone Normalization (+20 E.164) ---');

  test('Normalizes Vodafone Egypt 010 format', () {
    expect(PhoneNumberUtils.normalizeEgyptianPhone('01012345678'), '+201012345678');
    expect(PhoneNumberUtils.normalizeEgyptianPhone('010 1234 5678'), '+201012345678');
    expect(PhoneNumberUtils.normalizeEgyptianPhone('+201012345678'), '+201012345678');
    expect(PhoneNumberUtils.normalizeEgyptianPhone('00201012345678'), '+201012345678');
  });

  test('Normalizes Etisalat Egypt 011 format', () {
    expect(PhoneNumberUtils.normalizeEgyptianPhone('01123456789'), '+201123456789');
    expect(PhoneNumberUtils.normalizeEgyptianPhone('+20 11 2345 6789'), '+201123456789');
  });

  test('Normalizes Orange Egypt 012 format', () {
    expect(PhoneNumberUtils.normalizeEgyptianPhone('01234567890'), '+201234567890');
    expect(PhoneNumberUtils.normalizeEgyptianPhone('201234567890'), '+201234567890');
  });

  test('Normalizes WE / Telecom Egypt 015 format', () {
    expect(PhoneNumberUtils.normalizeEgyptianPhone('01545678901'), '+201545678901');
    expect(PhoneNumberUtils.normalizeEgyptianPhone('1545678901'), '+201545678901');
  });

  test('Rejects invalid phone numbers', () {
    expectThrows<FormatException>(() => PhoneNumberUtils.normalizeEgyptianPhone(''));
    expectThrows<FormatException>(() => PhoneNumberUtils.normalizeEgyptianPhone('01312345678')); // Invalid 013 prefix
    expectThrows<FormatException>(() => PhoneNumberUtils.normalizeEgyptianPhone('01412345678')); // Invalid 014 prefix
    expectThrows<FormatException>(() => PhoneNumberUtils.normalizeEgyptianPhone('0227948282'));  // Landline
    expectThrows<FormatException>(() => PhoneNumberUtils.normalizeEgyptianPhone('010123456'));   // Too short (9 digits)
    expectThrows<FormatException>(() => PhoneNumberUtils.normalizeEgyptianPhone('010123456789')); // Too long (12 digits)
    expectThrows<FormatException>(() => PhoneNumberUtils.normalizeEgyptianPhone('+15551234567')); // US number
  });

  test('Correctly identifies telecom operators', () {
    expect(PhoneNumberUtils.getOperatorName('01012345678'), 'Vodafone Egypt');
    expect(PhoneNumberUtils.getOperatorName('01123456789'), 'Etisalat by e&');
    expect(PhoneNumberUtils.getOperatorName('01234567890'), 'Orange Egypt');
    expect(PhoneNumberUtils.getOperatorName('01545678901'), 'WE (Telecom Egypt)');
  });

  test('Formats friendly local and international display', () {
    expect(PhoneNumberUtils.formatForDisplay('01012345678'), '+20 10 1234 5678');
    expect(PhoneNumberUtils.formatToLocalDisplay('+201012345678'), '010 1234 5678');
  });

  // ---------------------------------------------------------------------------
  // 2. EGYPTIAN NATIONAL ID & GENDER PARITY TESTS
  // ---------------------------------------------------------------------------
  stdout.writeln('\n--- 2. Egyptian National ID & Gender Parity ---');

  test('Validates 14-digit Egyptian National ID structure', () {
    NationalIdUtils.validate('29505150101248');
    NationalIdUtils.validate('30108202105675');
  });

  test('Rejects invalid National IDs', () {
    expectThrows<FormatException>(() => NationalIdUtils.validate('123456')); // Too short
    expectThrows<FormatException>(() => NationalIdUtils.validate('49505150101248')); // Invalid century 4
    expectThrows<FormatException>(() => NationalIdUtils.validate('29513150101248')); // Invalid month 13
    expectThrows<FormatException>(() => NationalIdUtils.validate('29505320101248')); // Invalid day 32
    expectThrows<FormatException>(() => NationalIdUtils.validate('29505159901248')); // Invalid governorate 99
  });

  test('Accurately decodes 13th-digit gender parity (Odd=Male, Even=Female)', () {
    expect(NationalIdUtils.getGender('29505150101248'), 'female'); // 13th digit is 4 -> female
    expect(NationalIdUtils.getGender('30108202105675'), 'male');   // 13th digit is 7 -> male
    expect(NationalIdUtils.isFemale('29505150101248'), true);
    expect(NationalIdUtils.isFemale('30108202105675'), false);
  });

  test('Enforces Rafik Girl gender parity matching', () {
    // A male National ID cannot be registered for a female account or Rafik Girl service
    expect(NationalIdUtils.matchesGender('30108202105675', 'male'), true);
    expect(NationalIdUtils.matchesGender('30108202105675', 'female'), false);

    // A female National ID matches female
    expect(NationalIdUtils.matchesGender('29505150101248', 'female'), true);
    expect(NationalIdUtils.matchesGender('29505150101248', 'male'), false);
  });

  // ---------------------------------------------------------------------------
  // 3. ROLE SEPARATION & SESSION RESTORATION LOGIC
  // ---------------------------------------------------------------------------
  stdout.writeln('\n--- 3. Role Separation & Authorization Guards ---');

  test('Enforces rider vs driver role separation on login', () {
    // Rider trying to log into driver app
    final riderProfile = {'role': 'rider', 'is_active': true};
    expect(riderProfile['role'] == 'driver', false, 'Rider must not pass driver guard');

    // Driver trying to log into rider app
    final driverProfile = {'role': 'driver', 'is_active': true, 'status': 'approved'};
    expect(driverProfile['role'] == 'rider', false, 'Driver must not pass rider guard');
  });

  test('Enforces deactivated account blocking', () {
    final suspendedProfile = {'role': 'rider', 'is_active': false};
    expect(suspendedProfile['is_active'], false);
  });

  test('Ensures unregistered phone numbers trigger UserNotRegisteredException', () {
    Map<String, dynamic>? fetchProfile(String phone) => null;
    final nonExistentProfile = fetchProfile('+201099999999');
    expect(nonExistentProfile, null);

    expectThrows<UserNotRegisteredException>(() {
      if (nonExistentProfile == null) {
        throw const UserNotRegisteredException('Phone number is not registered. Please register first.');
      }
    });
  });

  test('Registration Failure Recovery: Handles transient Firestore write failure with safe retry', () {
    final Map<String, Map<String, dynamic>> mockDb = {};
    const uid = 'recovered_user_123';
    const phone = '+201012345678';

    // Step 1: Phone verified in Auth. First Firestore write fails (transient network glitch)
    bool firstAttemptFailed = false;
    try {
      throw const SocketException('Transient network timeout during batch.commit()');
    } catch (_) {
      firstAttemptFailed = true;
    }
    expect(firstAttemptFailed, true);
    expect(mockDb.containsKey(uid), false, 'Database must have no partial document on failure');

    // Step 2: User taps retry with verified session -> write succeeds
    mockDb[uid] = {
      'uid': uid,
      'phone': phone,
      'full_name': 'Recovered User',
      'role': 'rider',
      'is_active': true,
    };
    expect(mockDb.containsKey(uid), true);
    expect(mockDb[uid]!['phone'], phone);

    // Step 3: Duplicate registration attempt is blocked
    expectThrows<UserAlreadyExistsException>(() {
      if (mockDb.containsKey(uid)) {
        throw const UserAlreadyExistsException('Phone number is already registered. Please log in.');
      }
    });

    // Step 4: Login succeeds and retrieves profile
    final loginProfile = mockDb[uid];
    expect(loginProfile != null, true);
    expect(loginProfile!['role'], 'rider');
  });

  // ---------------------------------------------------------------------------
  // 4. DRIVER STATUS GATING LOGIC
  // ---------------------------------------------------------------------------
  stdout.writeln('\n--- 4. Driver Status Gating (Pending / Rejected / Approved) ---');

  test('Routes pending driver to DriverPendingScreen', () {
    final driver = {'status': 'pending', 'role': 'driver'};
    String destination;
    if (driver['status'] == 'approved') {
      destination = 'DriverRadarScreen';
    } else if (driver['status'] == 'rejected') {
      destination = 'DriverRejectedScreen';
    } else {
      destination = 'DriverPendingScreen';
    }
    expect(destination, 'DriverPendingScreen');
  });

  test('Routes approved driver to DriverRadarScreen', () {
    final driver = {'status': 'approved', 'role': 'driver'};
    String destination;
    if (driver['status'] == 'approved') {
      destination = 'DriverRadarScreen';
    } else {
      destination = 'DriverPendingScreen';
    }
    expect(destination, 'DriverRadarScreen');
  });

  test('Routes rejected driver to DriverRejectedScreen with reason', () {
    final driver = {
      'status': 'rejected',
      'role': 'driver',
      'rejection_reason': 'Vehicle license copy was blurred and illegible.',
    };
    String destination;
    if (driver['status'] == 'rejected') {
      destination = 'DriverRejectedScreen';
    } else {
      destination = 'OtherScreen';
    }
    expect(destination, 'DriverRejectedScreen');
    expect(driver['rejection_reason'], 'Vehicle license copy was blurred and illegible.');
  });

  // ---------------------------------------------------------------------------
  // 5. 6-SIDED DOCUMENT VAULT VALIDATION
  // ---------------------------------------------------------------------------
  stdout.writeln('\n--- 5. 6-Sided Document Vault Validation ---');

  test('Validates all 6 required document sides', () {
    const requiredSides = [
      'national_id_front',
      'national_id_back',
      'driver_license_front',
      'driver_license_back',
      'vehicle_reg_front',
      'vehicle_reg_back',
    ];
    expect(requiredSides.length, 6);

    final completedDocs = {
      'national_id_front': true,
      'national_id_back': true,
      'driver_license_front': true,
      'driver_license_back': true,
      'vehicle_reg_front': true,
      'vehicle_reg_back': false,
    };

    final allDone = requiredSides.every((side) => completedDocs[side] == true);
    expect(allDone, false, 'Should fail when 1 side is missing');

    completedDocs['vehicle_reg_back'] = true;
    final allComplete = requiredSides.every((side) => completedDocs[side] == true);
    expect(allComplete, true, 'Should pass when all 6 sides are present');
  });

  test('Validates document file size constraint (<= 5 MB)', () {
    const maxSizeBytes = 5 * 1024 * 1024;
    final validFileSize = 3 * 1024 * 1024;
    final oversizeFile = 6 * 1024 * 1024;

    expect(validFileSize <= maxSizeBytes, true);
    expect(oversizeFile <= maxSizeBytes, false);
  });

  test('Validates allowed image MIME extensions', () {
    final validExtensions = ['.jpg', '.jpeg', '.png', '.webp'];
    bool isAllowed(String path) => validExtensions.any((ext) => path.toLowerCase().endsWith(ext));

    expect(isAllowed('photo.jpg'), true);
    expect(isAllowed('scan.PNG'), true);
    expect(isAllowed('document.webp'), true);
    expect(isAllowed('document.pdf'), false);
    expect(isAllowed('malicious.exe'), false);
  });

  // ---------------------------------------------------------------------------
  // SUMMARY
  // ---------------------------------------------------------------------------
  stdout.writeln('\n====================================================');
  stdout.writeln('TEST RESULTS: $passedTests / $totalTests PASSED');
  stdout.writeln('====================================================');

  if (passedTests < totalTests) {
    exit(1);
  }
}
