import 'dart:async';
import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import '../../firebase_options.dart';

/// Complete, Enterprise-Grade Firebase Integration for Rafik
/// Provides Instant Real-Time Trip Dispatch, High-Performance Firestore Sync,
/// and Seamless Username/Mobile + Password Authentication.
class FirebaseService {
  static final FirebaseService _instance = FirebaseService._internal();
  factory FirebaseService() => _instance;
  FirebaseService._internal();

  FirebaseAuth? _auth;
  FirebaseFirestore? _firestore;

  bool _initialized = false;
  bool get isInitialized => _initialized;

  FirebaseAuth get auth {
    _auth ??= FirebaseAuth.instance;
    return _auth!;
  }

  FirebaseFirestore get firestore {
    _firestore ??= FirebaseFirestore.instance;
    return _firestore!;
  }

  /// Initializes Firebase with platform-specific options
  Future<void> initialize() async {
    if (_initialized) return;
    try {
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp(
          options: DefaultFirebaseOptions.currentPlatform,
        );
      }
      _auth = FirebaseAuth.instance;
      _firestore = FirebaseFirestore.instance;
      _initialized = true;
      debugPrint('[FirebaseService] Successfully initialized Firebase & Firestore.');
    } catch (e) {
      debugPrint('[FirebaseService] Init warning: $e');
      _initialized = true; // Fallback to avoid blocking UI
    }
  }

  User? get currentUser => auth.currentUser;
  Stream<User?> get authStateChanges => auth.authStateChanges();

  /// Converts any username or Egyptian mobile number into a clean, deterministic
  /// Firebase Auth email identifier (e.g. `01012345678@rafik.app` or `kiro99@rafik.app`).
  String _toAuthEmail(String identifier) {
    final clean = identifier.trim().toLowerCase();
    if (clean.contains('@')) {
      return clean;
    }
    // Remove spaces, dashes, leading +, and build internal auth email
    final sanitized = clean.replaceAll(RegExp(r'[\s\-\+\(\)]'), '');
    return '$sanitized@rafik.app';
  }

  // ===========================================================================
  // AUTHENTICATION: Direct Username/Mobile + Password (No SMS Delays)
  // ===========================================================================

  /// Signs in using either a Username or Mobile Number with Password.
  Future<UserCredential> signInWithUsernameOrMobile({
    required String identifier,
    required String password,
  }) async {
    await initialize();
    final email = _toAuthEmail(identifier);
    try {
      final credential = await auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
      return credential;
    } on FirebaseAuthException catch (e) {
      debugPrint('[Firebase Auth] Sign in failed: ${e.code} - ${e.message}');
      rethrow;
    }
  }

  /// Registers a Client (Rider / Passenger)
  Future<UserCredential> registerClient({
    required String name,
    required String phone,
    required String username,
    required String password,
    required String gender,
    bool isUperGirl = false,
  }) async {
    await initialize();
    final email = _toAuthEmail(phone.isNotEmpty ? phone : username);
    final credential = await auth.createUserWithEmailAndPassword(
      email: email,
      password: password,
    );

    final uid = credential.user!.uid;
    await credential.user?.updateDisplayName(name);

    // Save profile to Firestore
    await firestore.collection('users').doc(uid).set({
      'uid': uid,
      'full_name': name,
      'phone': phone,
      'username': username,
      'email': email,
      'gender': gender,
      'role': 'rider',
      'gender_verified': gender == 'female' && isUperGirl,
      'rating_avg': 5.0,
      'created_at': FieldValue.serverTimestamp(),
      'updated_at': FieldValue.serverTimestamp(),
    });

    return credential;
  }

  /// Registers a Captain (Driver / Partner)
  Future<UserCredential> registerCaptain({
    required String name,
    required String phone,
    required String username,
    required String password,
    required String gender,
    required String nationalId,
    required String vehiclePlate,
    required String vehicleModel,
    required int vehicleYear,
    required String vehicleColor,
    required String licenseNumber,
  }) async {
    await initialize();
    final email = _toAuthEmail(phone.isNotEmpty ? phone : username);
    final credential = await auth.createUserWithEmailAndPassword(
      email: email,
      password: password,
    );

    final uid = credential.user!.uid;
    await credential.user?.updateDisplayName(name);

    final batch = firestore.batch();

    // User document
    final userRef = firestore.collection('users').doc(uid);
    batch.set(userRef, {
      'uid': uid,
      'full_name': name,
      'phone': phone,
      'username': username,
      'email': email,
      'gender': gender,
      'role': 'driver',
      'rating_avg': 5.0,
      'created_at': FieldValue.serverTimestamp(),
    });

    // Driver document (Pending admin review)
    final driverRef = firestore.collection('drivers').doc(uid);
    batch.set(driverRef, {
      'uid': uid,
      'user_id': uid,
      'full_name': name,
      'phone': phone,
      'username': username,
      'gender': gender,
      'role': 'driver',
      'status': 'pending', // Starts in pending review
      'national_id_number': nationalId,
      'license_number': licenseNumber,
      'vehicle_make': vehicleModel.split(' ').first,
      'vehicle_model': vehicleModel,
      'vehicle_year': vehicleYear,
      'vehicle_plate': vehiclePlate,
      'vehicle_color': vehicleColor,
      'is_online': false,
      'is_busy': false,
      'total_trips': 0,
      'wallet_balance_egp': 0.0,
      'rating_avg': 5.0,
      'created_at': FieldValue.serverTimestamp(),
    });

    await batch.commit();
    return credential;
  }

  /// Fetches current user profile from Firestore
  Future<Map<String, dynamic>?> getCurrentUserProfile() async {
    final user = currentUser;
    if (user == null) return null;

    try {
      final userDoc = await firestore.collection('users').doc(user.uid).get();
      if (userDoc.exists) {
        final data = userDoc.data();
        if (data?['role'] == 'driver') {
          final driverDoc = await firestore.collection('drivers').doc(user.uid).get();
          if (driverDoc.exists) {
            return {...?data, ...?driverDoc.data()};
          }
        }
        return data;
      }
    } catch (e) {
      debugPrint('[Firebase] Profile fetch note: $e');
    }
    return null;
  }

  /// Sign out
  Future<void> signOut() async {
    await auth.signOut();
  }

  // ===========================================================================
  // REAL-TIME DISPATCH: Instant Delivery to Drivers' Accounts
  // ===========================================================================

  /// Creates a ride request in Firestore.
  /// Fires real-time snapshot events to all online driver devices INSTANTLY.
  Future<String> requestRide({
    required String pickupAddress,
    required double pickupLat,
    required double pickupLng,
    required String dropoffAddress,
    required double dropoffLat,
    required double dropoffLng,
    required double distanceKm,
    required double fareEgp,
    required String tier,
    String paymentMethod = 'cash',
  }) async {
    final user = currentUser;
    if (user == null) throw Exception('User not authenticated');

    final profile = await getCurrentUserProfile();
    final riderName = profile?['full_name'] ?? user.displayName ?? 'Rafik Passenger';
    final riderPhone = profile?['phone'] ?? '';
    final randomPin = (1000 + Random().nextInt(9000)).toString();

    final docRef = await firestore.collection('rides').add({
      'rider_id': user.uid,
      'rider_name': riderName,
      'rider_phone': riderPhone,
      'tier': tier, // 'standard' or 'rafik_girl'
      'status': 'requested',
      'pickup_address': pickupAddress,
      'pickup_lat': pickupLat,
      'pickup_lng': pickupLng,
      'dropoff_address': dropoffAddress,
      'dropoff_lat': dropoffLat,
      'dropoff_lng': dropoffLng,
      'distance_km': distanceKm,
      'fare_egp': fareEgp,
      'payment_method': paymentMethod,
      'pin': randomPin,
      'attempts': 0,
      'driver_id': null,
      'driver_name': null,
      'driver_phone': null,
      'requested_at': FieldValue.serverTimestamp(),
      'expires_at': Timestamp.fromDate(DateTime.now().add(const Duration(minutes: 2))),
    });

    debugPrint('[Firebase] Trip requested with ID: ${docRef.id} and PIN: $randomPin');
    return docRef.id;
  }

  /// Real-time stream of newly requested rides for online drivers.
  /// This listener triggers INSTANTLY on driver accounts when any ride is submitted!
  Stream<QuerySnapshot<Map<String, dynamic>>> streamAvailableRides() {
    return firestore
        .collection('rides')
        .where('status', isEqualTo: 'requested')
        .snapshots();
  }

  /// Accepts a ride atomically using a Firestore Transaction to prevent race conditions.
  Future<bool> acceptRide({
    required String rideId,
    required String driverId,
    required String driverName,
    required String driverPhone,
    required String vehiclePlate,
    required String vehicleModel,
  }) async {
    return firestore.runTransaction<bool>((transaction) async {
      final rideRef = firestore.collection('rides').doc(rideId);
      final snapshot = await transaction.get(rideRef);

      if (!snapshot.exists) return false;
      if (snapshot.get('status') != 'requested') {
        return false; // Another captain already accepted or request expired
      }

      transaction.update(rideRef, {
        'status': 'accepted',
        'driver_id': driverId,
        'driver_name': driverName,
        'driver_phone': driverPhone,
        'vehicle_plate': vehiclePlate,
        'vehicle_model': vehicleModel,
        'accepted_at': FieldValue.serverTimestamp(),
      });

      transaction.update(firestore.collection('drivers').doc(driverId), {
        'is_busy': true,
      });

      return true;
    });
  }

  /// Driver arrived at pickup location
  Future<void> markArrived(String rideId) async {
    await firestore.collection('rides').doc(rideId).update({
      'status': 'arrived',
      'arrived_at': FieldValue.serverTimestamp(),
    });
  }

  /// Driver verifies 4-digit PIN and starts trip
  Future<Map<String, dynamic>> startRide({
    required String rideId,
    required String pin,
  }) async {
    final rideRef = firestore.collection('rides').doc(rideId);
    final snapshot = await rideRef.get();

    if (!snapshot.exists) return {'ok': false, 'error': 'Trip not found'};
    final correctPin = snapshot.get('pin')?.toString() ?? '';
    final attempts = (snapshot.data()?['attempts'] as num?)?.toInt() ?? 0;

    if (attempts >= 3) {
      return {'ok': false, 'locked': true, 'error': 'Trip PIN is locked after 3 attempts'};
    }

    if (pin.trim() == correctPin.trim()) {
      await rideRef.update({
        'status': 'in_progress',
        'started_at': FieldValue.serverTimestamp(),
      });
      return {'ok': true};
    } else {
      final newAttempts = attempts + 1;
      await rideRef.update({'attempts': newAttempts});
      return {
        'ok': false,
        'attempts_left': max(0, 3 - newAttempts),
        'locked': newAttempts >= 3,
        'error': 'Incorrect PIN. ${max(0, 3 - newAttempts)} attempts remaining.',
      };
    }
  }

  /// Completes trip, updates driver wallet with 100% earnings (0% commission)
  Future<void> completeRide({
    required String rideId,
    required String driverId,
    required double fareEgp,
  }) async {
    final batch = firestore.batch();
    final rideRef = firestore.collection('rides').doc(rideId);
    batch.update(rideRef, {
      'status': 'completed',
      'completed_at': FieldValue.serverTimestamp(),
    });

    final driverRef = firestore.collection('drivers').doc(driverId);
    batch.update(driverRef, {
      'is_busy': false,
      'total_trips': FieldValue.increment(1),
      'wallet_balance_egp': FieldValue.increment(fareEgp),
    });

    final txRef = firestore.collection('wallet_transactions').doc();
    batch.set(txRef, {
      'driver_id': driverId,
      'ride_id': rideId,
      'kind': 'fare_earned',
      'amount_egp': fareEgp,
      'created_at': FieldValue.serverTimestamp(),
    });

    await batch.commit();
  }

  /// Cancels a ride
  Future<void> cancelRide({
    required String rideId,
    required String cancelledBy,
    required String reason,
  }) async {
    final rideRef = firestore.collection('rides').doc(rideId);
    final snapshot = await rideRef.get();
    final driverId = snapshot.data()?['driver_id'] as String?;

    final batch = firestore.batch();
    batch.update(rideRef, {
      'status': 'cancelled',
      'cancelled_by': cancelledBy,
      'cancellation_reason': reason,
      'cancelled_at': FieldValue.serverTimestamp(),
    });

    if (driverId != null) {
      batch.update(firestore.collection('drivers').doc(driverId), {
        'is_busy': false,
      });
    }

    await batch.commit();
  }

  /// Real-time stream of a specific ride (for rider & driver UI sync)
  Stream<DocumentSnapshot<Map<String, dynamic>>> streamRide(String rideId) {
    return firestore.collection('rides').doc(rideId).snapshots();
  }

  /// Updates driver GPS location
  Future<void> updateDriverLocation({
    required String driverId,
    required double lat,
    required double lng,
    double heading = 0.0,
  }) async {
    await firestore.collection('driver_locations').doc(driverId).set({
      'driver_id': driverId,
      'lat': lat,
      'lng': lng,
      'heading': heading,
      'updated_at': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// Streams real-time GPS location of a specific driver
  Stream<DocumentSnapshot<Map<String, dynamic>>> streamDriverLocation(String driverId) {
    return firestore.collection('driver_locations').doc(driverId).snapshots();
  }

  /// Toggles driver online / offline status
  Future<void> setDriverOnline({
    required String driverId,
    required bool isOnline,
  }) async {
    await firestore.collection('drivers').doc(driverId).update({
      'is_online': isOnline,
    });
  }

  /// In-ride chat messages stream
  Stream<QuerySnapshot<Map<String, dynamic>>> streamRideMessages(String rideId) {
    return firestore
        .collection('rides')
        .doc(rideId)
        .collection('messages')
        .orderBy('created_at', descending: false)
        .snapshots();
  }

  /// Send in-ride chat message
  Future<void> sendRideMessage({
    required String rideId,
    required String senderId,
    required String senderName,
    required String text,
  }) async {
    await firestore
        .collection('rides')
        .doc(rideId)
        .collection('messages')
        .add({
      'sender_id': senderId,
      'sender_name': senderName,
      'text': text,
      'created_at': FieldValue.serverTimestamp(),
    });
  }

  /// Triggers emergency SOS alert
  Future<void> triggerSos({
    required String userId,
    String? rideId,
    required double lat,
    required double lng,
  }) async {
    await firestore.collection('sos_events').add({
      'user_id': userId,
      'ride_id': rideId,
      'lat': lat,
      'lng': lng,
      'status': 'active',
      'created_at': FieldValue.serverTimestamp(),
    });
  }
}
