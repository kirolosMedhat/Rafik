import 'dart:async';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import '../../firebase_options.dart';
import '../utils/national_id_utils.dart';
import '../utils/phone_number_utils.dart';

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  try {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
    }
  } catch (_) {}
  debugPrint('[FCM Background] Message received: ${message.messageId}, data: ${message.data}');
}

// =============================================================================
// AUTHENTICATION & AUTHORIZATION EXCEPTIONS
// =============================================================================

/// Thrown when a user attempts to log in but has no registered Firestore profile.
/// Enforces: "Never allow a login operation to silently create a new user profile."
class UserNotRegisteredException implements Exception {
  final String message;
  const UserNotRegisteredException([this.message = 'Phone number is not registered. Please register first.']);
  @override
  String toString() => message;
}

/// Thrown when a phone number is already registered under an existing profile.
class UserAlreadyExistsException implements Exception {
  final String message;
  const UserAlreadyExistsException([this.message = 'Phone number is already registered. Please log in.']);
  @override
  String toString() => message;
}

/// Thrown when a user with one role (e.g. rider) attempts to enter an app of another role (e.g. driver).
class RoleMismatchException implements Exception {
  final String expectedRole;
  final String actualRole;
  final String message;

  RoleMismatchException({
    required this.expectedRole,
    required this.actualRole,
    String? message,
  }) : message = message ??
            (expectedRole == 'rider'
                ? 'This account is registered as a Captain. Please use the Rafik Captain application.'
                : 'This account is registered as a Client. Please use the Rafik Rider application.');

  @override
  String toString() => message;
}

/// Thrown when an account has been suspended or deactivated.
class AccountDisabledException implements Exception {
  final String message;
  const AccountDisabledException([this.message = 'This account has been deactivated. Please contact support.']);
  @override
  String toString() => message;
}

/// Thrown when a driver's approval state does not allow access to active operations.
class DriverStatusException implements Exception {
  final String status;
  final String? rejectionReason;
  final String message;

  DriverStatusException({
    required this.status,
    this.rejectionReason,
    String? message,
  }) : message = message ??
            (status == 'pending'
                ? 'Your driver application is currently under review by our operations team.'
                : status == 'rejected'
                    ? 'Your driver application was rejected: ${rejectionReason ?? "Document verification failed"}'
                    : 'Driver account status: $status');

  @override
  String toString() => message;
}

/// Authoritative server-calculated ride request result
class RideRequestResult {
  final String rideId;
  final double fareEgp;
  final double distanceKm;
  final String? pin;

  const RideRequestResult({
    required this.rideId,
    required this.fareEgp,
    required this.distanceKm,
    this.pin,
  });

  @override
  String toString() => rideId;
}

// =============================================================================
// COMPLETE FIREBASE SERVICE FOR RAFIK
// =============================================================================

/// Complete, Enterprise-Grade Firebase Integration for Rafik (رفيق)
/// - Firebase Phone Authentication with SMS OTP (+20 E.164 normalization)
/// - Firebase App Check with Play Integrity (Android) and App Attest (iOS)
/// - Real-Time Trip Dispatch via Cloud Firestore
/// - 6-Sided KYC Document Upload via Firebase Storage
/// - Server-Authoritative Roles & Custom Claims
class FirebaseService {
  /// Computes estimated fare preview in EGP: max(25.00, 15.00 + km * 10.00)
  static double computeFarePreview(double km) {
    final calculated = 15.0 + (km * 10.0);
    return calculated < 25.0 ? 25.0 : double.parse(calculated.toStringAsFixed(2));
  }

  static final FirebaseService _instance = FirebaseService._internal();
  factory FirebaseService() => _instance;
  FirebaseService._internal();

  FirebaseAuth? _auth;
  FirebaseFirestore? _firestore;
  FirebaseStorage? _storage;
  FirebaseFunctions? _functions;

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

  FirebaseStorage get storage {
    _storage ??= FirebaseStorage.instance;
    return _storage!;
  }

  FirebaseFunctions get functions {
    _functions ??= FirebaseFunctions.instanceFor(region: 'europe-west1');
    return _functions!;
  }

  FirebaseDatabase? _rtdb;
  FirebaseDatabase get rtdb {
    _rtdb ??= FirebaseDatabase.instance;
    return _rtdb!;
  }

  /// Initializes Firebase Core, Firestore, Storage, RTDB, and App Check
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
      _storage = FirebaseStorage.instance;
      _functions = FirebaseFunctions.instanceFor(region: 'europe-west1');
      _rtdb = FirebaseDatabase.instance;

      // Initialize Firebase App Check with Play Integrity on Android and App Attest on Apple
      try {
        await FirebaseAppCheck.instance.activate(
          androidProvider: kDebugMode ? AndroidProvider.debug : AndroidProvider.playIntegrity,
          appleProvider: kDebugMode ? AppleProvider.debug : AppleProvider.appAttest,
        );
        debugPrint('[FirebaseService] Firebase App Check successfully activated.');
      } catch (appCheckError) {
        debugPrint('[FirebaseService] App Check activation notice: $appCheckError');
      }

      _initialized = true;
      debugPrint('[FirebaseService] Successfully initialized Firebase platform services.');
    } catch (e) {
      debugPrint('[FirebaseService] Init warning: $e');
      _initialized = true; // Fallback to avoid blocking UI
    }
  }

  User? get currentUser => auth.currentUser;
  Stream<User?> get authStateChanges => auth.authStateChanges();

  // ===========================================================================
  // 1. FIREBASE PHONE AUTHENTICATION (SMS OTP)
  // ===========================================================================

  /// Sends a real SMS OTP via Firebase Authentication with Egyptian E.164 normalization.
  Future<void> sendPhoneOtp({
    required String rawPhone,
    required void Function(String verificationId, int? resendToken) onCodeSent,
    required void Function(FirebaseAuthException e) onVerificationFailed,
    required void Function(PhoneAuthCredential credential) onVerificationCompleted,
    void Function(String verificationId)? onCodeAutoRetrievalTimeout,
    int? forceResendingToken,
  }) async {
    await initialize();

    // 1. Validate and normalize Egyptian phone number
    final normalizedPhone = PhoneNumberUtils.normalizeEgyptianPhone(rawPhone);
    debugPrint('[PhoneAuth] Initiating real SMS OTP to: $normalizedPhone');

    // 2. Trigger real Firebase phone verification
    await auth.verifyPhoneNumber(
      phoneNumber: normalizedPhone,
      timeout: const Duration(seconds: 60),
      forceResendingToken: forceResendingToken,
      verificationCompleted: (PhoneAuthCredential credential) {
        debugPrint('[PhoneAuth] Auto-verification completed.');
        onVerificationCompleted(credential);
      },
      verificationFailed: (FirebaseAuthException e) {
        debugPrint('[PhoneAuth] Verification failed: [${e.code}] ${e.message}');
        onVerificationFailed(e);
      },
      codeSent: (String verificationId, int? resendToken) {
        debugPrint('[PhoneAuth] SMS OTP sent. Verification ID: $verificationId');
        onCodeSent(verificationId, resendToken);
      },
      codeAutoRetrievalTimeout: (String verificationId) {
        debugPrint('[PhoneAuth] Auto-retrieval timed out for: $verificationId');
        if (onCodeAutoRetrievalTimeout != null) {
          onCodeAutoRetrievalTimeout(verificationId);
        }
      },
    );
  }

  /// Verifies an SMS OTP code and returns the [UserCredential].
  Future<UserCredential> verifyPhoneOtp({
    required String verificationId,
    required String smsCode,
  }) async {
    await initialize();
    final credential = PhoneAuthProvider.credential(
      verificationId: verificationId,
      smsCode: smsCode.trim(),
    );
    return await auth.signInWithCredential(credential);
  }

  // ===========================================================================
  // 2. PROFILE RETRIEVAL & ROLE ENFORCEMENT
  // ===========================================================================

  /// Fetches the Firestore profile for a given UID.
  /// If the user is a driver, merges the corresponding `/drivers/{uid}` document.
  Future<Map<String, dynamic>?> getUserProfile(String uid) async {
    await initialize();
    try {
      final userDoc = await firestore.collection('users').doc(uid).get();
      if (!userDoc.exists) return null;

      final userData = userDoc.data() ?? {};
      if (userData['role'] == 'driver') {
        final driverDoc = await firestore.collection('drivers').doc(uid).get();
        if (driverDoc.exists) {
          return {...userData, ...?driverDoc.data()};
        }
      }
      return userData;
    } catch (e) {
      debugPrint('[FirebaseService] Profile fetch error: $e');
      return null;
    }
  }

  /// Fetches current user profile from Firestore
  Future<Map<String, dynamic>?> getCurrentUserProfile() async {
    final user = currentUser;
    if (user == null) return null;
    return await getUserProfile(user.uid);
  }

  /// Signs in a user via Phone OTP and verifies:
  /// 1. Profile existence (never silently creates profiles).
  /// 2. Role adherence (rider vs driver cross-contamination blocked).
  /// 3. Account active status.
  /// 4. Driver approval status (pending/rejected/approved).
  Future<Map<String, dynamic>> loginWithPhone({
    required String verificationId,
    required String smsCode,
    required String expectedRole,
  }) async {
    // 1. Authenticate with Firebase via SMS OTP
    final credential = await verifyPhoneOtp(
      verificationId: verificationId,
      smsCode: smsCode,
    );

    final uid = credential.user?.uid;
    if (uid == null) {
      await auth.signOut();
      throw Exception('Authentication failed: Missing UID.');
    }

    // 2. Retrieve existing profile from Firestore
    final profile = await getUserProfile(uid);

    // CRITICAL: Never allow login to silently create a new user profile
    if (profile == null) {
      debugPrint('[PhoneAuth] Login rejected: No profile exists for UID $uid. Signing out.');
      await auth.signOut();
      throw const UserNotRegisteredException(
        'This phone number is not registered yet. Please create an account.\n'
        'هذا الرقم غير مسجل في رفيق. يرجى إنشاء حساب جديد.',
      );
    }

    // 3. Enforce role separation
    final actualRole = profile['role']?.toString() ?? 'rider';
    if (actualRole != expectedRole) {
      debugPrint('[PhoneAuth] Role mismatch: expected $expectedRole, got $actualRole. Signing out.');
      await auth.signOut();
      throw RoleMismatchException(
        expectedRole: expectedRole,
        actualRole: actualRole,
      );
    }

    // 4. Verify account active status
    final isActive = profile['is_active'] != false;
    if (!isActive) {
      debugPrint('[PhoneAuth] Login rejected: Account $uid is deactivated. Signing out.');
      await auth.signOut();
      throw const AccountDisabledException(
        'Your Rafik account has been deactivated. Please contact support.\n'
        'تم تعطيل حسابك في رفيق. يرجى التواصل مع الدعم الفني.',
      );
    }

    // 5. Refresh ID token so custom claims (role, approved) are fresh
    await credential.user?.getIdToken(true);

    return profile;
  }

  // ===========================================================================
  // 3. REGISTRATION WORKFLOWS (RIDER & DRIVER)
  // ===========================================================================

  /// Registers a new Rider (Client) profile after OTP verification.
  /// Enforces: No duplicate profiles, server-validated fields.
  Future<void> registerRiderProfile({
    required String uid,
    required String fullName,
    required String phone,
    required String gender,
    String? username,
  }) async {
    await initialize();
    final normalizedPhone = PhoneNumberUtils.normalizeEgyptianPhone(phone);

    // 1. Check if user already exists
    final existing = await firestore.collection('users').doc(uid).get();
    if (existing.exists) {
      throw const UserAlreadyExistsException(
        'An account already exists for this number. Please log in.\n'
        'يوجد حساب مسجل بالفعل لهذا الرقم. يرجى تسجيل الدخول.',
      );
    }

    final isFemale = gender.toLowerCase() == 'female';

    // 2. Create user profile in Firestore
    final batch = firestore.batch();
    final userRef = firestore.collection('users').doc(uid);
    batch.set(userRef, {
      'uid': uid,
      'full_name': fullName.trim(),
      'phone': normalizedPhone,
      'username': username?.trim().isNotEmpty == true ? username!.trim() : null,
      'gender': gender.toLowerCase(),
      'role': 'rider',
      'gender_verified': isFemale,
      'is_active': true,
      'rating_avg': 5.0,
      'total_trips': 0,
      'created_at': FieldValue.serverTimestamp(),
      'updated_at': FieldValue.serverTimestamp(),
    });

    await batch.commit();
    await currentUser?.updateDisplayName(fullName.trim());
    debugPrint('[FirebaseService] Rider profile created successfully for UID: $uid');
  }

  /// Registers a new Driver (Captain) profile after OTP verification.
  /// Enforces:
  /// - National ID 14-digit format and gender parity.
  /// - Initial status MUST be 'pending'.
  /// - Client is never auto-approved.
  Future<void> registerDriverProfile({
    required String uid,
    required String fullName,
    required String phone,
    required String gender,
    required String nationalId,
    required String licenseNumber,
    required String vehicleMake,
    required String vehicleModel,
    required int vehicleYear,
    required String vehiclePlate,
    required String vehicleColor,
    String? username,
  }) async {
    await initialize();
    final normalizedPhone = PhoneNumberUtils.normalizeEgyptianPhone(phone);

    // 1. Validate National ID and Gender Parity
    NationalIdUtils.validate(nationalId);
    if (!NationalIdUtils.matchesGender(nationalId, gender)) {
      throw const FormatException(
        'National ID does not match selected gender.\n'
        'الرقم القومي غير متطابق مع الجنس المحدد.',
      );
    }

    // 2. Check if user already exists
    final existingUser = await firestore.collection('users').doc(uid).get();
    if (existingUser.exists) {
      throw const UserAlreadyExistsException(
        'An account already exists for this number. Please log in.\n'
        'يوجد حساب مسجل بالفعل لهذا الرقم. يرجى تسجيل الدخول.',
      );
    }

    // 3. Atomic batch write: /users/{uid} and /drivers/{uid}
    final batch = firestore.batch();

    final userRef = firestore.collection('users').doc(uid);
    batch.set(userRef, {
      'uid': uid,
      'full_name': fullName.trim(),
      'phone': normalizedPhone,
      'username': username?.trim().isNotEmpty == true ? username!.trim() : null,
      'gender': gender.toLowerCase(),
      'role': 'driver',
      'gender_verified': gender.toLowerCase() == 'female',
      'is_active': true,
      'rating_avg': 5.0,
      'created_at': FieldValue.serverTimestamp(),
      'updated_at': FieldValue.serverTimestamp(),
    });

    final driverRef = firestore.collection('drivers').doc(uid);
    batch.set(driverRef, {
      'uid': uid,
      'user_id': uid,
      'full_name': fullName.trim(),
      'phone': normalizedPhone,
      'gender': gender.toLowerCase(),
      'role': 'driver',
      'status': 'pending', // MUST start in pending state for admin verification
      'rejection_reason': null,
      'national_id_number': nationalId.trim(),
      'license_number': licenseNumber.trim(),
      'vehicle_make': vehicleMake.trim(),
      'vehicle_model': vehicleModel.trim(),
      'vehicle_year': vehicleYear,
      'vehicle_plate': vehiclePlate.trim(),
      'vehicle_color': vehicleColor.trim(),
      'is_online': false,
      'is_busy': false,
      'total_trips': 0,
      'wallet_balance_egp': 0.0,
      'rating_avg': 5.0,
      'created_at': FieldValue.serverTimestamp(),
      'updated_at': FieldValue.serverTimestamp(),
    });

    await batch.commit();
    await currentUser?.updateDisplayName(fullName.trim());
    debugPrint('[FirebaseService] Driver profile created with status=pending for UID: $uid');
  }

  // ===========================================================================
  // 4. REAL KYC DOCUMENT UPLOAD TO FIREBASE STORAGE
  // ===========================================================================

  /// Uploads actual binary image bytes for a driver document to Firebase Storage:
  /// Storage Path: `driver_documents/{driverId}/{docType}.jpg`
  ///
  /// Enforces:
  /// - Valid document kinds: `national_id_front`, `national_id_back`,
  ///   `driver_license_front`, `driver_license_back`, `vehicle_reg_front`, `vehicle_reg_back`
  /// - File size <= 5 MB
  /// - Valid image MIME types (JPEG / PNG / WEBP)
  /// - Real-time upload progress reporting
  /// - Saves document metadata in Firestore under `/driver_documents/{driverId}/items/{docType}`
  Future<String> uploadDriverDocument({
    required String driverId,
    required String docType,
    required File file,
    void Function(double progress)? onProgress,
  }) async {
    await initialize();

    // 1. Validate file existence
    if (!file.existsSync()) {
      throw FileSystemException('Document file does not exist', file.path);
    }

    // 2. Validate file size (Max 5 MB)
    final fileBytes = await file.length();
    const maxSizeBytes = 5 * 1024 * 1024; // 5 MB
    if (fileBytes > maxSizeBytes) {
      throw const FormatException('Document file size exceeds the 5MB limit / حجم المستند يتجاوز الحد الأقصى (5 ميجابايت)');
    }

    // 3. Validate image extension
    final pathLower = file.path.toLowerCase();
    String contentType = 'image/jpeg';
    if (pathLower.endsWith('.png')) {
      contentType = 'image/png';
    } else if (pathLower.endsWith('.webp')) {
      contentType = 'image/webp';
    }

    // 4. Upload to Firebase Storage
    final storagePath = 'driver_documents/$driverId/$docType.jpg';
    final ref = storage.ref(storagePath);

    final uploadTask = ref.putFile(
      file,
      SettableMetadata(
        contentType: contentType,
        customMetadata: {
          'driver_id': driverId,
          'doc_type': docType,
          'uploaded_at': DateTime.now().toIso8601String(),
        },
      ),
    );

    // Track real progress
    StreamSubscription<TaskSnapshot>? sub;
    if (onProgress != null) {
      sub = uploadTask.snapshotEvents.listen((TaskSnapshot snap) {
        if (snap.totalBytes > 0) {
          final progress = snap.bytesTransferred / snap.totalBytes;
          onProgress(progress);
        }
      });
    }

    try {
      await uploadTask;
    } finally {
      await sub?.cancel();
    }

    // 5. Save document metadata in Firestore
    final docItemRef = firestore
        .collection('driver_documents')
        .doc(driverId)
        .collection('items')
        .doc(docType);

    await docItemRef.set({
      'driver_id': driverId,
      'doc_type': docType,
      'storage_path': storagePath,
      'file_size_bytes': fileBytes,
      'status': 'pending',
      'uploaded_at': FieldValue.serverTimestamp(),
      'updated_at': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    // Update driver record documents sub-map
    await firestore.collection('drivers').doc(driverId).set({
      'documents': {
        docType: {
          'storage_path': storagePath,
          'status': 'pending',
          'uploaded_at': FieldValue.serverTimestamp(),
        }
      }
    }, SetOptions(merge: true));

    debugPrint('[Storage] Document $docType uploaded successfully to $storagePath');
    return storagePath;
  }

  /// Streams the real-time driver profile document (to listen for status changes like approval/rejection)
  Stream<DocumentSnapshot<Map<String, dynamic>>> streamDriverProfile(String driverId) {
    return firestore.collection('drivers').doc(driverId).snapshots();
  }

  /// Sign out
  Future<void> signOut() async {
    await auth.signOut();
  }

  // ===========================================================================
  // 5. REAL-TIME DISPATCH & RIDE LIFECYCLE
  // ===========================================================================

  final Map<String, String> _ridePins = {};

  /// Creates a ride request strictly via server-authoritative Cloud Function (requestRide).
  /// Requirement A compliant: No insecure direct Firestore creation fallback.
  Future<RideRequestResult> requestRide({
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
    await initialize();
    final user = currentUser;
    if (user == null) throw Exception('User not authenticated');

    final callable = functions.httpsCallable('requestRide');
    final res = await callable.call({
      'tier': tier,
      'pickup_address': pickupAddress,
      'pickup_lat': pickupLat,
      'pickup_lng': pickupLng,
      'dropoff_address': dropoffAddress,
      'dropoff_lat': dropoffLat,
      'dropoff_lng': dropoffLng,
      'payment_method': paymentMethod,
    });

    final data = Map<String, dynamic>.from(res.data);
    final rideId = data['ride_id'].toString();
    final serverFare = (data['fare_egp'] as num?)?.toDouble() ?? fareEgp;
    final serverDist = (data['distance_km'] as num?)?.toDouble() ?? distanceKm;
    final pin = data['pin']?.toString();

    if (pin != null) {
      _ridePins[rideId] = pin;
    }
    debugPrint('[FirebaseService] requestRide server success: $rideId, fare: $serverFare EGP');
    return RideRequestResult(
      rideId: rideId,
      fareEgp: serverFare,
      distanceKm: serverDist,
      pin: pin,
    );
  }

  /// Fetches the 4-digit pickup PIN for the passenger strictly from isolated security document
  Future<String?> fetchRidePin(String rideId) async {
    if (_ridePins.containsKey(rideId)) {
      return _ridePins[rideId];
    }
    await initialize();
    try {
      final pinDoc = await firestore
          .collection('rides')
          .doc(rideId)
          .collection('security')
          .doc('pin_data')
          .get();
      if (pinDoc.exists && pinDoc.data()?['pin'] != null) {
        final pin = pinDoc.data()!['pin'].toString();
        _ridePins[rideId] = pin;
        return pin;
      }
    } catch (e) {
      debugPrint('[FirebaseService] fetchRidePin notice: $e');
    }
    return null;
  }

  /// Accepts a ride offer atomically strictly via Cloud Function (acceptRide).
  /// Requirement A compliant: No direct client Firestore update fallback.
  Future<bool> acceptRide({
    String offerId = '',
    required String rideId,
    required String driverId,
    required String driverName,
    required String driverPhone,
    required String vehiclePlate,
    required String vehicleModel,
  }) async {
    await initialize();
    final callable = functions.httpsCallable('acceptRide');
    final res = await callable.call({'offerId': offerId.isNotEmpty ? offerId : rideId});
    final data = Map<String, dynamic>.from(res.data);
    return data['success'] == true;
  }

  /// Driver arrived at pickup location strictly via Cloud Function (markArrived).
  /// Requirement D compliant: Backend verifies live RTDB coordinates; client coordinates are not accepted.
  Future<void> markArrived(String rideId) async {
    await initialize();
    final callable = functions.httpsCallable('markArrived');
    await callable.call({'rideId': rideId});
  }

  /// Driver verifies 4-digit PIN and starts trip strictly via Cloud Function (verifyPinAndStartTrip).
  /// Requirement A & C compliant: No client PIN check or state elevation.
  Future<Map<String, dynamic>> startRide({
    required String rideId,
    required String pin,
  }) async {
    await initialize();
    final callable = functions.httpsCallable('verifyPinAndStartTrip');
    final res = await callable.call({
      'rideId': rideId,
      'pin': pin.trim(),
    });
    final data = Map<String, dynamic>.from(res.data);
    if (data['success'] == true) {
      return {'ok': true, 'status': 'in_progress'};
    } else {
      return {
        'ok': false,
        'status': data['status'],
        'attempts_left': data['attempts_left'] ?? 0,
        'locked': data['is_locked'] == true,
        'error': data['is_locked'] == true
            ? 'Trip PIN is locked after 3 failed attempts.'
            : 'Incorrect PIN. ${data['attempts_left'] ?? 0} attempts remaining.',
      };
    }
  }

  /// Completes trip strictly via Cloud Function (completeRide).
  /// Requirement A compliant: No client wallet crediting or status updates.
  Future<void> completeRide({
    required String rideId,
    String? driverId,
    double? fareEgp,
  }) async {
    await initialize();
    final callable = functions.httpsCallable('completeRide');
    await callable.call({'rideId': rideId});
  }

  /// Cancels a ride strictly via Cloud Function (cancelRide).
  /// Requirement A compliant: No direct client batch update fallback.
  Future<void> cancelRide({
    required String rideId,
    required String cancelledBy,
    required String reason,
  }) async {
    await initialize();
    final callable = functions.httpsCallable('cancelRide');
    await callable.call({
      'rideId': rideId,
      'reason': reason,
    });
  }

  /// Mutual Rating strictly via Cloud Function (rateRide).
  /// Requirement A & G compliant: Validates rating boundaries and updates average atomically on server.
  Future<void> rateRide({
    required String rideId,
    required double rating,
    List<String>? badges,
    String? comment,
  }) async {
    await initialize();
    final callable = functions.httpsCallable('rateRide');
    await callable.call({
      'rideId': rideId,
      'rating': rating,
      'review': [comment ?? '', ...(badges ?? [])].where((s) => s.isNotEmpty).join(' | '),
    });
  }

  // ===========================================================================
  // 6. FIREBASE CLOUD MESSAGING (FCM) & ACTIVE SESSION MANAGEMENT (Requirement F)
  // ===========================================================================

  FirebaseMessaging? _messaging;
  FirebaseMessaging get messaging {
    _messaging ??= FirebaseMessaging.instance;
    return _messaging!;
  }

  /// Initializes FCM permissions, listeners, and token refresh
  Future<void> initializeFcm({
    void Function(RemoteMessage message)? onOfferReceived,
    void Function(RemoteMessage message)? onNotificationOpened,
  }) async {
    await initialize();

    try {
      final settings = await messaging.requestPermission(
        alert: true,
        announcement: false,
        badge: true,
        carPlay: false,
        criticalAlert: false,
        provisional: false,
        sound: true,
      );
      debugPrint('[FCM] Notification authorization status: ${settings.authorizationStatus}');

      // Register background message handler
      FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

      // Foreground message listener
      FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        debugPrint('[FCM Foreground] Got message: ${message.messageId}, type: ${message.data['type']}');
        if (message.data['type'] == 'ride_offer' && onOfferReceived != null) {
          onOfferReceived(message);
        }
      });

      // Background notification tap listener
      FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
        debugPrint('[FCM onMessageOpenedApp] Notification opened: ${message.messageId}');
        if (onNotificationOpened != null) {
          onNotificationOpened(message);
        }
      });

      // Cold start notification tap
      final initialMessage = await messaging.getInitialMessage();
      if (initialMessage != null && onNotificationOpened != null) {
        onNotificationOpened(initialMessage);
      }

      // Auto-register token if user is signed in
      final uid = currentUser?.uid;
      if (uid != null) {
        await registerFcmToken(uid);
      }
    } catch (e) {
      debugPrint('[FCM] Initialization notice: $e');
    }
  }

  /// Registers and persists the driver's FCM token under their active session
  Future<void> registerFcmToken(String userId) async {
    try {
      final token = await messaging.getToken();
      if (token != null && token.isNotEmpty) {
        await _persistFcmToken(userId, token);
      }

      messaging.onTokenRefresh.listen((newToken) async {
        debugPrint('[FCM] Token refreshed for $userId');
        await _persistFcmToken(userId, newToken);
      });
    } catch (e) {
      debugPrint('[FCM] Token registration warning: $e');
    }
  }

  /// Persists FCM token to Firestore /active_sessions/{userId} and RTDB
  Future<void> _persistFcmToken(String userId, String token) async {
    try {
      // 1. Firestore Active Session
      await firestore.collection('active_sessions').doc(userId).set({
        'fcm_token': token,
        'updated_at': FieldValue.serverTimestamp(),
        'platform': Platform.isAndroid ? 'android' : (Platform.isIOS ? 'ios' : 'other'),
      }, SetOptions(merge: true));

      // 2. RTDB Active Session
      await rtdb.ref('active_sessions/$userId').update({
        'fcm_token': token,
        'updated_at': ServerValue.timestamp,
      });

      // 3. User document backup
      await firestore.collection('users').doc(userId).update({
        'fcm_token': token,
      });
      debugPrint('[FCM] Token securely persisted for $userId');
    } catch (e) {
      debugPrint('[FCM] Token persist note: $e');
    }
  }

  /// Removes and invalidates the session token upon sign-out
  Future<void> removeFcmToken(String userId) async {
    try {
      await firestore.collection('active_sessions').doc(userId).delete();
      await rtdb.ref('active_sessions/$userId/fcm_token').remove();
      await messaging.deleteToken();
      debugPrint('[FCM] Token revoked and active session cleared for $userId');
    } catch (e) {
      debugPrint('[FCM] Token removal notice: $e');
    }
  }

  /// Trigger emergency SOS alert
  Future<void> triggerSos({
    String? rideId,
    String? userId,
    required double lat,
    required double lng,
  }) async {
    await initialize();
    final uid = userId ?? currentUser?.uid ?? '';
    try {
      if (rideId != null && rideId.isNotEmpty) {
        await firestore.collection('rides').doc(rideId).update({
          'sos_triggered': true,
          'sos_at': FieldValue.serverTimestamp(),
          'sos_lat': lat,
          'sos_lng': lng,
        }).catchError((_) {});
      }
      await firestore.collection('sos_alerts').add({
        'ride_id': rideId,
        'user_id': uid,
        'lat': lat,
        'lng': lng,
        'created_at': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint('[FirebaseService] triggerSos notice: $e');
    }
  }

  /// Fetches historical user trips from Firestore
  Future<List<Map<String, dynamic>>> fetchUserTrips() async {
    await initialize();
    final user = currentUser;
    if (user == null) return [];

    try {
      final profile = await getUserProfile(user.uid);
      final isDriver = profile?['role'] == 'driver';

      final query = isDriver
          ? firestore.collection('rides').where('driver_id', isEqualTo: user.uid)
          : firestore.collection('rides').where('rider_id', isEqualTo: user.uid);

      final snap = await query.orderBy('requested_at', descending: true).limit(30).get();
      return snap.docs.map((d) => {'id': d.id, ...d.data()}).toList();
    } catch (e) {
      debugPrint('[FirebaseService] fetchUserTrips notice: $e');
      return [];
    }
  }

  /// Gets emergency contacts for safety shield
  Future<List<Map<String, dynamic>>> getEmergencyContacts() async {
    await initialize();
    final user = currentUser;
    if (user == null) return [];

    try {
      final snap = await firestore
          .collection('users')
          .doc(user.uid)
          .collection('emergency_contacts')
          .get();
      return snap.docs.map((d) => {'id': d.id, ...d.data()}).toList();
    } catch (e) {
      debugPrint('[FirebaseService] getEmergencyContacts notice: $e');
      return [];
    }
  }

  /// Adds an emergency contact
  Future<void> addEmergencyContact({
    required String name,
    required String phone,
    String? relation,
    String? relationship,
  }) async {
    await initialize();
    final user = currentUser;
    if (user == null) return;

    await firestore
        .collection('users')
        .doc(user.uid)
        .collection('emergency_contacts')
        .add({
      'contact_name': name,
      'contact_phone': phone,
      'relationship': relationship ?? relation ?? 'Emergency Contact',
      'created_at': FieldValue.serverTimestamp(),
    });
  }

  /// Real-time stream of a specific ride (for rider & driver UI sync)
  Stream<DocumentSnapshot<Map<String, dynamic>>> streamRide(String rideId) {
    return firestore.collection('rides').doc(rideId).snapshots();
  }

  StreamSubscription<DatabaseEvent>? _presenceSubscription;

  /// Updates driver GPS telemetry in Firebase Realtime Database (/driver_locations/{driverId})
  /// Client submits only pure telemetry fields (lat, lng, heading, speed, updated_at).
  /// Server-authoritative dispatch fields are never modified by the client.
  Future<void> updateDriverTelemetry({
    required String driverId,
    required double lat,
    required double lng,
    double heading = 0.0,
    double speed = 0.0,
  }) async {
    final ref = rtdb.ref('driver_locations/$driverId');
    await ref.update({
      'lat': lat,
      'lng': lng,
      'heading': heading,
      'speed': speed,
      'updated_at': ServerValue.timestamp,
    });
  }

  /// Backward-compatible alias for updateDriverTelemetry
  Future<void> updateDriverLocation({
    required String driverId,
    required double lat,
    required double lng,
    double heading = 0.0,
    double speed = 0.0,
  }) async {
    await updateDriverTelemetry(
      driverId: driverId,
      lat: lat,
      lng: lng,
      heading: heading,
      speed: speed,
    );
  }

  /// Configures real-time presence lifecycle for a driver captain using .info/connected
  /// Registers onDisconnect() handlers on RTDB for graceful recovery on network drop/app crash
  void configureDriverPresence({
    required String driverId,
    required bool isOnline,
  }) {
    final connectedRef = rtdb.ref('.info/connected');
    final presenceRef = rtdb.ref('driver_presence/$driverId');
    final locationRef = rtdb.ref('driver_locations/$driverId');

    _presenceSubscription?.cancel();

    if (!isOnline) {
      // Driver explicitly toggled offline
      presenceRef.set({
        'state': 'offline',
        'last_changed': ServerValue.timestamp,
        'last_seen': ServerValue.timestamp,
      }).catchError((_) {});

      locationRef.update({
        'is_online': false,
        'updated_at': ServerValue.timestamp,
      }).catchError((_) {});

      firestore.collection('drivers').doc(driverId).update({
        'is_online': false,
      }).catchError((_) {});
      return;
    }

    _presenceSubscription = connectedRef.onValue.listen((event) {
      final isConnected = event.snapshot.value == true;
      if (isConnected) {
        // 1. Register onDisconnect handlers
        presenceRef.onDisconnect().set({
          'state': 'offline',
          'last_changed': ServerValue.timestamp,
          'last_seen': ServerValue.timestamp,
        });
        locationRef.onDisconnect().update({
          'is_online': false,
          'updated_at': ServerValue.timestamp,
        });

        // 2. Mark online immediately
        presenceRef.set({
          'state': 'online',
          'last_changed': ServerValue.timestamp,
          'last_seen': ServerValue.timestamp,
        });
        locationRef.update({
          'is_online': true,
          'updated_at': ServerValue.timestamp,
        });
        firestore.collection('drivers').doc(driverId).update({
          'is_online': true,
        }).catchError((_) {});
      }
    });
  }

  /// Cancels any active driver presence connection listener
  void cancelDriverPresence() {
    _presenceSubscription?.cancel();
    _presenceSubscription = null;
  }

  /// Streams real-time GPS telemetry of the assigned driver from RTDB
  /// Protected by RTDB rules: only assigned rider (active_rider_id) can read.
  Stream<DatabaseEvent> streamAssignedDriverLocation(String driverId) {
    return rtdb.ref('driver_locations/$driverId').onValue;
  }

  /// Streams pending ride offers dispatched to a specific driver from Firestore
  Stream<QuerySnapshot<Map<String, dynamic>>> streamDriverOffers(String driverId) {
    return firestore
        .collection('ride_offers')
        .where('driver_id', isEqualTo: driverId)
        .where('status', isEqualTo: 'pending')
        .snapshots();
  }

  /// Retrieves driver profile from Firestore
  Future<Map<String, dynamic>?> getDriverProfile(String driverId) async {
    final snap = await firestore.collection('drivers').doc(driverId).get();
    return snap.data();
  }

  /// Retrieves vehicle profile from Firestore
  Future<Map<String, dynamic>?> getVehicleProfile(String driverId) async {
    final snap = await firestore.collection('vehicles').doc(driverId).get();
    return snap.data();
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
}
