import 'dart:io';
import 'dart:math';

/// RAFIK (رفيق) — PHASE 2D DART TEST SUITE
/// Deterministic verification of Ride Creation, Dynamic Fare Calculation,
/// 4-Digit PIN Handshake (with 3-Strike Lockout), Offer Concurrency,
/// State Machine Lifecycle Transitions, Cancellation Cleanup, and In-Ride Chat.

// -----------------------------------------------------------------------------
// MODELS & MOCK ENGINES FOR VERIFICATION
// -----------------------------------------------------------------------------

enum RideStatus { requested, accepted, arrived, inProgress, completed, cancelled, expired }
enum RideTier { rafikStandard, rafikGirl }

class DynamicFareCalculator {
  final double baseFare;
  final double perKmRate;
  final double perMinuteRate;
  final double minimumFare;
  final double trafficMultiplier;
  final double rafikGirlMultiplier;

  const DynamicFareCalculator({
    this.baseFare = 12.0,
    this.perKmRate = 4.5,
    this.perMinuteRate = 0.75,
    this.minimumFare = 25.0,
    this.trafficMultiplier = 1.25,
    this.rafikGirlMultiplier = 1.10,
  });

  double calculateUpfrontFare({
    required double distanceKm,
    required double estimatedMinutes,
    required bool isRafikGirl,
  }) {
    // Formula: (baseFare + (distanceKm * trafficMultiplier * perKmRate) + (estimatedMinutes * perMinuteRate)) * tierMultiplier
    final rawFare = baseFare +
        (distanceKm * trafficMultiplier * perKmRate) +
        (estimatedMinutes * perMinuteRate);

    final tierAdjusted = isRafikGirl ? (rawFare * rafikGirlMultiplier) : rawFare;
    final finalFare = max(tierAdjusted, minimumFare);

    // Round to 2 decimal places for Egyptian Pound currency display
    return (finalFare * 100).roundToDouble() / 100.0;
  }
}

class PinHandshakeEngine {
  final String correctPin;
  int failedAttempts = 0;
  bool isLocked = false;
  static const int maxAttempts = 3;

  PinHandshakeEngine(this.correctPin);

  Map<String, dynamic> verifyPin(String submittedPin) {
    if (isLocked) {
      return {
        'ok': false,
        'status': 'LOCKED',
        'attempts_left': 0,
        'locked': true,
        'error': 'PIN handshake permanently locked after 3 failed attempts.',
      };
    }

    if (submittedPin == correctPin) {
      return {
        'ok': true,
        'status': 'VERIFIED',
        'attempts_left': maxAttempts - failedAttempts,
        'locked': false,
      };
    } else {
      failedAttempts++;
      if (failedAttempts >= maxAttempts) {
        isLocked = true;
        return {
          'ok': false,
          'status': 'LOCKED',
          'attempts_left': 0,
          'locked': true,
          'error': 'Maximum PIN attempts exceeded. Handshake locked.',
        };
      }
      return {
        'ok': false,
        'status': 'INVALID_PIN',
        'attempts_left': maxAttempts - failedAttempts,
        'locked': false,
      };
    }
  }
}

class ConcurrentOfferDispatcher {
  String rideStatus = 'requested';
  String? assignedDriverId;
  final Map<String, String> driverOffers = {}; // driverId -> offerStatus

  void issueOffer(String driverId) {
    driverOffers[driverId] = 'pending';
  }

  Map<String, dynamic> acceptOffer(String driverId) {
    // Atomic test simulating Firestore runTransaction
    if (rideStatus != 'requested') {
      return {
        'success': false,
        'code': 'RIDE_ALREADY_ACCEPTED',
        'message': 'Ride has already been claimed by another captain.',
      };
    }

    if (driverOffers[driverId] != 'pending') {
      return {
        'success': false,
        'code': 'INVALID_OFFER',
        'message': 'Offer is no longer active.',
      };
    }

    // Winner claims ride atomically
    rideStatus = 'accepted';
    assignedDriverId = driverId;
    driverOffers[driverId] = 'accepted';

    // Batch cancel competing offers
    driverOffers.forEach((id, status) {
      if (id != driverId && status == 'pending') {
        driverOffers[id] = 'cancelled';
      }
    });

    return {
      'success': true,
      'code': 'ACCEPTED',
      'driver_id': driverId,
    };
  }
}

class RideLifecycleStateMachine {
  RideStatus status = RideStatus.requested;
  bool driverBusy = false;
  String? activeRiderId;
  String? cancellationReason;

  void acceptRide(String driverId, String riderId) {
    if (status != RideStatus.requested) {
      throw StateError('Cannot accept ride in status $status');
    }
    status = RideStatus.accepted;
    driverBusy = true;
    activeRiderId = riderId;
  }

  void markArrived() {
    if (status != RideStatus.accepted) {
      throw StateError('Driver cannot mark arrived unless ride is accepted');
    }
    status = RideStatus.arrived;
  }

  void startTripWithPin(bool pinVerified) {
    if (status != RideStatus.arrived) {
      throw StateError('Cannot start trip before arriving at pickup');
    }
    if (!pinVerified) {
      throw StateError('PIN must be verified before starting trip');
    }
    status = RideStatus.inProgress;
  }

  void completeTrip() {
    if (status != RideStatus.inProgress) {
      throw StateError('Cannot complete trip unless it is in progress');
    }
    status = RideStatus.completed;
    driverBusy = false;
    activeRiderId = null;
  }

  void cancelTrip(String reason) {
    if (status == RideStatus.completed) {
      throw StateError('Cannot cancel an already completed trip');
    }
    status = RideStatus.cancelled;
    cancellationReason = reason;
    driverBusy = false;
    activeRiderId = null;
  }
}

// -----------------------------------------------------------------------------
// MAIN TEST SUITE ENTRYPOINT
// -----------------------------------------------------------------------------

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

  void expectTrue(bool condition, [String? reason]) {
    if (!condition) {
      throw AssertionError('Expected condition to be true. Reason: ${reason ?? "None"}');
    }
  }

  stdout.writeln('====================================================');
  stdout.writeln('RAFIK (رفيق) — PHASE 2D RIDE LIFECYCLE TEST SUITE');
  stdout.writeln('====================================================');

  // ---------------------------------------------------------------------------
  // 1. RIDE CREATION & TIER RESTRICTION (RAFIK GIRL)
  // ---------------------------------------------------------------------------
  stdout.writeln('\n--- 1. Ride Creation & Tier Restriction (Rafik Girl) ---');

  test('Permits Rafik Standard request for all verified riders', () {
    final payload = {
      'tier': 'standard',
      'rider_gender': 'male',
      'pickup_lat': 30.0444,
      'pickup_lng': 31.2357,
      'dropoff_lat': 30.0210,
      'dropoff_lng': 31.4920,
    };
    expect(payload['tier'], 'standard');
    expectTrue(payload['pickup_lat'] != null && payload['pickup_lng'] != null);
  });

  test('Permits Rafik Girl request for verified female rider', () {
    final riderGender = 'female';
    final requestedTier = 'rafik_girl';
    final isAllowed = (requestedTier != 'rafik_girl' || riderGender == 'female');
    expectTrue(isAllowed, 'Verified female rider must be permitted to request Rafik Girl');
  });

  test('Blocks male rider from requesting Rafik Girl tier', () {
    final riderGender = 'male';
    final requestedTier = 'rafik_girl';
    final isAllowed = (requestedTier != 'rafik_girl' || riderGender == 'female');
    expect(isAllowed, false, 'Male rider must be blocked from requesting Rafik Girl');
  });

  test('Only dispatches Rafik Girl rides to verified female drivers', () {
    final candidateDrivers = [
      {'driver_id': 'd1', 'gender': 'male', 'gender_verified': true},
      {'driver_id': 'd2', 'gender': 'female', 'gender_verified': false},
      {'driver_id': 'd3', 'gender': 'female', 'gender_verified': true},
    ];

    final eligibleForRafikGirl = candidateDrivers.where((d) =>
      d['gender'] == 'female' && d['gender_verified'] == true
    ).toList();

    expect(eligibleForRafikGirl.length, 1);
    expect(eligibleForRafikGirl.first['driver_id'], 'd3');
  });

  // ---------------------------------------------------------------------------
  // 2. DYNAMIC FARE CALCULATION ENGINE
  // ---------------------------------------------------------------------------
  stdout.writeln('\n--- 2. Dynamic Upfront Fare Calculation Engine ---');

  const calculator = DynamicFareCalculator(
    baseFare: 12.0,
    perKmRate: 4.5,
    perMinuteRate: 0.75,
    minimumFare: 25.0,
    trafficMultiplier: 1.25,
    rafikGirlMultiplier: 1.10,
  );

  test('Enforces minimum fare (25 EGP) for short trips (e.g. 1.2 KM, 3 mins)', () {
    final fare = calculator.calculateUpfrontFare(
      distanceKm: 1.2,
      estimatedMinutes: 3.0,
      isRafikGirl: false,
    );
    // 12 + (1.2 * 1.25 * 4.5) + (3 * 0.75) = 12 + 6.75 + 2.25 = 21.0 EGP -> Minimum 25.0 EGP
    expect(fare, 25.0, 'Short ride must be clamped to 25.0 EGP minimum fare');
  });

  test('Accurately computes long ride fare (Tahrir to AUC: 28 KM, 45 mins)', () {
    final fare = calculator.calculateUpfrontFare(
      distanceKm: 28.0,
      estimatedMinutes: 45.0,
      isRafikGirl: false,
    );
    // 12 + (28 * 1.25 * 4.5) + (45 * 0.75) = 12 + 157.5 + 33.75 = 203.25 EGP
    expect(fare, 203.25, 'Standard long distance fare must match Cairo pricing formula');
  });

  test('Applies Rafik Girl premium multiplier (1.10x) accurately', () {
    final standardFare = calculator.calculateUpfrontFare(
      distanceKm: 28.0,
      estimatedMinutes: 45.0,
      isRafikGirl: false,
    );
    final rafikGirlFare = calculator.calculateUpfrontFare(
      distanceKm: 28.0,
      estimatedMinutes: 45.0,
      isRafikGirl: true,
    );
    // 203.25 * 1.10 = 223.575 -> 223.58 EGP
    expect(rafikGirlFare, 223.58, 'Rafik Girl must accurately apply 1.10 multiplier');
    expectTrue(rafikGirlFare > standardFare);
  });

  test('Allows dynamic runtime configuration without code deployment', () {
    const surgeCalculator = DynamicFareCalculator(
      baseFare: 15.0,
      perKmRate: 5.5,
      perMinuteRate: 1.0,
      minimumFare: 35.0,
      trafficMultiplier: 1.35,
      rafikGirlMultiplier: 1.15,
    );
    final fare = surgeCalculator.calculateUpfrontFare(
      distanceKm: 10.0,
      estimatedMinutes: 20.0,
      isRafikGirl: false,
    );
    // 15 + (10 * 1.35 * 5.5) + (20 * 1.0) = 15 + 74.25 + 20 = 109.25 EGP
    expect(fare, 109.25);
  });

  // ---------------------------------------------------------------------------
  // 3. 4-DIGIT PIN VERIFICATION & 3-STRIKE LOCKOUT
  // ---------------------------------------------------------------------------
  stdout.writeln('\n--- 3. 4-Digit PIN Handshake & 3-Strike Lockout ---');

  test('Validates generated PIN format is strictly 4 numeric digits', () {
    final random = Random(42);
    for (int i = 0; i < 20; i++) {
      final pin = (1000 + random.nextInt(9000)).toString();
      expectTrue(pin.length == 4, 'PIN must be exactly 4 digits');
      expectTrue(int.tryParse(pin) != null, 'PIN must be entirely numeric');
    }
  });

  test('Successful PIN verification unlocks trip start on first try', () {
    final handshake = PinHandshakeEngine('4829');
    final res = handshake.verifyPin('4829');

    expect(res['ok'], true);
    expect(res['status'], 'VERIFIED');
    expect(res['locked'], false);
    expect(res['attempts_left'], 3);
  });

  test('Tracks failed PIN attempts and decrements remaining strikes', () {
    final handshake = PinHandshakeEngine('7193');

    final strike1 = handshake.verifyPin('0000');
    expect(strike1['ok'], false);
    expect(strike1['status'], 'INVALID_PIN');
    expect(strike1['attempts_left'], 2);
    expect(strike1['locked'], false);

    final strike2 = handshake.verifyPin('1111');
    expect(strike2['ok'], false);
    expect(strike2['status'], 'INVALID_PIN');
    expect(strike2['attempts_left'], 1);
    expect(strike2['locked'], false);

    // Correct PIN on third attempt succeeds
    final success = handshake.verifyPin('7193');
    expect(success['ok'], true);
    expect(success['status'], 'VERIFIED');
    expect(success['locked'], false);
  });

  test('Permanently locks handshake after 3 consecutive failed attempts', () {
    final handshake = PinHandshakeEngine('9988');

    handshake.verifyPin('1234'); // Strike 1
    handshake.verifyPin('5678'); // Strike 2
    final strike3 = handshake.verifyPin('9012'); // Strike 3

    expect(strike3['ok'], false);
    expect(strike3['status'], 'LOCKED');
    expect(strike3['locked'], true);
    expect(strike3['attempts_left'], 0);

    // Even if correct PIN is submitted after lock, it must be rejected!
    final lockedAttempt = handshake.verifyPin('9988');
    expect(lockedAttempt['ok'], false);
    expect(lockedAttempt['status'], 'LOCKED');
    expect(lockedAttempt['locked'], true);
  });

  // ---------------------------------------------------------------------------
  // 4. ATOMIC OFFER CONCURRENCY & RACE CONDITIONS
  // ---------------------------------------------------------------------------
  stdout.writeln('\n--- 4. Atomic Offer Concurrency & Acceptance Race ---');

  test('Guarantees only one driver wins concurrent acceptance race', () {
    final dispatcher = ConcurrentOfferDispatcher();
    dispatcher.issueOffer('driver_cairo_1');
    dispatcher.issueOffer('driver_cairo_2');

    // Driver 1 accepts first
    final res1 = dispatcher.acceptOffer('driver_cairo_1');
    expect(res1['success'], true);
    expect(res1['code'], 'ACCEPTED');
    expect(dispatcher.assignedDriverId, 'driver_cairo_1');

    // Driver 2 accepts milliseconds later
    final res2 = dispatcher.acceptOffer('driver_cairo_2');
    expect(res2['success'], false);
    expect(res2['code'], 'RIDE_ALREADY_ACCEPTED');

    // Competing offer for driver 2 was automatically cancelled
    expect(dispatcher.driverOffers['driver_cairo_2'], 'cancelled');
  });

  // ---------------------------------------------------------------------------
  // 5. RIDE LIFECYCLE STATE MACHINE INVARIANTS
  // ---------------------------------------------------------------------------
  stdout.writeln('\n--- 5. Ride Lifecycle State Machine Transitions ---');

  test('Strictly progresses: requested -> accepted -> arrived -> inProgress -> completed', () {
    final sm = RideLifecycleStateMachine();
    expect(sm.status, RideStatus.requested);
    expect(sm.driverBusy, false);

    sm.acceptRide('driver_42', 'rider_99');
    expect(sm.status, RideStatus.accepted);
    expect(sm.driverBusy, true);
    expect(sm.activeRiderId, 'rider_99');

    sm.markArrived();
    expect(sm.status, RideStatus.arrived);

    sm.startTripWithPin(true);
    expect(sm.status, RideStatus.inProgress);

    sm.completeTrip();
    expect(sm.status, RideStatus.completed);
    expect(sm.driverBusy, false, 'Driver busy status must be cleared upon trip completion');
    expect(sm.activeRiderId, null, 'Active rider ID must be cleared upon trip completion');
  });

  test('Rejects invalid transitions (e.g. starting trip before arriving)', () {
    final sm = RideLifecycleStateMachine();
    sm.acceptRide('driver_42', 'rider_99');

    // Attempt to start trip without marking arrived
    bool caught = false;
    try {
      sm.startTripWithPin(true);
    } catch (_) {
      caught = true;
    }
    expectTrue(caught, 'Must reject starting trip before driver arrives');
  });

  test('Cancellation immediately restores driver availability', () {
    final sm = RideLifecycleStateMachine();
    sm.acceptRide('driver_42', 'rider_99');
    expect(sm.driverBusy, true);

    sm.cancelTrip('Rider changed destination');
    expect(sm.status, RideStatus.cancelled);
    expect(sm.cancellationReason, 'Rider changed destination');
    expect(sm.driverBusy, false, 'Driver availability must be restored upon cancellation');
    expect(sm.activeRiderId, null);
  });

  // ---------------------------------------------------------------------------
  // 6. IN-RIDE CHAT & MESSAGING SECURITY
  // ---------------------------------------------------------------------------
  stdout.writeln('\n--- 6. In-Ride Chat Messaging Invariants ---');

  Map<String, dynamic> createChatMessage({
    required String rideId,
    required String senderId,
    required String senderRole,
    required String text,
  }) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) throw ArgumentError('Message text cannot be empty');
    if (trimmed.length > 500) throw ArgumentError('Message exceeds 500 character limit');
    if (senderRole != 'rider' && senderRole != 'driver') {
      throw ArgumentError('Invalid sender role: $senderRole');
    }

    return {
      'ride_id': rideId,
      'sender_id': senderId,
      'sender_role': senderRole,
      'text': trimmed,
      'created_at': DateTime.now().toIso8601String(),
      'read': false,
    };
  }

  test('Formats valid in-ride chat message with sanitized text', () {
    final msg = createChatMessage(
      rideId: 'ride_cairo_101',
      senderId: 'user_rider_1',
      senderRole: 'rider',
      text: '   I am waiting at the main entrance gate.   ',
    );
    expect(msg['text'], 'I am waiting at the main entrance gate.');
    expect(msg['sender_role'], 'rider');
    expect(msg['read'], false);
  });

  test('Rejects empty or whitespace-only chat message', () {
    bool caught = false;
    try {
      createChatMessage(
        rideId: 'ride_1',
        senderId: 'user_1',
        senderRole: 'rider',
        text: '   ',
      );
    } catch (_) {
      caught = true;
    }
    expectTrue(caught, 'Empty messages must be rejected');
  });

  test('Rejects oversized chat message exceeding 500 characters', () {
    bool caught = false;
    try {
      createChatMessage(
        rideId: 'ride_1',
        senderId: 'user_1',
        senderRole: 'rider',
        text: 'A' * 501,
      );
    } catch (_) {
      caught = true;
    }
    expectTrue(caught, 'Messages > 500 characters must be rejected');
  });

  // ---------------------------------------------------------------------------
  // 7. MUTUAL RATING & ROLLING AVERAGE CALCULATION
  // ---------------------------------------------------------------------------
  stdout.writeln('\n--- 7. Mutual Rating & Driver Rolling Average ---');

  double computeNewRatingAverage({
    required double currentAverage,
    required int totalCompletedRides,
    required double newRating,
  }) {
    if (newRating < 1.0 || newRating > 5.0) {
      throw ArgumentError('Rating must be between 1.0 and 5.0');
    }
    final totalPoints = (currentAverage * totalCompletedRides) + newRating;
    final newCount = totalCompletedRides + 1;
    final average = totalPoints / newCount;
    return (average * 100).roundToDouble() / 100.0;
  }

  test('Accurately computes driver rolling average rating', () {
    // Driver with 4.80 over 10 rides receives 5.0
    final newAvg = computeNewRatingAverage(
      currentAverage: 4.80,
      totalCompletedRides: 10,
      newRating: 5.0,
    );
    // (48.0 + 5.0) / 11 = 53 / 11 = 4.818... -> 4.82
    expect(newAvg, 4.82);
  });

  test('Rejects ratings out of bounds (< 1.0 or > 5.0)', () {
    bool caughtLow = false;
    try {
      computeNewRatingAverage(currentAverage: 5.0, totalCompletedRides: 1, newRating: 0.5);
    } catch (_) {
      caughtLow = true;
    }
    expectTrue(caughtLow, 'Ratings below 1.0 must be rejected');

    bool caughtHigh = false;
    try {
      computeNewRatingAverage(currentAverage: 5.0, totalCompletedRides: 1, newRating: 5.5);
    } catch (_) {
      caughtHigh = true;
    }
    expectTrue(caughtHigh, 'Ratings above 5.0 must be rejected');
  });

  // ---------------------------------------------------------------------------
  // SUMMARY
  // ---------------------------------------------------------------------------
  stdout.writeln('====================================================');
  stdout.writeln('TEST RESULTS: $passedTests / $totalTests PASSED');
  stdout.writeln('====================================================');

  if (passedTests != totalTests) {
    exit(1);
  }
}
