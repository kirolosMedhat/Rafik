# Rafik (رَفِيق) — Next-Generation Ride-Hailing Platform

[![Platform](https://img.shields.io/badge/Platform-Flutter%20%7C%20Firebase-orange.svg)](https://flutter.dev)
[![Backend](https://img.shields.io/badge/Backend-Firebase%20Cloud%20Functions%20v2-yellow.svg)](https://firebase.google.com)
[![Status](https://img.shields.io/badge/Status-Production%20Hardened-success.svg)]()
[![Security](https://img.shields.io/badge/Security-Server--Authoritative%20Dispatch-emerald.svg)]()
[![Copyright](https://img.shields.io/badge/Copyright-Rafik%202026-rose.svg)]()

> **All rights reserved to Rafik 2026.**  
> *Rafik (رَفِيق)* is an enterprise-grade Egyptian ride-hailing ecosystem built on a server-authoritative **Firebase Cloud Architecture** (Firebase Auth, Cloud Firestore, Realtime Database, Cloud Functions v2, Firebase Storage, and Firebase Cloud Messaging). It features a dual-tier service model: **Rafik Standard** and the dedicated **Rafik Girl** women-centric safety network.

---

## 🌟 Platform Overview

Rafik is designed specifically for Greater Cairo’s transit dynamics, addressing passenger safety, fair driver compensation, and high-frequency dispatch across Cairo, Giza, New Cairo (Tagamoa - AUC), Sheikh Zayed, Zamalek, and Heliopolis.

### 🚗 Dual-Tier Service Tiers
1. **Rafik Standard (رَفِيق ستاندرد)**
   - Open to all passengers and certified Egyptian captains.
   - **Signature Visual Identity:** Sleek Jet Black (`#000000`) and Titanium Ice Blue (`#3B82F6`) palette.
   - Fair and transparent Cairo pricing with 0% platform commission on promotional trips.
2. **Rafik Girl (رَفِيق جيرل)**
   - A dedicated, secure ride-hailing option exclusively pairing verified female passengers with verified female captains.
   - **Signature Visual Identity:** Obsidian Berry (`#12080C`) and Egyptian Rose Gold (`#B76E79`) luxury theme.
   - Enhanced security features, automatic route monitoring, 13th-digit National ID validation, and manual admin verification.

---

## 🏛️ 100% Firebase Cloud Architecture

Rafik operates with **server-authoritative Cloud Functions v2** and strict security rules. All business logic, fare calculations, atomic driver acceptance races, and safety handshakes are validated and enforced on the server.

```
┌─────────────────────────────────┐       ┌─────────────────────────────────┐
│     Rafik Rider App (Flutter)   │       │    Rafik Driver App (Flutter)   │
│   (Flavored: com.rafik.rider)   │       │   (Flavored: com.rafik.driver)  │
└────────────────┬────────────────┘       └────────────────┬────────────────┘
                 │                                         │
                 │         HTTPS / WebSocket (Firebase SDK)│
                 └───────────────────┬─────────────────────┘
                                     │
                    ┌────────────────┴─────────────────┐
                    │      Firebase Cloud Platform     │
                    ├──────────────────────────────────┤
                    │  • Firebase Phone Auth (SMS OTP) │
                    │  • Cloud Functions v2 (Node 20)  │
                    │  • Cloud Firestore (Standard)    │
                    │  • Realtime Database (Telemetry) │
                    │  • Firebase Storage (KYC Vault)  │
                    │  • Cloud Messaging (FCM Alerts)  │
                    └────────────────┬─────────────────┘
                                     │
                    ┌────────────────┴─────────────────┐
                    │    Admin Operations Portal       │
                    │  Static Web App (Vercel/Netlify) │
                    │  Firebase Compat SDK • KYC Queue │
                    └──────────────────────────────────┘
```

- **Authentication:** Firebase Phone Authentication with E.164 SMS OTP (`+201XXXXXXXXX`). Direct phone verification with automatic Firestore `/users/{uid}` profile creation.
- **Server-Authoritative Cloud Functions:**
  - `executeRequestRide`: Validates rider role, geofence, and calculates dynamic upfront fare.
  - `executeAcceptRide`: Uses Firestore transactions to guarantee that only one captain wins concurrent ride acceptance races.
  - `executeMarkArrived`: Enforces 200m GPS arrival radius.
  - `executeVerifyPinAndStartTrip`: Validates 4-digit safety PIN with 3-strike lockout and zero master bypass.
  - `executeCompleteRide`: Finalizes ride and credits driver wallet server-side.
  - `executeCancelRide`: Restores captain availability immediately.
  - `executeRateRide`: Updates rolling average ratings atomically.
- **Realtime Telemetry & Presence:** Firebase Realtime Database with ServerValue.timestamp heartbeat and dual-mode GPS battery optimization (3s moving / 10s stationary). Stale telemetry (>60s) is automatically excluded from dispatch.
- **Driver Data Privacy:** Sensitive driver records (`/drivers/{driverId}`) containing National ID and license numbers are restricted to the driver owner and authorized administrators. Riders access safe public projections via `/public_drivers/{driverId}`.
- **KYC Document Vault:** Driver KYC uploads (6-sided inspection) are stored in private Firebase Storage buckets (`kyc/{driverId}/...`) with 5MB limits and MIME whitelisting.

---

## 📐 Cairo Fare Formula

$$\text{Fare (EGP)} = \max\Big(25.00,\, 15.00 + (\text{Distance in km} \times 10.00)\Big)$$

- **Base Pickup Fare:** 15.00 EGP
- **Per Kilometer Rate:** 10.00 EGP
- **Minimum Trip Fare:** 25.00 EGP
- **Cairo Traffic Multiplier:** 1.25x road distance approximation
- **Rafik Girl Multiplier:** 1.10x
- **Platform Commission:** 0.00 EGP (100% earnings to captains)

---

## 🛠️ Getting Started

### Prerequisites
- [Flutter SDK](https://flutter.dev/) (v3.24+)
- [Node.js](https://nodejs.org/) (v18+)
- [Java Development Kit](https://openjdk.org/) (JDK 17+)
- Android Studio / Android SDK (API 34+)

---

### 1. Backend & Cloud Functions Setup (`functions/`)

1. **Install Dependencies:**
   ```bash
   cd functions
   npm install
   ```

2. **Build TypeScript:**
   ```bash
   npm run build
   ```

3. **Run Real Emulator Suite:**
   The test suite runs against the real Firebase Firestore and Realtime Database emulators using `@firebase/rules-unit-testing`:
   ```bash
   npm test
   ```

---

### 2. Mobile App Setup (`mobile_app/`)

1. **Install Dependencies:**
   ```bash
   cd mobile_app
   flutter pub get
   ```

2. **Configure Environment:**
   Firebase credentials are configured in `mobile_app/lib/firebase_options.dart` and `mobile_app/android/app/google-services.json`.

3. **Run Rider App:**
   ```bash
   flutter run --flavor rider -t lib/main_rider.dart
   ```

4. **Run Driver App:**
   ```bash
   flutter run --flavor driver -t lib/main_driver.dart
   ```

5. **Build Production Release APK:**
   Release APKs require a release keystore configured in `mobile_app/android/key.properties`:
   ```bash
   flutter build apk --release
   ```

---

### 3. Admin Operations Portal (`admin_portal/`)

The Admin Operations Portal is a static web application powered by the Firebase SDK.

1. **Configure Environment:**
   Copy the example configuration file:
   ```bash
   cd admin_portal
   cp config.example.js config.js
   ```
   Populate `config.js` with your Firebase project configuration:
   ```javascript
   window.RAFIK_CONFIG = {
     FIREBASE_CONFIG: {
       apiKey: "YOUR_API_KEY",
       authDomain: "rafik-98844.firebaseapp.com",
       projectId: "rafik-98844",
       storageBucket: "rafik-98844.firebasestorage.app",
       messagingSenderId: "123456789012",
       appId: "1:123456789012:web:abcdef123456",
       databaseURL: "https://rafik-98844-default-rtdb.firebaseio.com"
     }
   };
   ```

2. **Admin Claim Provisioning:**
   Administrator accounts authenticate via Firebase Authentication with the custom claim `{ role: 'admin' }` or Firestore user profile `{ role: 'admin' }`:
   ```javascript
   // Via Firebase Admin SDK:
   await admin.auth().setCustomUserClaims(adminUid, { role: 'admin' });
   ```

3. **Run Locally:**
   Open `admin_portal/index.html` using any local HTTP server:
   ```bash
   npx serve admin_portal
   ```

---

## 📁 Repository Structure & Legacy Artifacts Notice

```
.
├── admin_portal/       # Static Operations & KYC Verification Portal
├── docs/               # Architecture diagrams, specifications, and project book
├── functions/          # Firebase Cloud Functions (TypeScript backend)
│   ├── src/            # Rides, dispatch, spatial, pricing, and triggers
│   └── test/           # Real Emulator test suite & backend unit tests
├── mobile_app/         # Unified Flutter Application (Rider & Driver Flavors)
│   ├── android/        # Android platform configuration & signing configs
│   ├── lib/            # Clean architecture Flutter presentation & logic
│   └── test/           # Dart unit tests (Auth, Telemetry, Ride Lifecycle)
├── database.rules.json # Realtime Database Security Rules
├── firestore.rules     # Cloud Firestore Security Rules
├── storage.rules       # Firebase Storage Security Rules
└── supabase/           # [HISTORICAL AUDIT ARCHIVE] Intentionally retained
```

> [!NOTE]
> The `/supabase` directory is intentionally retained in the repository solely as a historical reference and audit trail from Phase 1. The active production system is 100% powered by Firebase Cloud Services.

---

## 🔒 Security Best Practices

1. **Zero Client Authority:** All fares, driver assignments, ride status transitions, and wallet updates are executed strictly by Cloud Functions.
2. **National ID Algorithm:** The 13th digit of Egyptian National IDs is validated cryptographically (`odd = male`, `even = female`) to enforce safety parity on the Rafik Girl tier.
3. **Trip PIN Handshake:** PINs are stored in `/rides/{rideId}/security/pin_data`, which is blocked from driver reads. Drivers verify PINs exclusively through `executeVerifyPinAndStartTrip`.
4. **Driver Data Privacy:** National ID and license numbers in `/drivers/{driverId}` are shielded from riders; only public profile projections are exposed.
5. **Real-time Distress Protocol (SOS):** Emergency alerts immediately update Firestore and launch native phone dialing to Egyptian Police (`122`).

---

## 📄 License & Copyright

All rights reserved © 2026 **Rafik (رَفِيق)**.  
Unauthorized copying, reverse engineering, or redistribution of this software is strictly prohibited.
