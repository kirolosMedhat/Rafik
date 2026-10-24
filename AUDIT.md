# Rafik Architecture & Security Audit (F1 – F20)

**Date:** October 2026  
**Auditor:** Autonomous Migration Engineer (Antigravity)  
**Repository:** `github.com/kirolosMedhat/Rafik`  
**Migration Branch:** `supabase-migration`  

---

## 1. Executive Summary

This audit catalogs 20 verified findings (F1–F20) across security, data integrity, architecture, and code quality in the Rafik platform. The migration plan replaces the Node.js/Express/Socket.IO backend and JSON-file database with a pure, production-grade Supabase architecture (Supabase Auth, PostgreSQL + PostGIS, Row Level Security, `SECURITY DEFINER` RPCs, and Realtime `postgres_changes`).

---

## 2. Verified Findings Catalog

### Critical: Security and Safety (F1 – F7)

| ID | Severity | Category | Description | Files Affected | Root Cause & Remediation |
|---|---|---|---|---|---|
| **F1** | Critical | Auth / Access | `/api/login` logs in any caller by phone number only without credential verification, and auto-creates a female rider if unknown. | `backend/src/index.ts:250-280` | Client/Node bypass. Replaced with Supabase Auth OTP (`signInWithOtp` / `verifyOTP`) and `handle_new_user()` trigger on `auth.users`. |
| **F2** | Critical | Auth / Bypasses | OTP verification accepts any 4 digits under "Committee Demo Bypass" (UI displayed `1234`). A 1-tap "Instant Bypass" button was present. | `mobile_app/lib/features/auth/otp_verification_sheet.dart`, `mobile_app/lib/features/auth/auth_screen.dart:150-180` | Hardcoded demo bypass logic. Removed entirely from production. Any test bypass restricted strictly to `kDebugMode` hitting pre-seeded auth users. |
| **F3** | Critical | Safety / Gender | Gender was self-declared. Backend set `genderVerified = gender === 'female'`, allowing any user to enter Rafik Girl immediately. | `backend/src/index.ts:310-330`, `mobile_app/lib/features/auth/auth_screen.dart`, `mobile_app/lib/features/rider/rider_home_screen.dart` | No verification step. Replaced with mandatory admin approval of government KYC/identity documents before `profiles.gender_verified` can be set to `true`. |
| **F4** | Critical | Security / RBAC | Zero authentication on REST endpoints (`/api/database/records`, `/api/drivers`, `PUT /api/drivers/:id/status`, `POST /api/admin/reset`). Socket.IO CORS set to `*`. | `backend/src/index.ts:180-220, 680-720` | Unprotected Node server. Node server decommissioned; all database mutations moved behind authenticated Supabase RPCs with strict role checks (`is_admin()`). |
| **F5** | Critical | Privacy / RLS | RLS in `supabase_schema.sql` allowed anyone to read `profiles` and `drivers` (exposing national IDs and phone numbers). Users could update their own `role`, `gender`, and `gender_verified`. | `supabase_schema.sql:35-70` | Permissive RLS policies. Fixed with strict RLS: profiles only readable by owner, admin, or active ride counterparty (with masked contact). Direct mutation revoked; updates via `protect_profile()` trigger. |
| **F6** | Critical | Data Protection | Storage bucket `driver-documents` configured as `public = true`, exposing driver KYC images to the public internet. `driver_documents.status` defaulted to `'approved'`. | `supabase_schema.sql:120-145` | Public bucket setting. Migrated to private buckets `driver-documents` and `identity-documents` accessible only via owner policy or admin signed URLs (`createSignedUrl`). |
| **F7** | Critical | Safety / PIN | Trip handshake PIN was hardcoded to `'7429'` on the rider client and backend accepted master PIN `'1234'` with unlimited attempts. | `mobile_app/lib/features/rider/rider_home_screen.dart:139`, `backend/src/index.ts:510-530` | Insecure handshake. Replaced with ephemeral cryptographic 4-digit PIN stored in isolated `ride_pins` table (never selectable by drivers) with max 3 attempts lock enforced by `start_ride()` RPC. |

---

### High: Broken Flows and Data Integrity (F8 – F14)

| ID | Severity | Category | Description | Files Affected | Root Cause & Remediation |
|---|---|---|---|---|---|
| **F8** | High | Schema Mismatch | Mobile app and database schema column names disagreed: `fare_amount` vs `fare_egp`, `handshake_pin` vs `pin_code`, missing `driver_earnings_egp`, `contact_phone` vs `phone_number`, `uper_girl_certified`, mismatched `drivers` keys. Writes failed silently. | `mobile_app/lib/core/services/supabase_service.dart`, `mobile_app/lib/features/auth/auth_screen.dart`, `mobile_app/lib/features/driver/driver_onboarding_screen.dart`, `supabase_schema.sql` | Desynchronized client-database contracts. Standardized all column names in `0001_core.sql` and `0002_rpcs.sql`; removed all `catch -> debugPrint` swallowers. |
| **F9** | High | Auth / Identity | App used synthetic IDs (`usr-<timestamp>`, `demo-rider-...`) instead of Supabase Auth UUIDs. `auth.uid()` never matched, completely breaking RLS. | `mobile_app/lib/features/auth/auth_screen.dart`, `mobile_app/lib/features/auth/otp_verification_sheet.dart` | Fake session creation. Replaced with real Supabase Auth sessions, routing purely on `supabase.auth.currentSession`. |
| **F10** | High | KYC Verification | Driver onboarding constructed a fake URL string without uploading images. Admin portal displayed hardcoded Unsplash stock photos. Registration fabricated national IDs (`29804150102844`), plates, and liveness `0.984`. | `mobile_app/lib/features/driver/driver_onboarding_screen.dart:140-165`, `backend/src/index.ts:340-380`, `admin_portal/index.html:720-760` | Mocked KYC pipeline. Replaced with real Supabase Storage multipart uploads (`{uid}/{kind}.jpg`) and admin signed URL previewing. |
| **F11** | High | Realtime / Tracking | Driver movement on rider map was simulated by local Dart timers (`_startDriverMovementSimulation`, `_startTripProgressSimulation`). A 12s fallback faked driver response. | `mobile_app/lib/features/rider/rider_home_screen.dart:210-260, 480-530` | Client simulation timers. Removed all simulation timers and local fallbacks. Position driven strictly by `postgres_changes` on `driver_locations`. |
| **F12** | High | Dispatch / Concurrency | Dispatch was an unranked broadcast to all connected sockets. `find_nearby_female_drivers` was never called. `accept` had no row locking, allowing race conditions. | `backend/src/index.ts:440-490`, `mobile_app/lib/features/driver/driver_radar_screen.dart`, `mobile_app/lib/features/rider/rider_home_screen.dart` | Unsynchronized broadcast. Migrated to `request_ride()` generating ranked `ride_offers` within 5 km and atomic `accept_ride()` RPC with row locking (`FOR UPDATE`). |
| **F13** | High | Pricing / Tampering | Fare was computed on the mobile phone and trusted blindly by the server. | `mobile_app/lib/features/rider/rider_home_screen.dart:358`, `backend/src/index.ts:415` | Client-authoritative pricing. Moved fare calculation entirely to PostgreSQL `compute_fare(km)` function (`greatest(25, round(15 + km * 10, 2))`). Client fare is preview only. |
| **F14** | High | Network / Architecture | Hardcoded LAN IP `http://192.168.1.13:5000` and `localhost:5000` embedded in mobile app, admin portal, and scripts. | `mobile_app/lib/features/auth/auth_screen.dart:135`, `admin_portal/index.html:598, 1112`, `backend/src/index.ts` | Local environment hardcoding. All endpoints replaced with Supabase Client SDK configured via runtime `--dart-define-from-file` and `config.js`. |

---

### Medium: Cleanup and Configuration (F15 – F20)

| ID | Severity | Category | Description | Files Affected | Remediation |
|---|---|---|---|---|---|
| **F15** | Medium | Android Security | `usesCleartextTraffic="true"`, release builds signed with debug keystore, R8 code/resource shrinking disabled. | `mobile_app/android/app/src/main/AndroidManifest.xml`, `mobile_app/android/app/build.gradle.kts` | Disabled cleartext traffic, configured release signing template with `key.properties`, enabled `isMinifyEnabled` and `isShrinkResources`. |
| **F16** | Medium | Data Consistency | Registration wrote concurrently to three disparate stores (Local persistent storage, Node backend, Supabase) with no transactional guarantees. | `mobile_app/lib/features/auth/auth_screen.dart`, `mobile_app/lib/core/services/persistent_storage.dart` | Unified data flow to Supabase Auth -> `handle_new_user()` trigger -> single source of truth in PostgreSQL. |
| **F17** | Medium | Licensing / Map Tiles | Map tiles loaded from Google tile URLs (`mt{s}.google.com`) in violation of terms. | `mobile_app/lib/features/rider/rider_home_screen.dart`, `mobile_app/lib/features/driver/driver_radar_screen.dart`, `admin_portal/index.html` | Switched to OpenStreetMap tile endpoints with proper `userAgentPackageName` attribution. |
| **F18** | Medium | Analytics / Accuracy | `/api/metrics` calculated safety rate incorrectly (`SOS count / completed rides`), and `infrastructureCostUsd` was hardcoded to 0. | `backend/src/index.ts:600-630`, `admin_portal/index.html` | Replaced with PostgreSQL SQL view calculating genuine platform metrics (active drivers, completed rides, gross volume, SOS incidents). Removed fake cost metrics. |
| **F19** | Medium | Technical Debt | Duplicate entrypoint `lib/main.dart`; four redundant `MainActivity.kt` files across legacy packages (`rafik`, `refqa`, `rider`, `driver`); ten unused test/inspect scripts in `backend/`; fragmented naming (`Uper Girl`, `Refqa`, `uper_girl`). | `mobile_app/lib/main.dart`, `mobile_app/android/app/src/main/kotlin/...`, `backend/src/test_*` | Deleted duplicate files, standardized flavor entrypoints (`main_rider.dart`, `main_driver.dart`), renamed all references to `Rafik` / `rafik_girl`. |
| **F20** | Medium | Storage / Concurrency | Node backend rewrote entire `backend/data/database.json` file synchronously on every write with zero file locking. | `backend/data/database.json`, `backend/src/index.ts` | Node backend and JSON database eliminated completely. |

---

## 3. Initial Baseline Grep Scan (Phase 0)

Pattern scanned: `localhost|127\.0\.0\.1|10\.0\.2\.2|192\.168|:5000`

```text
RAFIK_GRADUATION_BOOK.html:493:        ExpressREST["Express.js REST Gateway (:5000)\n/api/register | /api/drivers | /api/rides"]
RAFIK_GRADUATION_BOOK.html:635:    participant Server as Rafik Server (:5000)
RAFIK_GRADUATION_BOOK.html:679:    participant Server as Operations Server (:5000)
README.md:108:- **Admin Dashboard:** Open [http://localhost:5000/admin](http://localhost:5000/admin) in your browser.
README.md:109:- **Database Inspection:** [http://localhost:5000/api/database/records](http://localhost:5000/api/database/records).
WORKFLOW_AND_IMPLEMENTATION_TRACKER.md:296:- [x] Live API Server operational at `http://localhost:5000` verified with `/health` and PostGIS dispatch endpoints.
admin_portal/index.html:598:    const BACKEND_URL = window.location.origin.startsWith('http') ? window.location.origin : 'http://localhost:5000';
admin_portal/index.html:1112:        console.log('Local backend not reachable on :5000, continuing with Supabase Realtime.');
backend/src/index.ts:193:    adminPortalUrl: `http://localhost:${PORT}/admin`,
backend/src/index.ts:731:  console.log(`🖥️  Admin Dashboard: http://localhost:${PORT}/admin`);
backend/src/index.ts:732:  console.log(`📡 Health Check:    http://localhost:${PORT}/health`);
backend/src/index.ts:733:  console.log(`💾 Database API:    http://localhost:${PORT}/api/database/records`);
backend/src/index.ts:734:  console.log(`👥 Drivers API:     http://localhost:${PORT}/api/drivers`);
backend/src/index.ts:735:  console.log(`🚗 Rides API:       http://localhost:${PORT}/api/rides`);
backend/src/index.ts:736:  console.log(`🚨 SOS API:         http://localhost:${PORT}/api/sos`);
backend/src/test_suite.ts:26:const BASE_URL = 'http://localhost:5000';
mobile_app/lib/features/auth/auth_screen.dart:135:        final req = await client.postUrl(Uri.parse('http://192.168.1.13:5000/api/register'));
```

**Target after Phase 5:** 0 matches in code, configuration, or active scripts.
