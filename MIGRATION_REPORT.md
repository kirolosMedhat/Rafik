# Rafik (رَفِيق) — Full Supabase Migration, Security Hardening & Architecture Report

**Project:** Rafik Cairo Ride-Hailing Platform  
**Target Branch:** `supabase-migration`  
**Repository:** `github.com/kirolosMedhat/Rafik`  
**Date:** October 2026  
**Status:** COMPLETE & VERIFIED  

---

## 1. Executive Summary & Architectural Paradigm Shift

The Rafik platform has completed an end-to-end migration from an insecure, single-point-of-failure Node.js/Express server relying on a local JSON file (`database.json`), Socket.IO broadcasts, and hardcoded LAN/localhost IPs (`192.168.1.13:5000`) to an enterprise-grade, serverless **Pure Supabase Cloud Architecture**.

### Key Architectural Transformations:
1. **Decommissioned Intermediate Node Server:** The entire `backend/` directory, including Express routing, Socket.IO connections, local disk JSON database, and hardcoded localhost listeners, has been completely eliminated.
2. **Database-Driven Security:** All operational logic, fare calculations, and state machines are enforced at the database layer via **PostgreSQL 15**, **PostGIS**, **Row Level Security (RLS)**, and 16 **`SECURITY DEFINER` RPCs**. Direct table mutations (`INSERT`, `UPDATE`, `DELETE`) on operational tables are revoked from client roles (`anon` and `authenticated`).
3. **Realtime Engine:** Custom Socket.IO event channels were replaced with Supabase Realtime `postgres_changes` subscriptions filtered by user ID and constrained by RLS.
4. **Zero Secrets in Clients:** Neither the mobile apps nor the static admin portal contain database passwords, private keys, or `service_role` secrets. Authentication uses standard Supabase Auth with publishable anon keys injected at build time.
5. **Private KYC & Document Vault:** Captain verification documents and passenger national ID photos are stored in private Supabase Storage buckets, inspectable only by authorized administrators through short-lived (60-second) signed URLs.

---

## 2. Verified Findings Resolution Matrix (F1 through F20)

| ID | Severity | Category | Original Vulnerability / Broken Flow | Resolution & Verification |
| :--- | :--- | :--- | :--- | :--- |
| **F1** | Critical | Auth | `/api/login` authenticated anyone by phone alone and automatically created female rider profiles for unknown numbers. | Replaced with native Supabase Auth (`signInWithOtp`, `verifyOTP`, `signInWithOAuth`, `signInWithPassword`). Profiles are created strictly via the `handle_new_user` PostgreSQL trigger. |
| **F2** | Critical | Auth / Safety | OTP accepted any 4 digits ("Committee Demo Bypass" accepting `1234`), plus a 1-tap "Instant Bypass" button. | Removed insecure UI bypasses in release modes. OTP verification delegates exclusively to `supabase.auth.verifyOTP`. Debug bypass is restricted to `kDebugMode` targeting seeded test credentials. |
| **F3** | Critical | Rafik Girl Safety | Gender was self-declared without validation (`genderVerified = gender === 'female'`), allowing any user to enter Rafik Girl. | Enforced 13th-digit parity verification on Egyptian National IDs (`odd = male`, `even = female`). Riders must upload government ID and selfie; access to Rafik Girl tier is locked until `gender_verified = true` is approved by an administrator. |
| **F4** | Critical | Authorization | No authentication or authorization on sensitive endpoints (`/api/database/records`, `/api/drivers`, `PUT /api/drivers/:id/status`, `POST /api/admin/reset`). CORS set to `*`. | Endpoints eliminated. Tables protected by RLS; captain approvals handled via `admin_review_driver` RPC requiring `is_admin()` validation. Reset endpoint removed. |
| **F5** | Critical | Data Privacy | RLS on `profiles` and `drivers` allowed world-readable access (exposing phones and national IDs). Users could edit their own `role` and `gender_verified`. | Strict RLS applied: users read only own row or active ride counterparties (with masked phones). `protect_profile` trigger rejects client modifications to `role`, `gender_verified`, and `rating_avg`. |
| **F6** | Critical | Storage Privacy | `driver-documents` storage bucket was public (`public = true`), making KYC images world-readable. Document status defaulted to `'approved'`. | Storage buckets `driver-documents` and `identity-documents` set to private (`public = false`). Document status defaults to `'pending'`. Documents are accessed only via short-lived signed URLs. |
| **F7** | Critical | Ride Safety | Handshake PIN was hardcoded to `'7429'` on the client; backend accepted master PIN `1234`. No attempt limits existed. | PINs are generated cryptographically on the database (`gen_random_bytes(3)`) and stored in a separate `ride_pins` table hidden from drivers. `start_ride` RPC enforces a strict 3-attempt lockout without rollback. Master PIN eliminated. |
| **F8** | High | Schema Integrity | App and database column names disagreed (`fare_amount` vs `fare_egp`, `pin_code`, missing `driver_earnings_egp`, `drivers.id` vs `user_id`), causing silent write failures. | Unified schema: all Dart models, RPC calls, and SQL tables share identical column names and non-null constraints. All silent `catch -> debugPrint` blocks replaced with structured error handling. |
| **F9** | High | Identity | User IDs were simulated strings (`usr-<timestamp>`, `demo-rider-...`). The app never signed into Supabase Auth, breaking RLS policies. | Client authenticates through Supabase Auth, establishing genuine UUIDs matching `auth.uid()`. All RLS policies successfully resolve caller identity. |
| **F10** | High | KYC Verification | KYC images were never uploaded; admin portal rendered hardcoded Unsplash stock photos. Registration fabricated national IDs and plates. | Drivers upload 6 authentic document images to private storage. Admin portal dynamically requests 60-second signed URLs to render authentic driver submissions. |
| **F11** | High | Map & Tracking | Driver movements on rider maps were simulated with local timers (`_startDriverMovementSimulation`). A 12-second local fallback fabricated driver acceptance. | Removed all simulation timers and local fallbacks. Rider map subscribes directly to `driver_locations` table changes via Supabase Realtime. When a ride expires without acceptance, a clear "No captains nearby" state is shown. |
| **F12** | High | Dispatch / Concurrency | Dispatch was broadcast indiscriminately. Concurrent `accept` requests allowed multiple drivers to claim the same ride. | `request_ride` matches up to 10 qualified drivers within 5 km using PostGIS spatial queries. `accept_ride` uses atomic row locking with state validation; second captain receives graceful `ride_unavailable`. |
| **F13** | High | Financial Integrity | Ride fare was computed on the mobile client and trusted by the server. | Fare computation moved entirely to database RPC `compute_fare(km)`. Server calculates and writes `fare_egp` and `driver_earnings_egp`. Client displays fare only as an informational preview. |
| **F14** | High | Network / Architecture | Hardcoded LAN IP `http://192.168.1.13:5000` and `localhost:5000` embedded in mobile app, admin portal, and scripts. | Eliminated all localhost/LAN references. Configuration is supplied via `--dart-define-from-file=env/dev.json` in Flutter and `config.js` in Admin Portal. Grep verification confirms 0 occurrences across active code. |
| **F15** | Medium | Android Security | `usesCleartextTraffic="true"`, release signed with debug keys, and code minification disabled. | Enforced HTTPS-only via `network_security_config.xml`. Configured release signing template with `key.properties`. Enabled ProGuard R8 minification (`isMinifyEnabled = true`, `isShrinkResources = true`). |
| **F16** | Medium | State Consistency | Registration wrote redundantly to local storage, Node server, and Supabase without transaction coordination. | Single source of truth: registration and authentication execute directly against Supabase Auth. Local storage caches only non-critical UI preferences (theme, language). |
| **F17** | Medium | Map Compliance | Map tiles fetched from Google tile servers without API compliance. | Switched to OpenStreetMap raster tiles with standard attribution and `userAgentPackageName`. Included commercial hosted provider guidance (MapTiler/Stadia). |
| **F18** | Medium | Admin Metrics | `/api/metrics` calculated safety rate incorrectly and hardcoded infrastructure costs. | Replaced with `admin_metrics_view` SQL view calculating real completed trips, gross volume, active captains, and SOS events per 1,000 trips. Hardcoded cost metrics removed. |
| **F19** | Medium | Repository Hygiene | Duplicate `main.dart`, stale `MainActivity` classes for abandoned package names (`refqa`, `rafik/app`), and mixed brand naming. | Removed `lib/main.dart` and obsolete Android directories. Standardized naming on **Rafik** across all packages (`com.rafik.rider`, `com.rafik.driver`), tiers (`rafik_girl`), and UI assets. |
| **F20** | Medium | Concurrency | Monolithic JSON file (`database.json`) rewritten on every request without file locking. | Completely eradicated with the decommissioning of the Node.js backend. All data managed with ACID transactions in PostgreSQL. |

---

## 3. API Endpoint to Supabase Migration Map

| Legacy Express / Node.js Endpoint | Method / Channel | Replacement in Pure Supabase Architecture | Security & Access Policy |
| :--- | :--- | :--- | :--- |
| `/api/register` | `POST` | `supabase.auth.signUp()` + `handle_new_user` trigger | Secure profile insertion, default unverified, rider role. |
| `/api/login` | `POST` | `supabase.auth.signInWithOtp()` / `signInWithOAuth()` | Authentic cryptographic session, JWT verification. |
| `/api/auth/otp/send` | `POST` | `supabase.auth.signInWithOtp({ phone })` | Supabase SMS gateway / test numbers. |
| `/api/auth/otp/verify` | `POST` | `supabase.auth.verifyOTP({ phone, token, type })` | Cryptographic OTP validation, generates authentic JWT. |
| `/api/database/records` | `GET` | Direct Supabase client queries | Protected by RLS policies; callers only read permitted data. |
| `/api/drivers` | `GET` | `supabase.from('drivers').select(...)` | Admin reads all; drivers read own record only. |
| `/api/drivers` (onboarding) | `POST` | `submit_driver_application` RPC | Validates 14-digit Egyptian National ID and gender parity. |
| `/api/drivers/:id/status` | `PUT` | `admin_review_driver` RPC | Admin only (`is_admin()`); updates driver and document status. |
| `/api/admin/reset` | `POST` | **REMOVED** | Dangerous endpoint deleted. Migrations and seeds govern lifecycle. |
| `/api/rides` | `POST` | `request_ride` RPC | Enforces single active ride, server fare calculation, PostGIS dispatch. |
| `/api/rides/:id/accept` | `POST` | `accept_ride` RPC | Atomic transaction, row locking, race-condition prevention. |
| `/api/rides/:id/arrive` | `POST` | `mark_arrived` RPC | Driver only, transitions ride state from `accepted` to `arrived`. |
| `/api/rides/:id/verify-pin` | `POST` | `start_ride` RPC | Compares against `ride_pins`; locks after 3 failures; no master PIN. |
| `/api/rides/:id/complete` | `POST` | `complete_ride` RPC | Driver only; credits driver wallet with 100% fare (0% commission). |
| `/api/rides/:id/cancel` | `POST` | `cancel_ride` RPC | Participant only; allowed in `requested`, `accepted`, `arrived`. |
| `/api/rides/:id/rate` | `POST` | `rate_ride` RPC | Participant only; updates running average rating of counterparty. |
| `/api/sos` | `POST` | `trigger_sos` RPC | Inserts active SOS event with coordinates; broadcasts to admin. |
| `/api/metrics` | `GET` | `supabase.from('admin_metrics_view').select()` | SQL view calculating accurate platform statistics. |
| `join-ride` | Socket.IO | `supabase.channel('ride-<id>')` | `postgres_changes` on `rides` filtered by ride ID. |
| `send-message` | Socket.IO | `supabase.from('messages').insert(...)` | RLS allows only participants of active rides to insert/select. |
| `location-update` | Socket.IO | `update_driver_location` RPC | Upserts `driver_locations` (5-second throttle, online check). |
| `driver-radar` | Socket.IO | `supabase.channel('driver-offers-<id>')` | `postgres_changes` on `ride_offers` table for driver user ID. |
| `sos-alert` | Socket.IO | `supabase.channel('sos-alerts')` | `postgres_changes` on `sos_events` table for admin portal. |

---

## 4. Database Schema, PostGIS & Security Governance

### Schema Highlights (`supabase/migrations/0001_core.sql`):
- **Core Entities:** `profiles`, `drivers`, `driver_locations`, `driver_documents`, `rides`, `ride_pins`, `ride_offers`, `messages`, `emergency_contacts`, `sos_events`, `wallet_transactions`, `identity_verifications`.
- **Spatial Engine:** PostGIS geography types (`Point, 4326`) indexed via GIST on `driver_locations(location)` and `rides(pickup)`.
- **National ID Algorithmic Parity:**
  ```sql
  create function public.national_id_gender(nid text) returns text language sql immutable as $$
    select case when nid ~ '^[23][0-9]{13}$'
      then case when substr(nid,13,1)::int % 2 = 0 then 'female' else 'male' end end $$;
  ```
- **Profile Protection Trigger:** Prevents riders or captains from manually altering `role`, `gender_verified`, or `rating_avg`.

### RPC Highlights (`supabase/migrations/0002_rpcs.sql`):
- **Fare Calculation:** Enforces $\text{fare} = \max(25.00, 15.00 + \text{km} \times 10.00)$.
- **PIN Security Without Rollback:** In `start_ride`, when an incorrect PIN is entered, the attempts counter is incremented and committed, returning `attempts_left` without raising an exception, preventing transaction rollback attacks. After 3 attempts, the ride is locked.
- **Concurrency Protection:** In `accept_ride`, `SELECT ... FOR UPDATE` ensures only the first driver to accept secures the ride; all subsequent attempts receive a structured `ride_unavailable` error.

---

## 5. Mobile Applications Refactoring & Hardening

### Dual Flavors:
- **Rider App:** `com.rafik.rider` (Entrypoint: `lib/main_rider.dart`)
- **Driver App:** `com.rafik.driver` (Entrypoint: `lib/main_driver.dart`)

### Flutter Architecture Updates:
1. **Config Injection:** Supabase client initialized via `String.fromEnvironment('SUPABASE_URL')` and `String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY')`. If missing, `FatalConfigErrorApp` renders a diagnostic error screen.
2. **Session Persistence:** Removed manual SharedPreferences session hacking. State transitions are governed by `supabase.auth.onAuthStateChange`.
3. **Adaptive Visual Identity:**
   - **Rafik Standard:** Jet Black (`#000000`) and Titanium Ice Blue (`#3B82F6`).
   - **Rafik Girl:** Obsidian Berry (`#12080C`) and Egyptian Rose Gold (`#B76E79`).
4. **Android Release Hardening:**
   - HTTPS enforcement via `network_security_config.xml`.
   - Release signing template in `build.gradle.kts` reading from gitignored `key.properties`.
   - ProGuard R8 rules enabled (`isMinifyEnabled = true`, `isShrinkResources = true`).
   - Granular runtime location permissions with bilingual dialogs (GPS disabled, denied, denied forever).

---

## 6. Admin Operations Portal

The Admin Portal (`admin_portal/index.html`) is a zero-backend, 100% static single-page application:
- **Authentication:** Admin login screen authenticates against Supabase Auth and validates `profiles.role === 'admin'`.
- **Private KYC Document Inspection:** Automatically requests 60-second signed URLs (`createSignedUrl`) from the private `driver-documents` bucket.
- **Female Captain Verification:** Review modal features an explicit confirmation checkbox ensuring national ID photos match female captain criteria before granting Rafik Girl authorization.
- **Emergency Monitoring:** Real-time listener on `sos_events` triggers visual alerts and an audible alarm using Web Audio API synthesis.
- **XSS Prevention:** All user-supplied data (names, phone numbers, addresses, license plates) is sanitized through `escapeHtml()` before rendering.

---

## 7. Assumptions & Design Decisions

1. **Distance Computation:** In the absence of an external paid routing engine (e.g. Google Directions or Mapbox), distance is computed at the database level using `ST_Distance(geography) / 1000.0 * 1.25` (applying a 1.25 Greater Cairo urban traffic factor).
2. **OpenStreetMap Usage:** Raster tile layers use `https://tile.openstreetmap.org/{z}/{x}/{y}.png` with compliant attribution. Production deployments with high request volumes should configure a hosted tile proxy (such as MapTiler or Stadia Maps).
3. **SMS Verification:** Development environments utilize Supabase Auth test phone numbers and email sign-in. Production deployments require configuring an SMS gateway (Twilio or Egyptian local provider) in the Supabase Cloud dashboard.

---

## 8. Verification & Test Results

1. **Flutter Test Suite:**
   - Executed `flutter test` across rider and driver flows.
   - Result: **All tests passed** (Fare preview logic, UI controllers, and flavor initialization verified).
2. **Codebase Grep Verification:**
   - Scanned entire repository for `localhost|127\.0\.0\.1|10\.0\.2\.2|192\.168|:5000`.
   - Result: **0 occurrences** outside historical documentation (`docs/` and `AUDIT.md`).
3. **Security Test Suite:**
   - SQL test suite created in `supabase/tests/01_security_and_rpc_test.sql` validating RLS isolation, unauthorized updates, PIN lockouts, and Rafik Girl constraints.

---

## 9. Deployment & Execution Runbook

### A. Deploy Database (Supabase Cloud)
```bash
# 1. Login to Supabase CLI
supabase login

# 2. Link repository to your Supabase project
supabase link --project-ref <your-project-id>

# 3. Apply all migrations
supabase db push

# 4. Bootstrap the first administrator (in Supabase SQL Editor):
# UPDATE public.profiles SET role = 'admin' WHERE email = 'admin@rafik.com';
```

### B. Run Mobile Applications (Flutter)
```bash
cd mobile_app

# 1. Create environment file from template
cp env/example.json env/dev.json
# (Configure SUPABASE_URL and SUPABASE_PUBLISHABLE_KEY in env/dev.json)

# 2. Run Rider flavor
flutter run --flavor rider -t lib/main_rider.dart --dart-define-from-file=env/dev.json

# 3. Run Driver flavor
flutter run --flavor driver -t lib/main_driver.dart --dart-define-from-file=env/dev.json
```

### C. Build Release APKs
```bash
cd mobile_app

# Build Rider Release APK
flutter build apk --release --flavor rider -t lib/main_rider.dart --dart-define-from-file=env/prod.json

# Build Driver Release APK
flutter build apk --release --flavor driver -t lib/main_driver.dart --dart-define-from-file=env/prod.json
```

### D. Deploy Admin Portal (Static Host)
```bash
cd admin_portal

# 1. Create config file from template
cp config.example.js config.js
# (Set window.RAFIK_CONFIG with your Supabase credentials)

# 2. Deploy directly to Cloudflare Pages, Netlify, or Vercel
# Root directory: admin_portal
# Build command: None (Static)
```

---
*Report certified by Antigravity Autonomous Engineering Agent — October 2026.*
