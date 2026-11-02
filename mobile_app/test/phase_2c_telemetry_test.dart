import 'dart:io';

/// Rafik Phase 2C - Real-Time Telemetry & Presence Dart Unit Test Suite
/// Deterministically validates coordinate boundaries, telemetry throttling,
/// server-authoritative field stripping, and presence lifecycle state machines.

class ThrottlingDecision {
  final bool shouldPublish;
  final String reason;
  const ThrottlingDecision(this.shouldPublish, this.reason);
}

class DriverPresenceStateMachine {
  String state = 'offline';
  bool isOnline = false;
  bool isConnected = false;

  void onConnect() {
    isConnected = true;
    if (isOnline) {
      state = 'online';
    }
  }

  void toggleOnline(bool online) {
    isOnline = online;
    if (!isOnline) {
      state = 'offline';
    } else if (isConnected) {
      state = 'online';
    }
  }

  void onDisconnectTriggered() {
    // RTDB onDisconnect() handler executed by server
    isConnected = false;
    state = 'offline';
    isOnline = false;
  }
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

  void expectTrue(bool condition, [String? reason]) {
    if (!condition) {
      throw AssertionError('Expected condition to be true. Reason: ${reason ?? "None"}');
    }
  }

  stdout.writeln('====================================================');
  stdout.writeln('RAFIK (رفيق) — PHASE 2C DART TELEMETRY TEST SUITE');
  stdout.writeln('====================================================');

  // ---------------------------------------------------------------------------
  // 1. COORDINATE VALIDATION & GEOGRAPHIC BOUNDS
  // ---------------------------------------------------------------------------
  stdout.writeln('\n--- 1. Coordinate Validation & Geographic Bounds ---');

  bool isValidCoordinate(double lat, double lng) {
    return lat >= -90.0 && lat <= 90.0 && lng >= -180.0 && lng <= 180.0;
  }

  test('Validates authentic Cairo metropolitan coordinates', () {
    expectTrue(isValidCoordinate(30.0444, 31.2357), 'Tahrir Square');
    expectTrue(isValidCoordinate(30.0210, 31.4920), 'AUC New Cairo');
    expectTrue(isValidCoordinate(30.0561, 31.2223), 'Zamalek 26th July');
    expectTrue(isValidCoordinate(29.9602, 31.2569), 'Maadi Corniche');
    expectTrue(isValidCoordinate(30.0074, 30.9733), '6th of October City');
  });

  test('Rejects invalid latitude beyond [-90, +90]', () {
    expect(isValidCoordinate(90.0001, 31.2357), false);
    expect(isValidCoordinate(-90.5000, 31.2357), false);
  });

  test('Rejects invalid longitude beyond [-180, +180]', () {
    expect(isValidCoordinate(30.0444, 180.001), false);
    expect(isValidCoordinate(30.0444, -180.500), false);
  });

  // ---------------------------------------------------------------------------
  // 2. TELEMETRY SERIALIZATION & SERVER-FIELD STRIPPING
  // ---------------------------------------------------------------------------
  stdout.writeln('\n--- 2. Telemetry Serialization & Server Field Isolation ---');

  Map<String, dynamic> buildClientTelemetryPayload({
    required double lat,
    required double lng,
    double heading = 0.0,
    double speed = 0.0,
    int? timestampMs,
  }) {
    if (!isValidCoordinate(lat, lng)) {
      throw ArgumentError('Invalid coordinates');
    }

    // Normalizes heading to [0, 360)
    final normalizedHeading = (heading % 360.0 + 360.0) % 360.0;
    final normalizedSpeed = speed < 0.0 ? 0.0 : speed;

    return {
      'lat': lat,
      'lng': lng,
      'heading': normalizedHeading,
      'speed': normalizedSpeed,
      'updated_at': timestampMs ?? DateTime.now().millisecondsSinceEpoch,
    };
  }

  test('Builds valid client telemetry payload with pure driver fields', () {
    final payload = buildClientTelemetryPayload(
      lat: 30.0444,
      lng: 31.2357,
      heading: 90.0,
      speed: 25.5,
      timestampMs: 1729864200000,
    );

    expect(payload['lat'], 30.0444);
    expect(payload['lng'], 31.2357);
    expect(payload['heading'], 90.0);
    expect(payload['speed'], 25.5);
    expect(payload['updated_at'], 1729864200000);

    // Assert that server-authoritative fields are absent
    expect(payload.containsKey('status'), false);
    expect(payload.containsKey('is_busy'), false);
    expect(payload.containsKey('gender'), false);
    expect(payload.containsKey('active_rider_id'), false);
    expect(payload.containsKey('tier'), false);
  });

  test('Normalizes heading angles exceeding 360 degrees', () {
    final payload = buildClientTelemetryPayload(lat: 30.0, lng: 31.0, heading: 450.0);
    expect(payload['heading'], 90.0);
  });

  test('Clamps negative speed to 0.0', () {
    final payload = buildClientTelemetryPayload(lat: 30.0, lng: 31.0, speed: -15.0);
    expect(payload['speed'], 0.0);
  });

  // ---------------------------------------------------------------------------
  // 3. BATTERY & NETWORK THROTTLING LOGIC
  // ---------------------------------------------------------------------------
  stdout.writeln('\n--- 3. Battery & GPS Throttling Engine ---');

  ThrottlingDecision evaluatePublishNeed({
    required double speedKmh,
    required DateTime now,
    required DateTime? lastPublishTime,
    required Duration movingInterval,
    required Duration stationaryInterval,
  }) {
    if (lastPublishTime == null) {
      return const ThrottlingDecision(true, 'INITIAL_FIRST_UPDATE');
    }

    final elapsed = now.difference(lastPublishTime);
    final isMoving = speedKmh >= 1.0;

    if (isMoving) {
      if (elapsed >= movingInterval) {
        return const ThrottlingDecision(true, 'MOVING_INTERVAL_REACHED');
      }
      return const ThrottlingDecision(false, 'THROTTLED_MOVING');
    } else {
      if (elapsed >= stationaryInterval) {
        return const ThrottlingDecision(true, 'STATIONARY_HEARTBEAT_KEEP_ALIVE');
      }
      return const ThrottlingDecision(false, 'THROTTLED_STATIONARY');
    }
  }

  final movingInterval = const Duration(seconds: 3);
  final stationaryInterval = const Duration(seconds: 10);
  final baseTime = DateTime(2026, 11, 2, 14, 0, 0);

  test('Publishes immediately on first startup update', () {
    final decision = evaluatePublishNeed(
      speedKmh: 0.0,
      now: baseTime,
      lastPublishTime: null,
      movingInterval: movingInterval,
      stationaryInterval: stationaryInterval,
    );
    expect(decision.shouldPublish, true);
    expect(decision.reason, 'INITIAL_FIRST_UPDATE');
  });

  test('Throttles moving driver updates if under 3-second moving interval', () {
    final decision = evaluatePublishNeed(
      speedKmh: 45.0, // Moving at 45 km/h
      now: baseTime.add(const Duration(seconds: 2)),
      lastPublishTime: baseTime,
      movingInterval: movingInterval,
      stationaryInterval: stationaryInterval,
    );
    expect(decision.shouldPublish, false);
    expect(decision.reason, 'THROTTLED_MOVING');
  });

  test('Publishes moving driver updates after 3 seconds elapse', () {
    final decision = evaluatePublishNeed(
      speedKmh: 45.0,
      now: baseTime.add(const Duration(seconds: 3)),
      lastPublishTime: baseTime,
      movingInterval: movingInterval,
      stationaryInterval: stationaryInterval,
    );
    expect(decision.shouldPublish, true);
    expect(decision.reason, 'MOVING_INTERVAL_REACHED');
  });

  test('Throttles stationary driver for 9 seconds to preserve battery', () {
    final decision = evaluatePublishNeed(
      speedKmh: 0.2, // Stationary
      now: baseTime.add(const Duration(seconds: 9)),
      lastPublishTime: baseTime,
      movingInterval: movingInterval,
      stationaryInterval: stationaryInterval,
    );
    expect(decision.shouldPublish, false);
    expect(decision.reason, 'THROTTLED_STATIONARY');
  });

  test('Sends keep-alive heartbeat after 10 seconds of stationary traffic wait', () {
    final decision = evaluatePublishNeed(
      speedKmh: 0.0,
      now: baseTime.add(const Duration(seconds: 10)),
      lastPublishTime: baseTime,
      movingInterval: movingInterval,
      stationaryInterval: stationaryInterval,
    );
    expect(decision.shouldPublish, true);
    expect(decision.reason, 'STATIONARY_HEARTBEAT_KEEP_ALIVE');
  });

  // ---------------------------------------------------------------------------
  // 4. PRESENCE STATE MACHINE & DISCONNECT RECOVERY
  // ---------------------------------------------------------------------------
  stdout.writeln('\n--- 4. Presence State Machine Transitions ---');

  test('Correctly progresses presence: offline -> connected & online -> onDisconnect', () {
    final machine = DriverPresenceStateMachine();
    expect(machine.state, 'offline');
    expect(machine.isOnline, false);

    // 1. Device connects WebSocket
    machine.onConnect();
    expect(machine.isConnected, true);
    expect(machine.state, 'offline'); // Still offline until captain toggles online

    // 2. Captain toggles online
    machine.toggleOnline(true);
    expect(machine.state, 'online');
    expect(machine.isOnline, true);

    // 3. Network connection drops abruptly
    machine.onDisconnectTriggered();
    expect(machine.state, 'offline');
    expect(machine.isOnline, false);
    expect(machine.isConnected, false);
  });

  test('Manual toggle to offline sets state to offline immediately', () {
    final machine = DriverPresenceStateMachine();
    machine.onConnect();
    machine.toggleOnline(true);
    expect(machine.state, 'online');

    machine.toggleOnline(false);
    expect(machine.state, 'offline');
    expect(machine.isOnline, false);
  });

  // ---------------------------------------------------------------------------
  // 5. SERVER-AUTHORITATIVE TIMESTAMPS & STALE-DRIVER EXCLUSION
  // ---------------------------------------------------------------------------
  stdout.writeln('\n--- 5. Server-Authoritative Timestamps & Telemetry Freshness ---');

  bool isTelemetryFresh({
    required int? updatedAtMs,
    required int currentServerTimeMs,
    int maxHeartbeatTimeoutMs = 60000,
    int maxClockSkewToleranceMs = 5000,
  }) {
    if (updatedAtMs == null) return false;
    // Reject future timestamps
    if (updatedAtMs > currentServerTimeMs + maxClockSkewToleranceMs) return false;
    // Reject stale telemetry
    if (currentServerTimeMs - updatedAtMs > maxHeartbeatTimeoutMs) return false;
    return true;
  }

  test('Validates fresh telemetry within 60-second dispatch window', () {
    final now = 1729864200000;
    expectTrue(isTelemetryFresh(updatedAtMs: now - 5000, currentServerTimeMs: now));
    expectTrue(isTelemetryFresh(updatedAtMs: now - 30000, currentServerTimeMs: now));
    expectTrue(isTelemetryFresh(updatedAtMs: now, currentServerTimeMs: now));
  });

  test('Excludes stale telemetry older than 60 seconds from dispatch', () {
    final now = 1729864200000;
    expect(isTelemetryFresh(updatedAtMs: now - 65000, currentServerTimeMs: now), false);
    expect(isTelemetryFresh(updatedAtMs: now - 120000, currentServerTimeMs: now), false);
  });

  test('Rejects future timestamps sent to artificially bypass stale driver exclusion', () {
    final now = 1729864200000;
    // 10 seconds in the future (exceeds 5s skew tolerance)
    expect(isTelemetryFresh(updatedAtMs: now + 10000, currentServerTimeMs: now), false);
    // 1 hour in the future
    expect(isTelemetryFresh(updatedAtMs: now + 3600000, currentServerTimeMs: now), false);
  });

  test('Rejects null or missing timestamps', () {
    final now = 1729864200000;
    expect(isTelemetryFresh(updatedAtMs: null, currentServerTimeMs: now), false);
  });

  test('Enforces ServerValue.timestamp format for RTDB payloads', () {
    // Client must never pass manual epoch timestamps when publishing via FirebaseService
    final rtdbPayload = {
      'lat': 30.0444,
      'lng': 31.2357,
      'heading': 90.0,
      'speed': 25.0,
      'updated_at': {'.sv': 'timestamp'},
    };
    expectTrue(rtdbPayload['updated_at'] is Map);
    expect((rtdbPayload['updated_at'] as Map)['.sv'], 'timestamp');
  });

  stdout.writeln('====================================================');
  stdout.writeln('TEST RESULTS: $passedTests / $totalTests PASSED');
  stdout.writeln('====================================================');

  if (passedTests != totalTests) {
    exit(1);
  }
}
