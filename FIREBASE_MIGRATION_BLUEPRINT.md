# RAFIK (رفيق) — FIREBASE MIGRATION BLUEPRINT & TECHNICAL AUDIT
**Document Version:** 1.0.0-PROD  
**Target Environment:** Firebase Enterprise Suite (`rafik-98844`)  
**Scope:** Flutter Rider App, Flutter Driver App, Web Admin Portal, Cloud Functions Backend  
**Status:** ARCHITECTURAL SPECIFICATION & AUDIT (PHASE 1)  
**Date:** November 2026  

---

## EXECUTIVE SUMMARY

Rafik (رفيق) is a high-availability, dual-tier Egyptian ride-hailing ecosystem serving Greater Cairo (Cairo, Giza, New Cairo, 6th of October, Sheikh Zayed, Maadi, Heliopolis). The platform offers two service classes:
1. **Rafik Standard (رَفِيق ستاندرد):** Premium ride-hailing open to all verified riders and drivers, styled in Jet Black (`#000000`) and Titanium Ice Blue (`#3B82F6`).
2. **Rafik Girl (رَفِيق جيرل):** An exclusive, high-security women-only transit network pairing verified female riders with verified female drivers, styled in Obsidian Berry (`#12080C`) and Egyptian Rose Gold (`#B76E79`), featuring government KYC verification, 13th-digit National ID parity verification, and automated route monitoring.

This document represents the **authoritative technical audit and comprehensive Firebase migration blueprint**. It evaluates the existing codebase, exposes architectural flaws and simulation shortcuts, specifies a zero-trust production Firebase architecture, and provides a file-by-file implementation plan.

---

## 1. EXISTING ARCHITECTURE

### 1.1 Historical Evolution
The Rafik repository has passed through three architectural generations:
1. **Generation 1 (Legacy Prototype):** An insecure Express.js Node.js server (`backend/src/index.ts`) bound to local port `5000`, writing synchronously to a monolithic JSON file (`backend/data/database.json`), broadcasting via unrestricted Socket.IO (`cors: *`), and relying on hardcoded local LAN IP addresses (`192.168.1.13:5000`).
2. **Generation 2 (Attempted Pure Supabase Cloud):** An initiative to eliminate the Node.js server in favor of Supabase Cloud (PostgreSQL 15, PostGIS spatial queries, Row Level Security, and 16 `SECURITY DEFINER` RPCs).
3. **Current State (Unstable Hybrid / Incomplete Migration):** The repository is currently in an uncoordinated hybrid state:
   - The Flutter mobile application contains a dual backend layer (`SupabaseService` wrapping both `FirebaseService` and `SupabaseClient`).
   - `FirebaseService` was introduced using an email/password masquerade rather than real SMS OTP.
   - `admin_portal/index.html` loads both the Supabase JS SDK (v2.49.1) and Firebase Compat SDK (v10.12.2), but delegates all critical administrative actions (driver approvals, KYC identity reviews, SOS incident resolution, metrics) to Supabase RPCs.
   - Core Firebase services required for production ride-hailing (Firebase Realtime Database for driver tracking and Firebase Cloud Messaging for push dispatch) are missing from `pubspec.yaml`.

```
CURRENT HYBRID STATE (FRAGILE & SPLIT):

┌──────────────────────────────────────┐       ┌──────────────────────────────────────┐
│       Rafik Rider App (Flutter)      │       │      Rafik Driver App (Flutter)      │
│     (Flavored: com.rafik.rider)      │       │     (Flavored: com.rafik.driver)     │
└──────────────────┬───────────────────┘       └──────────────────┬───────────────────┘
                   │                                              │
                   ├───────────────────────┬──────────────────────┤
                   │                       │                      │
                   ▼                       ▼                      ▼
       ┌──────────────────────┐ ┌────────────────────┐ ┌────────────────────┐
       │   FirebaseService    │ │  SupabaseService   │ │ PersistentStorage  │
       │ (Email/Pass Masking, │ │ (Dual-call bridge, │ │ (Reads Supabase    │
       │  Firestore polling,  │ │  client-side fare, │ │  Auth currentUser  │
       │  leaked PIN in ride) │ │  dummy fallbacks)  │ │  directly)         │
       └───────────┬──────────┘ └──────────┬─────────┘ └────────────────────┘
                   │                       │
         ┌─────────┴─────────┐   ┌─────────┴─────────┐
         ▼                   ▼   ▼                   ▼
┌──────────────────┐ ┌───────────────────┐ ┌─────────────────────────────────┐
│ Cloud Firestore  │ │ Firebase Storage  │ │      Supabase Cloud Engine      │
│  (rafik-98844)   │ │  (Initialized,    │ │ • PostgreSQL + PostGIS (RPCs)   │
│ • rides, users,  │ │   uploads unused  │ │ • Row Level Security (RLS)      │
│   drivers, sos   │ │   in onboarding)  │ │ • Supabase Realtime Channels    │
└──────────────────┘ └───────────────────┘ └────────────────┬────────────────┘
                                                            │
                                         ┌──────────────────┴────────────────┐
                                         ▼                                   ▼
                               ┌───────────────────┐               ┌───────────────────┐
                               │   Admin Portal    │               │  Supabase Storage │
                               │ (Dual-initialized │               │ (driver-documents,│
                               │  depends on RPCs) │               │  identity-docs)   │
                               └───────────────────┘               └───────────────────┘
```

### 1.2 Component Breakdown
- **Flutter Application (`mobile_app/`):** Single Flutter codebase supporting two application targets:
  - `main_rider.dart` (Rider Flavor: `com.rafik.rider`)
  - `main_driver.dart` (Driver Flavor: `com.rafik.driver`)
  - Legacy `main.dart` with branded name "Go Safe"
- **Web Admin Operations Portal (`admin_portal/`):** Single-page web dashboard (`index.html`, `config.js`) featuring an interactive OpenStreetMap Leaflet dispatch map, driver KYC document review queue, passenger biometric identity verification queue, live SOS alert monitor, and platform operational metrics.
- **Supabase Backend Assets (`supabase/`):**
  - `migrations/0001_core.sql`: Schema definitions for 12 tables, PostGIS geography types, national ID parity function, triggers, and Row Level Security policies.
  - `migrations/0002_rpcs.sql`: 16 PL/pgSQL stored procedures handling ride requests, acceptance, arrivals, PIN validation, completion, cancellations, ratings, and driver vetting.
  - `tests/01_security_and_rpc_test.sql`: SQL automated tests.

---

## 2. PROBLEMS DISCOVERED IN THE ACTUAL IMPLEMENTATION

An exhaustive source-code inspection revealed critical security vulnerabilities, architectural shortcuts, and broken flows:

### P-01: Synthetic Email/Password Masquerade Bypassing SMS OTP
- **Location:** `mobile_app/lib/core/services/firebase_service.dart:57-65`, `mobile_app/lib/features/auth/auth_screen.dart:123-148`
- **Defect:** Real Phone Authentication with SMS OTP is absent in the primary auth flow. Instead, `FirebaseService._toAuthEmail(identifier)` cleans the input phone number or username and appends `@rafik.app` (e.g., `01012345678@rafik.app`). Authentication executes via `signInWithEmailAndPassword` and `createUserWithEmailAndPassword`.
- **Impact:** Any user can register arbitrary phone numbers without proving device possession. SMS verification is completely bypassed.

### P-02: Instant Driver Auto-Admission & Approval Bypass
- **Location:** `mobile_app/lib/features/auth/auth_screen.dart:385-405`
- **Defect:** In `_handleRegisterCaptain`, immediately after creating the Firestore document with `status: 'pending'`, the app calls:
  ```dart
  Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const DriverRadarScreen()));
  ```
- **Impact:** An unvetted, unapproved driver immediately gains access to the live dispatch radar without waiting for administrator review.

### P-03: Session Restoration Ignores Account Status & Role
- **Location:** `mobile_app/lib/main_driver.dart:40-49`, `mobile_app/lib/main_rider.dart:40-49`
- **Defect:** On application launch, `main_driver.dart` evaluates `StreamBuilder<User?>` on `authStateChanges`. If `user != null`, it directly renders `DriverRadarScreen()`:
  ```dart
  if (user != null) {
    return const DriverRadarScreen();
  }
  ```
- **Impact:** A rider logging into the driver app, or a driver whose account was rejected or suspended, is automatically routed into the operational radar without profile validation or status checks.

### P-04: Global Unfiltered Ride Broadcast (O(N) Driver Exposure)
- **Location:** `mobile_app/lib/features/driver/driver_radar_screen.dart:144-165`, `mobile_app/lib/core/services/firebase_service.dart:281-286`
- **Defect:** `streamAvailableRides()` executes an unrestricted query across the entire database:
  ```dart
  firestore.collection('rides').where('status', isEqualTo: 'requested').snapshots();
  ```
- **Impact:** Every single online driver in Egypt receives snapshot updates for every ride requested across the country. There is zero spatial proximity filtering, zero matching radius, and zero service tier isolation.

### P-05: Secret Trip Handshake PIN Leaked to Driver Client
- **Location:** `mobile_app/lib/features/driver/driver_radar_screen.dart:157`
- **Defect:** When an incoming ride snapshot arrives, the driver screen reads the secret PIN directly from the document payload:
  ```dart
  _targetPin = data['pin']?.toString() ?? '7429';
  ```
- **Impact:** The driver's device possesses the secret PIN before pickup. A malicious captain can read the PIN from network traffic or memory and start the ride without the passenger ever boarding the vehicle.

### P-06: Hardcoded Master PINs, Demo Bypasses, and Static Fallbacks
- **Location:** Multiple files
  - `mobile_app/lib/features/driver/driver_radar_screen.dart:50, 157`: Default fallback PIN is hardcoded to `'7429'`.
  - `mobile_app/lib/features/auth/otp_verification_sheet.dart:103`: Hardcoded demo bypass accepts `'1234'` or `'123456'` and logs in via a seeded internal email (`${role}_${gender}_test@rafik.internal`).
  - `mobile_app/lib/features/biometrics/id_ocr_service.dart:71, 80`: Hardcoded fallback National ID `'29810140102468'` automatically returns female approval on any camera/ML Kit exception.
  - `mobile_app/lib/features/biometrics/liveness_detection_screen.dart:138`: Hardcoded anti-spoof score `0.992` automatically approves female liveness on any capture failure.
  - `mobile_app/lib/features/rider/trip_history_screen.dart:18-50`: Hardcoded mock trips list (`RIDE-9941`, `RIDE-9812`, etc.) displayed when remote queries return empty.
  - `mobile_app/lib/features/rider/safety_shield_sheet.dart:32`: Hardcoded default emergency contacts (`Nabila Medhat`, `Mina Medhat`).

### P-07: Mock Document Upload Pipeline in Onboarding
- **Location:** `mobile_app/lib/core/services/supabase_service.dart:357-373`, `mobile_app/lib/features/driver/driver_onboarding_screen.dart:141`
- **Defect:** While `DriverOnboardingScreen` captures 6 camera photos, `uploadDriverDocument()` ignores the binary file:
  ```dart
  await FirebaseService().firestore.collection('drivers').doc(user.uid).collection('documents').doc(kind).set({
    'kind': kind,
    'status': 'pending',
    'uploaded_at': FieldValue.serverTimestamp(),
  });
  return 'uploaded';
  ```
- **Impact:** No image bytes are uploaded to Firebase Storage. Administrators in the operations portal cannot review real driver licenses, national IDs, or vehicle registrations.

### P-08: Client-Authoritative Pricing & Hardcoded Trip Distance
- **Location:** `mobile_app/lib/core/services/supabase_service.dart:80-99`
- **Defect:** Trip distance is hardcoded to `5.0` km inside `requestRide()`, and trip fare is computed on the mobile client using `computeFarePreview(distanceKm)`.
- **Impact:** A compromised or modified client can submit arbitrary trip distances and zero-cost fares directly into Firestore.

### P-09: Excessive Latency & Cost from Firestore Driver Telemetry
- **Location:** `mobile_app/lib/core/services/firebase_service.dart:431-444`, `mobile_app/lib/features/driver/driver_radar_screen.dart:122-137`
- **Defect:** Driver GPS positions are written directly to Firestore document `/driver_locations/{driverId}` every 5 seconds.
- **Impact:** Writing high-frequency GPS pings to Firestore generates massive document write costs, rate limits, and latency spikes. Firestore does not support automatic disconnect triggers (`onDisconnect`), leaving drivers permanently marked "online" if the app crashes.

### P-10: Admin Operations Portal Disconnected from Firebase
- **Location:** `admin_portal/index.html:600-1440`
- **Defect:** While Firebase is initialized in `index.html`, all administrative workflows (reviewing drivers, reviewing identity proofs, fetching metrics, real-time dispatch map, resolving SOS alerts) are hard-wired to Supabase RPCs (`admin_review_driver`, `admin_review_identity`) and Supabase Realtime channels (`admin-realtime-feed`).
- **Impact:** The admin portal cannot function with a pure Firebase backend until all queries, mutations, signed URLs, and listeners are ported to Firebase Admin / Firestore.

### P-11: Concurrent Dual-Stream State Contention
- **Location:** `mobile_app/lib/features/rider/rider_home_screen.dart:205-280`, `mobile_app/lib/features/driver/driver_radar_screen.dart:142-210`
- **Defect:** Screens register listeners to both Firestore snapshot streams and Supabase `postgres_changes` channels simultaneously, resulting in double state transitions, conflicting haptic triggers, and race conditions.

---

## 3. COMPLETE FIREBASE ARCHITECTURE

The target architecture eliminates Supabase entirely. All client applications communicate with a unified, production-grade Firebase cloud ecosystem.

```
TARGET PURE FIREBASE ENTERPRISE ARCHITECTURE:

┌──────────────────────────────────────┐       ┌──────────────────────────────────────┐
│      Rafik Rider App (Flutter)       │       │      Rafik Driver App (Flutter)      │
│     (Flavored: com.rafik.rider)      │       │     (Flavored: com.rafik.driver)     │
└──────────────────┬───────────────────┘       └──────────────────┬───────────────────┘
                   │                                              │
                   ├───────────────────────┬──────────────────────┤
                   │                       │                      │
                   ▼                       ▼                      ▼
┌─────────────────────────────────────────────────────────────────────────────────────┐
│                            FIREBASE APPLICATION SERVICES                            │
├─────────────────────────────────────────────────────────────────────────────────────┤
│ 1. Firebase Phone Auth: SMS OTP Verification, E.164 Egypt (+20), App Check Token    │
│ 2. Cloud Firestore: Primary Document Store, Transactions, Security Rules            │
│ 3. Firebase Realtime Database: Sub-100ms Driver GPS Locations, Presence / Heartbeats │
│ 4. Firebase Storage: Encrypted Private KYC Vault (Driver Licenses, National IDs)    │
│ 5. Firebase Cloud Messaging (FCM): High-Priority Wakeup Dispatch & Push Alerts       │
│ 6. Firebase Cloud Functions (v2): Server-Authoritative Logic & Admin Backend         │
│ 7. Firebase App Check: Play Integrity & DeviceCheck Protection                      │
└──────────────────────────────────────────┬──────────────────────────────────────────┘
                                           │
                                           ▼
┌─────────────────────────────────────────────────────────────────────────────────────┐
│                            WEB ADMIN OPERATIONS PORTAL                              │
│  Static Web App (Firebase Hosting) • Leaflet OSM Dispatch • KYC Verification Queue   │
│  Firebase JS SDK v10 (Auth + Firestore + RTDB + Storage Signed URLs)                │
└─────────────────────────────────────────────────────────────────────────────────────┘
```

### 3.1 Architectural Principles
1. **Zero Client Trust:** The mobile clients and web portal are untrusted presentation layers. Fares, driver matching, ride offers, state transitions, PIN verification, wallet balances, and KYC approvals are executed exclusively via atomic Firestore Transactions or trusted Cloud Functions using the Firebase Admin SDK.
2. **Dedicated Telemetry Engine:** Cloud Firestore is reserved for persistent business documents (rides, profiles, payments). Firebase Realtime Database is used exclusively for ephemeral, high-frequency driver coordinates, connection states, and presence heartbeats.
3. **Cryptographic Handshake PIN Isolation:** Ride security PINs are generated on the server and stored in a private subcollection (`/rides/{rideId}/security/pin_data`) accessible strictly by the passenger and the server. The driver client NEVER has read access to this document.
4. **Strict Custom Claims Role-Based Access Control (RBAC):** Privileges (`admin`, `driver`, `rider`, `approved`, `gender_verified`) are stamped directly into the Firebase Auth ID Token via Custom Claims, ensuring deterministic security rule evaluation without redundant Firestore lookups.

---

## 4. AUTHENTICATION ANALYSIS & IMPLEMENTATION PLAN

### 4.1 Egyptian Phone Number Specification
All phone numbers must conform to Egyptian mobile telecommunications standards:
- Valid Operator Prefixes:
  - `010`: Vodafone Egypt
  - `011`: Etisalat Misr
  - `012`: Orange Egypt
  - `015`: Telecom Egypt (WE)
- National Format: `01[0125][0-9]{8}` (11 digits)
- International E.164 Format: `+201[0125][0-9]{8}` (13 characters)

#### Phone Normalization Algorithm:
```dart
String? normalizeEgyptianPhone(String input) {
  // Strip whitespace, dashes, parentheses
  String clean = input.replaceAll(RegExp(r'[\s\-\(\)]'), '');
  
  // Remove leading 00
  if (clean.startsWith('00')) {
    clean = clean.substring(2);
  }
  
  // Match standard Egyptian national format (e.g., 01012345678)
  final nationalRegex = RegExp(r'^0?(1[0125]\d{8})$');
  final match = nationalRegex.firstMatch(clean);
  if (match != null) {
    return '+20${match.group(1)}';
  }
  
  // Match existing +20 format
  final e164Regex = RegExp(r'^\+20(1[0125]\d{8})$');
  if (e164Regex.hasMatch(clean)) {
    return clean;
  }
  
  return null; // Invalid Egyptian mobile number
}
```

### 4.2 Registration Flow (Riders & Drivers)
```
REGISTRATION SEQUENCE:

User                Mobile App              Firebase Auth              Firestore / Cloud Function
 │                      │                         │                               │
 │── Enter Phone No. ──>│                         │                               │
 │                      │── verifyPhoneNumber ───>│                               │
 │                      │<── Code Sent (SMS) ─────│                               │
 │<── Enter 6-digit OTP─│                         │                               │
 │── Enters OTP ───────>│── signInWithCredential ─│                               │
 │                      │<── UserCredential (UID) ┘                               │
 │                      │                                                         │
 │                      │── GET /users/{uid} ────────────────────────────────────>│
 │                      │<── Document Does Not Exist ─────────────────────────────│
 │                      │                                                         │
 │                      │ [Collect Name, Gender, Role, Documents]                 │
 │                      │── Call callableFunction: 'registerUserProfile' ────────>│
 │                      │                                                         │── Validate fields
 │                      │                                                         │── Set Custom Claims
 │                      │                                                         │── Batch Write:
 │                      │                                                         │   /users/{uid}
 │                      │                                                         │   /riders or /drivers
 │                      │<── Success & Claims Updated ────────────────────────────│
 │                      │                                                         │
 │                      │── If Rider: Navigate to RiderHomeScreen                 │
 │                      │── If Driver: Navigate to DriverPendingApprovalScreen    │
```

### 4.3 Login Flow (NO SILENT CREATION)
```
LOGIN SEQUENCE:

User                Mobile App              Firebase Auth              Firestore
 │                      │                         │                        │
 │── Enter Phone No. ──>│                         │                        │
 │                      │── verifyPhoneNumber ───>│                        │
 │                      │<── Code Sent (SMS) ─────│                        │
 │── Enters OTP ───────>│── signInWithCredential ─│                        │
 │                      │<── UserCredential (UID) ┘                        │
 │                      │                                                  │
 │                      │── GET /users/{uid} ─────────────────────────────>│
 │                      │                                                  │
 │                      │─ CASE 1: Document NOT Found ────────────────────>│
 │                      │   ├── await FirebaseAuth.instance.signOut()      │
 │                      │   └── Show Error: "Account not registered.       │
 │                      │       Please complete sign-up first."            │
 │                      │                                                  │
 │                      │─ CASE 2: Document Found ────────────────────────>│
 │                      │   ├── Check user.is_active == true               │
 │                      │   ├── If Rider: Route to RiderHomeScreen         │
 │                      │   └── If Driver: Check /drivers/{uid}.status:    │
 │                      │       ├── 'pending'  -> DriverPendingScreen      │
 │                      │       ├── 'rejected' -> DriverRejectionScreen    │
 │                      │       └── 'approved' -> DriverRadarScreen        │
```

---

## 5. FIREBASE DATABASE DESIGN

### 5.1 Cloud Firestore Schema

#### 1. Collection: `users/{userId}`
Root profile containing core authentication and demographic information.
```json
{
  "uid": "USER_UID_STRING",
  "phone": "+201012345678",
  "full_name": "Kiro Medhat",
  "email": "kiro@example.com",
  "role": "rider", // "rider" | "driver" | "admin"
  "gender": "female", // "male" | "female"
  "gender_verified": true, // true only after KYC approval
  "language": "ar", // "en" | "ar"
  "is_active": true,
  "created_at": "TIMESTAMP",
  "updated_at": "TIMESTAMP"
}
```

#### 2. Collection: `riders/{riderId}`
Domain data specific to passengers.
```json
{
  "rider_id": "USER_UID_STRING",
  "rating_avg": 4.95,
  "total_rides": 24,
  "default_payment_method": "cash", // "cash" | "card" | "wallet"
  "emergency_contacts": [
    {
      "name": "Nabila Medhat",
      "phone": "+201001234567",
      "relationship": "Mother"
    }
  ],
  "created_at": "TIMESTAMP",
  "updated_at": "TIMESTAMP"
}
```

#### 3. Collection: `drivers/{driverId}`
Domain data specific to platform captains.
```json
{
  "driver_id": "USER_UID_STRING",
  "national_id_number": "29810140102468",
  "license_number": "LIC-9842104",
  "status": "pending", // "pending" | "approved" | "rejected" | "suspended"
  "rejection_reason": null,
  "is_online": false,
  "is_busy": false,
  "current_ride_id": null,
  "total_trips": 142,
  "wallet_balance_egp": 3450.00,
  "rating_avg": 4.92,
  "approved_by": "ADMIN_UID_STRING",
  "approved_at": "TIMESTAMP",
  "created_at": "TIMESTAMP",
  "updated_at": "TIMESTAMP"
}
```

#### 4. Collection: `vehicles/{driverId}`
Physical vehicle specifications linked 1:1 to driver.
```json
{
  "driver_id": "USER_UID_STRING",
  "make": "Toyota",
  "model": "Corolla",
  "year": 2022,
  "plate_number": "أ ب ج ١٢٣٤",
  "color": "Obsidian Black",
  "tier_eligibility": ["standard"], // ["standard"] or ["standard", "rafik_girl"]
  "created_at": "TIMESTAMP",
  "updated_at": "TIMESTAMP"
}
```

#### 5. Collection: `driver_documents/{driverId}/items/{docType}`
Document metadata tracking the 6 required KYC sides.
```json
{
  "doc_type": "national_id_front", // "national_id_front" | "national_id_back" | "license_front" | "license_back" | "vehicle_reg_front" | "vehicle_reg_back"
  "driver_id": "USER_UID_STRING",
  "storage_path": "driver_documents/USER_UID_STRING/national_id_front.jpg",
  "status": "pending", // "pending" | "approved" | "rejected"
  "rejection_reason": null,
  "uploaded_at": "TIMESTAMP",
  "reviewed_at": null,
  "reviewed_by": null
}
```

#### 6. Collection: `rides/{rideId}`
Primary ride contract and state machine.
```json
{
  "ride_id": "RIDE_AUTO_ID",
  "rider_id": "RIDER_UID_STRING",
  "rider_name": "Salma Hassan",
  "rider_phone": "+201098765432",
  "driver_id": "DRIVER_UID_STRING", // null while requested
  "driver_name": "Mariam Farouk",
  "driver_phone": "+201123456789",
  "vehicle_plate": "س ص ع ٩٨٧٦",
  "vehicle_model": "Nissan Sunny (Pearl Rose)",
  "tier": "rafik_girl", // "standard" | "rafik_girl"
  "status": "requested", // "requested" | "accepted" | "arrived" | "in_progress" | "completed" | "cancelled" | "expired"
  "pickup_address": "Cairo Festival City Mall, New Cairo",
  "pickup_lat": 30.0285,
  "pickup_lng": 31.4015,
  "dropoff_address": "Tahrir Square, Downtown Cairo",
  "dropoff_lat": 30.0444,
  "dropoff_lng": 31.2357,
  "distance_km": 24.50,
  "fare_egp": 260.00,
  "driver_earnings_egp": 260.00, // 0% platform commission promotional policy
  "platform_fee_egp": 0.00,
  "payment_method": "cash", // "cash" | "wallet" | "card"
  "attempts": 0, // Failed PIN attempts (locked at 3)
  "requested_at": "TIMESTAMP",
  "expires_at": "TIMESTAMP", // requested_at + 2 minutes
  "accepted_at": null,
  "arrived_at": null,
  "started_at": null,
  "completed_at": null,
  "cancelled_at": null,
  "cancelled_by": null, // "rider" | "driver" | "admin" | "system"
  "cancellation_reason": null,
  "rider_rating": null,
  "driver_rating": null,
  "review": null
}
```

#### 7. Subcollection: `rides/{rideId}/security/pin_data` (ISOLATED)
Security code isolated from the driver client.
```json
{
  "pin": "7429",
  "attempts": 0,
  "is_locked": false,
  "created_at": "TIMESTAMP"
}
```

#### 8. Subcollection: `rides/{rideId}/messages/{messageId}`
In-ride communication ledger.
```json
{
  "message_id": "MSG_AUTO_ID",
  "sender_id": "USER_UID_STRING",
  "sender_name": "Salma Hassan",
  "sender_role": "rider", // "rider" | "driver"
  "text": "I am standing next to Gate 4.",
  "created_at": "TIMESTAMP"
}
```

#### 9. Collection: `ride_offers/{offerId}`
Individual targeted dispatch offers presented to candidate captains.
```json
{
  "offer_id": "OFFER_AUTO_ID",
  "ride_id": "RIDE_AUTO_ID",
  "driver_id": "DRIVER_UID_STRING",
  "tier": "rafik_girl",
  "pickup_address": "Cairo Festival City Mall, New Cairo",
  "dropoff_address": "Tahrir Square, Downtown Cairo",
  "distance_km": 24.50,
  "fare_egp": 260.00,
  "status": "pending", // "pending" | "accepted" | "declined" | "expired" | "cancelled"
  "offered_at": "TIMESTAMP",
  "expires_at": "TIMESTAMP" // offered_at + 30 seconds
}
```

#### 10. Collection: `payments/{paymentId}`
Immutable platform financial transactions.
```json
{
  "payment_id": "PAY_AUTO_ID",
  "ride_id": "RIDE_AUTO_ID",
  "driver_id": "DRIVER_UID_STRING",
  "rider_id": "RIDER_UID_STRING",
  "amount_egp": 260.00,
  "kind": "trip_earnings", // "trip_earnings" | "cash_collection" | "payout" | "adjustment"
  "status": "settled",
  "created_at": "TIMESTAMP"
}
```

#### 11. Collection: `sos_events/{sosId}`
Emergency distress alerts.
```json
{
  "sos_id": "SOS_AUTO_ID",
  "user_id": "USER_UID_STRING",
  "ride_id": "RIDE_AUTO_ID",
  "caller_role": "rider", // "rider" | "driver"
  "lat": 30.0312,
  "lng": 31.3980,
  "status": "active", // "active" | "investigating" | "resolved"
  "notes": "Emergency alert triggered during active transit.",
  "resolved_by": null,
  "resolved_at": null,
  "created_at": "TIMESTAMP"
}
```

#### 12. Collection: `app_settings/global`
Dynamic platform configuration.
```json
{
  "base_fare_egp": 15.00,
  "per_km_rate_egp": 10.00,
  "min_fare_egp": 25.00,
  "initial_dispatch_radius_km": 3.0,
  "expanded_dispatch_radius_km": 5.0,
  "max_dispatch_radius_km": 7.0,
  "offer_ttl_seconds": 30,
  "ride_request_ttl_seconds": 120,
  "max_pin_attempts": 3,
  "rafik_girl_enabled": true
}
```

#### 13. Collection: `admin_users/{adminId}`
Authorized operations personnel.
```json
{
  "admin_id": "USER_UID_STRING",
  "email": "admin@rafik.app",
  "full_name": "Operations Commander",
  "permissions": ["manage_drivers", "manage_kyc", "manage_sos", "view_metrics", "superadmin"],
  "is_active": true,
  "created_at": "TIMESTAMP"
}
```

### 5.2 Firebase Realtime Database Structure

```json
{
  "driver_locations": {
    "DRIVER_UID_STRING": {
      "lat": 30.0444,
      "lng": 31.2357,
      "heading": 180.5,
      "speed_kmh": 32.0,
      "geohash": "w28t2x8",
      "tier": "standard", // "standard" | "rafik_girl"
      "gender": "female",
      "gender_verified": true,
      "is_online": true,
      "is_busy": false,
      "status": "approved",
      "updated_at": 1729864200000
    }
  },
  "driver_presence": {
    "DRIVER_UID_STRING": {
      "state": "online", // "online" | "offline"
      "last_seen": 1729864200000,
      "session_id": "sess_982341"
    }
  },
  "active_sessions": {
    "DRIVER_UID_STRING": {
      "fcm_token": "fcm_token_hash_here",
      "app_version": "1.0.0+1",
      "connected_at": 1729864000000
    }
  }
}
```

---

## 6. REAL-TIME DRIVER TRACKING DESIGN

### 6.1 RTDB vs. Firestore Evaluation
| Criterion | Cloud Firestore | Firebase Realtime Database | Decision |
|---|---|---|---|
| **Cost Model** | \$0.18 per 100,000 document writes | Billed exclusively on GB storage & network egress | **RTDB** (Zero write cost) |
| **Write Frequency** | Max 1 write/sec per document recommended | Thousands of updates/sec over persistent WebSocket | **RTDB** (High throughput) |
| **Latency** | 250ms – 600ms | Sub-100ms real-time wire protocol | **RTDB** (Smooth map movement) |
| **Connection Presence** | No native client disconnect primitives | Native `.info/connected` and `onDisconnect()` | **RTDB** (Reliable availability) |

### 6.2 Presence & Disconnect Architecture
When a captain goes online in the Flutter Driver app:
```dart
void configureDriverPresence(String driverId) {
  final presenceRef = FirebaseDatabase.instance.ref('driver_presence/$driverId');
  final locationRef = FirebaseDatabase.instance.ref('driver_locations/$driverId');
  final connectedRef = FirebaseDatabase.instance.ref('.info/connected');

  connectedRef.onValue.listen((event) {
    final connected = event.snapshot.value as bool? ?? false;
    if (connected) {
      // 1. Set onDisconnect handler
      presenceRef.onDisconnect().set({
        'state': 'offline',
        'last_seen': ServerValue.timestamp,
      });
      locationRef.onDisconnect().update({
        'is_online': false,
      });

      // 2. Mark online
      presenceRef.set({
        'state': 'online',
        'last_seen': ServerValue.timestamp,
      });
      locationRef.update({
        'is_online': true,
      });
    }
  });
}
```

---

## 7. RIDE DISPATCH ARCHITECTURE

### 7.1 Dispatch Lifecycle & Geofencing (3 KM Initial Radius)
The matching workflow enforces spatial, tier, and availability constraints:

```
MATCHING & DISPATCH WORKFLOW:

   Rider requests ride (Pick-up, Drop-off, Tier: 'rafik_girl' or 'standard')
                               │
                               ▼
            Cloud Function: onRideRequested Trigger
                               │
                               ▼
   ┌────────────────────────────────────────────────────────┐
   │ 1. Validate Caller Profile, Status & Tier Eligibility   │
   │ 2. Authoritative Fare Calculation:                      │
   │    fare = max(25.00, round(15.00 + km * 10.00, 2))     │
   │ 3. Generate Cryptographic 4-Digit PIN -> Store in       │
   │    /rides/{rideId}/security/pin_data (isolated)        │
   │ 4. Query RTDB /driver_locations:                        │
   │    • Distance <= 3.0 KM (Initial Matching Radius)       │
   │    • status == 'approved'                               │
   │    • is_online == true AND is_busy == false             │
   │    • Heartbeat freshness < 60 seconds                   │
   │    • If tier == 'rafik_girl':                           │
   │        gender == 'female' && gender_verified == true   │
   └───────────────────────────┬────────────────────────────┘
                               │
                Eligible Captains Found (Top 5 Ranked)
                               │
                               ▼
   ┌────────────────────────────────────────────────────────┐
   │ Create targeted /ride_offers/{offerId} for each driver │
   │ Status: 'pending', TTL: 30 seconds                     │
   │ Dispatch high-priority FCM data message to devices     │
   └───────────────────────────┬────────────────────────────┘
                               │
             ┌─────────────────┴─────────────────┐
             │                                   │
      Driver Accepts                     Offer Times Out
             │                           (30 seconds elapsed)
             ▼                                   │
┌───────────────────────────────┐                ▼
│ Firestore Transaction:        │      Are all 3 KM offers expired?
│ • Verify ride still requested │                │
│ • Assign driver to ride       │       YES ─────┴───── NO
│ • driver.is_busy = true       │        │               │
│ • Invalidate competing offers │        ▼               ▼
│ • FCM to Rider: "Assigned"    │  Expand Radius   Wait for other
└───────────────────────────────┘   to 5.0 KM      pending offers
                                         │
                                   Still none after 2 min?
                                         │
                                         ▼
                                   Expire Ride Request
                                   FCM to Rider: "No Captains"
```

### 7.2 Complete Ride Lifecycle State Machine

| Current State | Triggering Event | Actor | Target State | Security & Validation Rules |
|---|---|---|---|---|
| `[None]` | Rider submits booking | Rider | `requested` | Caller must be rider; no existing active ride; server computes fare & distance. |
| `requested` | Candidate captain accepts | Driver | `accepted` | Atomic transaction; first driver wins; competing offers cancelled; driver marked busy. |
| `requested` | 2 minutes timeout elapsed | Server | `expired` | Automatically executed by Cloud Function TTL cleaner when no captain accepts. |
| `accepted` | Rider cancels booking | Rider | `cancelled` | Allowed before arrival; frees assigned driver (`is_busy = false`). |
| `accepted` | Driver arrives at pickup | Driver | `arrived` | Driver GPS must be within 150m of pickup coordinates; rider receives arrival push. |
| `arrived` | Driver submits 4-digit PIN | Driver | `in_progress` | Server compares against isolated PIN document; locks after 3 failed attempts; sets `started_at`. |
| `arrived` | Driver cancels booking | Driver | `cancelled` | Driver must supply valid cancellation reason; frees ride and driver. |
| `in_progress`| Destination reached | Driver | `completed` | Credits driver wallet balance with 100% fare; creates immutable `/payments` record; frees driver. |

---

## 8. SECURITY STRATEGY

### 8.1 Firebase App Check
Firebase App Check will be enforced on all backend resources to reject requests originating from unverified clients, emulators, or automated bot scripts:
- **Android:** Play Integrity API (Hardware-backed attestation).
- **iOS:** Apple App Attest / DeviceCheck.
- **Web Admin Portal:** reCAPTCHA Enterprise / reCAPTCHA v3.

### 8.2 Firestore Security Rules (`firestore.rules`)
A comprehensive, zero-trust ruleset enforcing schema validation, immutable fields, role restrictions, and PIN privacy:

```javascript
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {

    // Default Deny
    match /{document=**} {
      allow read, write: if false;
    }

    // Helper Functions
    function isSignedIn() {
      return request.auth != null;
    }

    function isOwner(uid) {
      return isSignedIn() && request.auth.uid == uid;
    }

    function isAdmin() {
      return isSignedIn() && (
        request.auth.token.role == 'admin' ||
        request.auth.token.admin == true
      );
    }

    function isApprovedDriver() {
      return isSignedIn() && (
        request.auth.token.role == 'driver' &&
        request.auth.token.approved == true
      );
    }

    // 1. Users Collection
    match /users/{userId} {
      allow read: if isOwner(userId) || isAdmin();
      allow create: if isOwner(userId) &&
        request.resource.data.uid == userId &&
        request.resource.data.role in ['rider', 'driver'] &&
        request.resource.data.gender_verified == false &&
        request.resource.data.is_active == true;
      allow update: if (isOwner(userId) || isAdmin()) &&
        !request.resource.data.diff(resource.data).affectedKeys().hasAny([
          'uid', 'role', 'gender_verified', 'created_at'
        ]);
      allow delete: if isAdmin();
    }

    // 2. Riders Collection
    match /riders/{riderId} {
      allow read: if isOwner(riderId) || isAdmin();
      allow create, update: if isOwner(riderId) || isAdmin();
      allow delete: if isAdmin();
    }

    // 3. Drivers Collection
    match /drivers/{driverId} {
      allow read: if isSignedIn();
      allow create: if isOwner(driverId) &&
        request.resource.data.driver_id == driverId &&
        request.resource.data.status == 'pending' &&
        request.resource.data.wallet_balance_egp == 0.0 &&
        request.resource.data.total_trips == 0;
      allow update: if isAdmin() || (
        isOwner(driverId) &&
        isApprovedDriver() &&
        request.resource.data.diff(resource.data).affectedKeys().hasOnly([
          'is_online', 'is_busy', 'updated_at'
        ])
      );
      allow delete: if isAdmin();
    }

    // 4. Vehicles Collection
    match /vehicles/{driverId} {
      allow read: if isSignedIn();
      allow write: if isOwner(driverId) || isAdmin();
    }

    // 5. Driver Documents Collection
    match /driver_documents/{driverId}/items/{docType} {
      allow read: if isOwner(driverId) || isAdmin();
      allow write: if isOwner(driverId) || isAdmin();
    }

    // 6. Rides Collection
    match /rides/{rideId} {
      allow read: if isSignedIn() && (
        resource.data.rider_id == request.auth.uid ||
        resource.data.driver_id == request.auth.uid ||
        (resource.data.status == 'requested' && isApprovedDriver()) ||
        isAdmin()
      );
      // Client cannot write directly to rides; all transitions go through Cloud Functions
      allow create, update, delete: if isAdmin();

      // Messages Subcollection
      match /messages/{messageId} {
        allow read: if isSignedIn() && (
          get(/databases/$(database)/documents/rides/$(rideId)).data.rider_id == request.auth.uid ||
          get(/databases/$(database)/documents/rides/$(rideId)).data.driver_id == request.auth.uid ||
          isAdmin()
        );
        allow create: if isSignedIn() && (
          get(/databases/$(database)/documents/rides/$(rideId)).data.rider_id == request.auth.uid ||
          get(/databases/$(database)/documents/rides/$(rideId)).data.driver_id == request.auth.uid
        ) && request.resource.data.sender_id == request.auth.uid;
      }

      // Security PIN Data: NEVER accessible to driver
      match /security/pin_data {
        allow read: if isSignedIn() && (
          get(/databases/$(database)/documents/rides/$(rideId)).data.rider_id == request.auth.uid ||
          isAdmin()
        );
        allow write: if false; // Cloud Functions Admin SDK only
      }
    }

    // 7. Ride Offers Collection
    match /ride_offers/{offerId} {
      allow read: if isSignedIn() && (
        resource.data.driver_id == request.auth.uid ||
        isAdmin()
      );
      // Offers created & managed strictly by Cloud Functions
      allow write: if isAdmin();
    }

    // 8. Payments Collection
    match /payments/{paymentId} {
      allow read: if isSignedIn() && (
        resource.data.driver_id == request.auth.uid ||
        resource.data.rider_id == request.auth.uid ||
        isAdmin()
      );
      allow write: if false; // Server-authoritative ledger
    }

    // 9. SOS Events Collection
    match /sos_events/{sosId} {
      allow read: if isSignedIn() && (
        resource.data.user_id == request.auth.uid ||
        isAdmin()
      );
      allow create: if isSignedIn() && request.resource.data.user_id == request.auth.uid;
      allow update, delete: if isAdmin();
    }

    // 10. App Settings & Admin Users
    match /app_settings/{document=**} {
      allow read: if isSignedIn();
      allow write: if isAdmin();
    }

    match /admin_users/{adminId} {
      allow read, write: if isAdmin();
    }
  }
}
```

### 8.3 Realtime Database Security Rules (`database.rules.json`)
```json
{
  "rules": {
    ".read": false,
    ".write": false,
    "driver_locations": {
      ".read": "auth != null",
      "$driverId": {
        ".write": "auth != null && auth.uid === $driverId && auth.token.role === 'driver' && auth.token.approved === true",
        ".validate": "newData.hasChildren(['lat', 'lng', 'updated_at']) && newData.child('lat').isNumber() && newData.child('lng').isNumber()"
      }
    },
    "driver_presence": {
      "$driverId": {
        ".read": "auth != null",
        ".write": "auth != null && auth.uid === $driverId"
      }
    },
    "active_sessions": {
      "$driverId": {
        ".read": "auth != null && (auth.uid === $driverId || auth.token.role === 'admin')",
        ".write": "auth != null && auth.uid === $driverId"
      }
    }
  }
}
```

### 8.4 Firebase Storage Security Rules (`storage.rules`)
```javascript
rules_version = '2';
service firebase.storage {
  match /b/{bucket}/o {

    function isSignedIn() {
      return request.auth != null;
    }

    function isAdmin() {
      return isSignedIn() && request.auth.token.role == 'admin';
    }

    // Private Driver KYC Documents
    match /driver_documents/{driverId}/{allPaths=**} {
      allow read: if isSignedIn() && (request.auth.uid == driverId || isAdmin());
      allow write: if isSignedIn() && request.auth.uid == driverId
        && request.resource.size < 5 * 1024 * 1024
        && request.resource.contentType.matches('image/(jpeg|png|webp)');
    }

    // Private Rider Identity Proofs (Rafik Girl)
    match /identity_verifications/{userId}/{allPaths=**} {
      allow read: if isSignedIn() && (request.auth.uid == userId || isAdmin());
      allow write: if isSignedIn() && request.auth.uid == userId
        && request.resource.size < 5 * 1024 * 1024
        && request.resource.contentType.matches('image/(jpeg|png|webp)');
    }

    // User Public Avatars
    match /avatars/{userId}/{fileName} {
      allow read: if isSignedIn();
      allow write: if isSignedIn() && request.auth.uid == userId
        && request.resource.size < 2 * 1024 * 1024
        && request.resource.contentType.matches('image/(jpeg|png)');
    }
  }
}
```

---

## 9. REQUIRED FIREBASE CONFIGURATION

### 9.1 Active Firebase Project
- **Project Name:** Rafik
- **Project ID:** `rafik-98844`
- **Project Number:** `933541427773`
- **Storage Bucket:** `rafik-98844.firebasestorage.app`
- **Default Cloud Region:** `europe-west3` (Frankfurt) or `europe-west1` (Belgium) for lowest latency to Cairo.

### 9.2 Console Configuration Checklist
1. **Authentication:**
   - Enable Phone Authentication.
   - Configure SMS delivery quotas and test phone numbers (e.g., `+201000000001` with static OTP `123456` strictly for automated test suites).
   - Configure reCAPTCHA verification for Web Admin and Android SafetyNet/Play Integrity fallback.
2. **Cloud Firestore:**
   - Create production database in Native mode.
   - Apply `firestore.rules` and `firestore.indexes.json`.
3. **Realtime Database:**
   - Initialize instance in `europe-west1`.
   - Apply `database.rules.json`.
4. **Cloud Storage:**
   - Ensure default bucket is provisioned.
   - Apply `storage.rules`.
5. **Firebase Cloud Messaging:**
   - Generate Web Push Certificates (VAPID key) for Admin Portal notifications.
   - Download updated `google-services.json` containing FCM client configuration.
6. **Cloud Functions:**
   - Initialize Firebase CLI in `/functions` targeting Node.js 20 / TypeScript.

---

## 10. PACKAGE DEPENDENCY CHANGES

### 10.1 Mobile App (`mobile_app/pubspec.yaml`)

```diff
 dependencies:
   flutter:
     sdk: flutter
   cupertino_icons: ^1.0.8
   firebase_core: ^3.6.0
   firebase_auth: ^5.3.1
   cloud_firestore: ^5.4.4
   firebase_storage: ^12.3.2
+  firebase_database: ^11.1.4
+  firebase_messaging: ^15.1.3
+  flutter_local_notifications: ^17.2.2
-  supabase_flutter: ^2.8.3
   google_sign_in: ^6.2.2
   flutter_svg: ^2.0.17
   google_fonts: ^6.2.1
   latlong2: ^0.9.1
   flutter_map: ^7.0.2
   geolocator: ^13.0.2
   shared_preferences: ^2.3.5
   url_launcher: ^6.3.1
   image_picker: ^1.2.3
   google_mlkit_text_recognition: ^0.17.1
   google_mlkit_face_detection: ^0.15.1
```

### 10.2 Admin Portal (`admin_portal/index.html`)

```diff
- <script src="https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2.49.1/dist/umd/supabase.min.js"></script>
  <script src="https://www.gstatic.com/firebasejs/10.12.2/firebase-app-compat.js"></script>
  <script src="https://www.gstatic.com/firebasejs/10.12.2/firebase-auth-compat.js"></script>
  <script src="https://www.gstatic.com/firebasejs/10.12.2/firebase-firestore-compat.js"></script>
+ <script src="https://www.gstatic.com/firebasejs/10.12.2/firebase-database-compat.js"></script>
+ <script src="https://www.gstatic.com/firebasejs/10.12.2/firebase-storage-compat.js"></script>
+ <script src="https://www.gstatic.com/firebasejs/10.12.2/firebase-messaging-compat.js"></script>
```

### 10.3 Cloud Functions (`functions/package.json`) [NEW]
```json
{
  "name": "rafik-backend-functions",
  "version": "1.0.0",
  "description": "Trusted serverless backend operations for Rafik platform",
  "main": "lib/index.js",
  "engines": {
    "node": "20"
  },
  "dependencies": {
    "firebase-admin": "^12.6.0",
    "firebase-functions": "^6.0.1",
    "geofire-common": "^6.0.0"
  },
  "devDependencies": {
    "typescript": "^5.5.4"
  }
}
```

---

## 11. FILE-BY-FILE MIGRATION PLAN

| File Path | Current State | Required Modification |
|---|---|---|
| `mobile_app/pubspec.yaml` | Imports `supabase_flutter`, missing RTDB & FCM | Remove `supabase_flutter`. Add `firebase_database`, `firebase_messaging`, `flutter_local_notifications`. |
| `mobile_app/lib/core/services/supabase_service.dart` | Dual-bridged Frankenstein wrapper | **Delete completely**. All calls redirected to native `FirebaseService`. |
| `mobile_app/lib/core/services/firebase_service.dart` | Fake email/pass auth, direct Firestore writes | Refactor to pure Phone Auth OTP, Cloud Functions dispatch calls, and RTDB telemetry. |
| `mobile_app/lib/core/services/persistent_storage.dart` | Reads `Supabase.instance.client.auth` | Switch session checks to `FirebaseAuth.instance.currentUser`. Remove Supabase signout. |
| `mobile_app/lib/features/auth/auth_screen.dart` | Username/Mobile + Password forms | Replace with E.164 Egyptian Phone input, trigger Firebase Phone Auth OTP, separate login vs. registration. |
| `mobile_app/lib/features/auth/otp_verification_sheet.dart` | Supabase OTP with committee bypass | Switch to `PhoneAuthProvider.credential`, verify with `FirebaseAuth`, enforce 60s cooldown timer. |
| `mobile_app/lib/main_rider.dart` | Listens to auth state, routes blindly | Validate `/users/{uid}.role == 'rider'` before navigating to `RiderHomeScreen`. |
| `mobile_app/lib/main_driver.dart` | Routes any authenticated user to radar | Validate `/users/{uid}.role == 'driver'` and `/drivers/{uid}.status == 'approved'`. Route pending/rejected accordingly. |
| `mobile_app/lib/main.dart` | Duplicate entrypoint with old "Go Safe" name | Standardize branding to Rafik or remove in favor of flavors. |
| `mobile_app/lib/features/driver/driver_onboarding_screen.dart` | Calls dummy document upload | Upload actual picked files to Firebase Storage (`driver_documents/{uid}/{docType}.jpg`). |
| `mobile_app/lib/features/driver/driver_radar_screen.dart` | Global Firestore ride stream, leaked PIN | Listen to `/ride_offers` for driver UID. Stream location to RTDB. Remove PIN exposure. |
| `mobile_app/lib/features/driver/driver_wallet_screen.dart` | Calls SupabaseService | Fetch transactions from Firestore `/payments` and driver balance from `/drivers/{uid}`. |
| `mobile_app/lib/features/rider/rider_home_screen.dart` | Dual Firestore & Supabase listeners | Stream ride from `/rides/{rideId}` and driver location from RTDB `/driver_locations/{driverId}`. |
| `mobile_app/lib/features/rider/trip_history_screen.dart` | Hardcoded fallback mock trips | Query Firestore `/rides` where `rider_id == currentUser.uid`. Remove dummy trips list. |
| `mobile_app/lib/features/rider/safety_shield_sheet.dart` | Hardcoded default contacts | Read & write emergency contacts to `/riders/{uid}/emergency_contacts`. |
| `mobile_app/lib/features/rider/rating_dialog.dart` | Hardcoded mock submission | Submit rating to Cloud Function `rateRide`. Update driver running average atomically. |
| `mobile_app/lib/features/chat/in_ride_chat_sheet.dart` | Dual listeners | Stream chat messages from `/rides/{rideId}/messages`. |
| `admin_portal/index.html` | Hardcoded Supabase RPC calls | Port all queries, mutations, signed URL previews, and real-time feeds to Firebase JS SDK. |
| `admin_portal/config.js` | Contains Supabase credentials | Remove Supabase keys; retain pure Firebase config. |
| `firestore.rules` | Partial rules draft | Replace with the hardened zero-trust rules specified in Section 8.2. |
| `database.rules.json` | Non-existent | Create RTDB rules file securing `/driver_locations` and `/driver_presence`. |
| `storage.rules` | Non-existent | Create Storage rules file securing private KYC buckets. |
| `functions/src/index.ts` | Non-existent | Implement Cloud Functions: `requestRide`, `acceptRide`, `startRide`, `completeRide`, `adminReviewDriver`, `expireStaleOffers`. |

---

## 12. TESTING STRATEGY

### 12.1 Security Rules Unit Testing
Run automated unit tests using `@firebase/rules-unit-testing`:
- **Test S-01:** Unauthenticated read/write to any collection is denied.
- **Test S-02:** Driver cannot read `/rides/{rideId}/security/pin_data`.
- **Test S-03:** Driver cannot modify `status`, `wallet_balance_egp`, or `rating_avg` in `/drivers/{uid}`.
- **Test S-04:** Unapproved driver (`status: 'pending'`) cannot write coordinates to RTDB `/driver_locations`.
- **Test S-05:** Rider cannot book Rafik Girl tier without `gender_verified: true`.
- **Test S-06:** Non-admin cannot upload or inspect other users' KYC document files.

### 12.2 Integration Test Matrix
1. **Authentication:**
   - Input valid Egyptian mobile (`01012345678`) $\rightarrow$ verify E.164 format `+201012345678`.
   - Complete OTP verification on unregistered number during login $\rightarrow$ verify immediate sign-out and error prompt (no silent creation).
   - Complete Driver registration $\rightarrow$ verify `/drivers/{uid}.status == 'pending'` and user is locked on `DriverPendingScreen`.
2. **Dispatch & Radius Matching:**
   - Place rider at AUC New Cairo (`30.0131, 31.4989`).
   - Place Driver A 1.8 KM away (eligible) and Driver B 4.2 KM away (outside 3 KM radius).
   - Request ride $\rightarrow$ verify Driver A receives `/ride_offers` and Driver B receives nothing.
   - Allow Driver A offer to expire (30s) $\rightarrow$ verify radius expands to 5 KM $\rightarrow$ Driver B receives offer.
3. **Atomic Concurrency:**
   - Simulate two drivers clicking "Accept" simultaneously on the same ride offer.
   - Verify transaction commits for the first driver and returns structured `RIDE_ALREADY_ACCEPTED` for the second driver.
4. **Safety Handshake:**
   - Driver attempts to start trip with incorrect PIN $\rightarrow$ verify counter increments to 1, then 2.
   - Driver inputs 3rd incorrect PIN $\rightarrow$ verify trip enters `pin_locked` state; subsequent attempts fail.
   - Driver enters correct PIN $\rightarrow$ verify trip transitions to `in_progress`.

---

## 13. DEPLOYMENT INSTRUCTIONS

### 13.1 CLI Prerequisites
```powershell
npm install -g firebase-tools
firebase login
firebase use rafik-98844
```

### 13.2 Rules, Indexes & Cloud Functions Deployment
```powershell
# 1. Deploy Security Rules & Indexes
firebase deploy --only firestore:rules,firestore:indexes,database,storage

# 2. Deploy Cloud Functions Backend
cd functions
npm install
npm run build
firebase deploy --only functions
```

### 13.3 Mobile Applications Build
```powershell
cd mobile_app

# 1. Clean and update dependencies
flutter clean
flutter pub get

# 2. Build Rider APK
flutter build apk --flavor rider -t lib/main_rider.dart --release

# 3. Build Driver APK
flutter build apk --flavor driver -t lib/main_driver.dart --release
```

### 13.4 Admin Operations Portal Deployment
```powershell
# Deploy Static Web Dashboard to Firebase Hosting
firebase deploy --only hosting
```

---

## 14. POTENTIAL BREAKING CHANGES & MITIGATIONS

| Risk / Breaking Change | Severity | Impact | Mitigation Strategy |
|---|---|---|---|
| **Removal of Fake Password Auth** | High | Users accustomed to typing username/password cannot log in directly. | Present clean, friendly phone input sheet explaining one-time SMS verification. |
| **Enforcement of Driver Approval Gate** | Critical | Previously registered unvetted drivers will be locked out of the radar. | Display clear status badge: "Application Pending Safety Team Review" with support hotline. |
| **RTDB Protocol Change** | High | Driver telemetry switches from HTTP/Firestore to WebSockets. | Provide background location service handling reconnects and battery optimization. |
| **PIN Privacy Isolation** | Medium | Drivers who relied on seeing the PIN on their own screen must now ask the rider. | Display prominent UI banner on driver screen: "Ask passenger for 4-digit safety code upon boarding." |
| **Zero Platform Commission Lock** | Low | Financial accounting must track 100% fare credit to driver wallet. | Automated Firestore ledger writes full fare to driver wallet balance and zero platform deduction. |

---

## IMPLEMENTATION SEQUENCE (PHASE 2 ROADMAP)

The implementation must proceed in strictly segregated, independently testable phases:

```
IMPLEMENTATION ROADMAP:

[PHASE 2A: INFRASTRUCTURE & BACKEND CLOUD FUNCTIONS]
  ├── Provision Cloud Functions (v2) in TypeScript
  ├── Deploy Security Rules (Firestore, RTDB, Storage)
  └── Implement Server-Authoritative Ride Dispatch & Fare Engine
              │
              ▼
[PHASE 2B: AUTHENTICATION & KYC ONBOARDING]
  ├── Port Flutter apps to Pure Phone Auth (E.164 Normalization + SMS OTP)
  ├── Enforce Strict Login vs. Registration (No Silent User Creation)
  ├── Wire 6-Sided Document Uploads to Firebase Storage
  └── Implement Driver Approval Gate & Session Restoration
              │
              ▼
[PHASE 2C: REAL-TIME TELEMETRY & DRIVER PRESENCE]
  ├── Implement Realtime Database Driver GPS Telemetry (3-5s throttled)
  └── Configure Native Presence (.info/connected + onDisconnect)
              │
              ▼
[PHASE 2D: DISPATCH WORKFLOW & SAFETY HANDSHAKE]
  ├── Connect 3 KM Matching Engine with Server-Sent Offers
  ├── Wire FCM Background Wakeup Notifications
  ├── Implement Atomic Accept Transaction & Offer Expiration
  └── Implement Isolated 4-Digit PIN Handshake Verification
              │
              ▼
[PHASE 2E: WEB ADMIN OPERATIONS PORTAL MIGRATION]
  ├── Port Admin Portal from Supabase RPCs to Firebase JS SDK v10
  ├── Wire Driver KYC Review Queue (Storage Signed URLs + Approval Mutation)
  ├── Wire Real-Time Fleet Map to RTDB /driver_locations
  └── Wire SOS Alert Dispatch Center
              │
              ▼
[PHASE 2F: DEPENDENCY PURGE & CLEANUP]
  ├── Remove supabase_flutter and delete SupabaseService.dart
  ├── Remove all mock fallbacks, demo codes, and test accounts
  └── Verify Zero Supabase References Across Repository
              │
              ▼
[PHASE 2G: END-TO-END VERIFICATION & USER ACCEPTANCE TESTING]
```

> **AWAITING USER APPROVAL:**  
> This concludes Phase 1. No application code has been modified or destroyed. Awaiting confirmation before initiating Phase 2A.
