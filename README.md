# Rafik (رَفِيق) — Next-Generation Ride-Hailing Platform

[![Platform](https://img.shields.io/badge/Platform-Flutter%20%7C%20Supabase-blue.svg)](https://flutter.dev)
[![Status](https://img.shields.io/badge/Status-Production%20Hardened-success.svg)]()
[![Security](https://img.shields.io/badge/Security-RLS%20%2B%20SECURITY%20DEFINER%20RPCs-emerald.svg)]()
[![Copyright](https://img.shields.io/badge/Copyright-Rafik%202026-rose.svg)]()

> **All rights reserved to Rafik 2026.**  
> *Rafik (رَفِيق)* is an enterprise-grade Egyptian ride-hailing ecosystem built on a pure, serverless **Supabase Cloud** architecture (PostgreSQL, PostGIS, Row Level Security, RPCs, Realtime, and private Storage). It features a dual-tier service model: **Rafik Standard** and the dedicated **Rafik Girl** women-centric safety network.

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

## 🏛️ Pure Supabase Architecture

Rafik operates with **zero intermediate application servers**. All business logic, authorization, spatial queries, and safety handshakes are enforced directly inside the database engine.

```
┌─────────────────────────────────┐       ┌─────────────────────────────────┐
│     Rafik Rider App (Flutter)   │       │    Rafik Driver App (Flutter)   │
│   (Flavored: com.rafik.rider)   │       │   (Flavored: com.rafik.driver)  │
└────────────────┬────────────────┘       └────────────────┬────────────────┘
                 │                                         │
                 │         HTTPS / WSS (Supabase SDK)     │
                 └───────────────────┬─────────────────────┘
                                     │
                   ┌─────────────────┴─────────────────┐
                   │       Supabase Cloud Engine       │
                   ├───────────────────────────────────┤
                   │  • Supabase Auth (OTP / OAuth)    │
                   │  • PostgreSQL 15 + PostGIS Spatial│
                   │  • Strict Row Level Security (RLS)│
                   │  • 16 SECURITY DEFINER RPCs       │
                   │  • Realtime (postgres_changes)    │
                   │  • Private Storage (Signed URLs)  │
                   └─────────────────┬─────────────────┘
                                     │
                   ┌─────────────────┴─────────────────┐
                   │    Admin Operations Portal        │
                   │  Static Web App (Vercel/Netlify)  │
                   │  Leaflet / OSM • KYC Document Q   │
                   └───────────────────────────────────┘
```

- **Authentication:** Supabase Auth with Phone OTP, Email/Password, and Google Sign-In. Direct phone verification with automatic `profiles` row generation via database trigger.
- **Row Level Security (RLS):** Enabled on 100% of tables. Direct `INSERT`, `UPDATE`, and `DELETE` on operational tables (`rides`, `ride_pins`, `ride_offers`, `drivers`, `driver_locations`, `wallet_transactions`) are strictly revoked from `anon` and `authenticated` roles.
- **SECURITY DEFINER RPCs:** All operational transitions are executed via parameterized, audit-safe stored procedures with strict parameter validation and atomic state management:
  - `compute_fare(km)`
  - `request_ride(tier, pickup_address, pickup_lat, pickup_lng, dropoff_address, dropoff_lat, dropoff_lng, payment)`
  - `accept_ride(ride_id)` — Atomic check preventing race conditions between concurrent captains.
  - `decline_offer(ride_id)`
  - `mark_arrived(ride_id)`
  - `start_ride(ride_id, pin)` — Enforces 3-attempt lockout without rolling back failure counters; zero master PIN bypass.
  - `complete_ride(ride_id)` — Credits captain wallet with 100% fare (0% commission).
  - `cancel_ride(ride_id, reason)`
  - `rate_ride(ride_id, stars, review)`
  - `submit_driver_application(national_id, license_number, make, model, year, plate, color)`
  - `set_driver_online(online)`
  - `update_driver_location(lat, lng, heading)`
  - `trigger_sos(ride_id, lat, lng)`
  - `admin_review_driver(driver_id, approve, reason, confirm_female)`
  - `admin_review_identity(user_id, approve, reason)`
  - `expire_stale_rides()`
- **Realtime Dispatch:** Broadcasts and driver updates use Supabase Realtime `postgres_changes` respecting database RLS.
- **Document Vault:** Captain KYC documents (6 photos) and rider identity proofs are stored in private Supabase Storage buckets (`driver-documents` and `identity-documents`). Document inspection in the Admin Portal uses short-lived signed URLs (60-second expiration).
- **Map & Routing:** OpenStreetMap raster tiles with proper attribution and Open Source routing distance formula (`Haversine * 1.25` Cairo traffic factor).

---

## 📐 Cairo Fare Formula

$$\text{Fare (EGP)} = \max\Big(25.00,\, 15.00 + (\text{Distance in km} \times 10.00)\Big)$$

- **Base Pickup Fare:** 15.00 EGP
- **Per Kilometer Rate:** 10.00 EGP
- **Minimum Trip Fare:** 25.00 EGP
- **Platform Commission:** 0.00 EGP (100% earnings to captains)

---

## 🛠️ Getting Started

### Prerequisites
- [Flutter SDK](https://flutter.dev/) (v3.24+)
- [Supabase CLI](https://supabase.com/docs/guides/cli) (v1.140+)
- Android Studio / Android SDK (API 34+)

---

### 1. Database Setup (Supabase Cloud)

1. **Link your Supabase Project:**
   ```bash
   supabase login
   supabase link --project-ref <your-supabase-project-id>
   ```

2. **Push Migrations:**
   ```bash
   # Applies 0001_core.sql and 0002_rpcs.sql
   supabase db push
   ```

3. **Verify Security Tests:**
   Execute the pgTAP / SQL security test suite to verify RLS lockdown, RPC constraints, and lockout mechanisms:
   ```bash
   supabase test db
   # Or run supabase/tests/01_security_and_rpc_test.sql in the SQL Editor
   ```

4. **Bootstrap Initial Administrator:**
   Create an admin account via Supabase Auth (or the Admin Portal login screen), then promote it in the Supabase SQL Editor:
   ```sql
   UPDATE public.profiles
   SET role = 'admin'
   WHERE email = 'admin@rafik.com'; -- Or your admin user ID
   ```

---

### 2. Mobile App Setup (`mobile_app/`)

1. **Configure Environment:**
   Copy the example environment configuration:
   ```bash
   cd mobile_app
   cp env/example.json env/dev.json
   ```
   Edit `env/dev.json` with your Supabase URL and Publishable Anon Key:
   ```json
   {
     "SUPABASE_URL": "https://your-project-id.supabase.co",
     "SUPABASE_PUBLISHABLE_KEY": "your-publishable-anon-key"
   }
   ```
   *(Note: `env/*.json` is gitignored to protect client configs).*

2. **Install Flutter Dependencies:**
   ```bash
   flutter pub get
   ```

3. **Run Rider App:**
   ```bash
   flutter run --flavor rider -t lib/main_rider.dart --dart-define-from-file=env/dev.json
   ```

4. **Run Driver App:**
   ```bash
   flutter run --flavor driver -t lib/main_driver.dart --dart-define-from-file=env/dev.json
   ```

5. **Build Hardened Release APKs:**
   ```bash
   # Rider Release APK
   flutter build apk --release --flavor rider -t lib/main_rider.dart --dart-define-from-file=env/prod.json

   # Driver Release APK
   flutter build apk --release --flavor driver -t lib/main_driver.dart --dart-define-from-file=env/prod.json
   ```

---

### 3. Admin Operations Portal (`admin_portal/`)

The Admin Operations Portal is a 100% static web application that requires zero backend servers.

1. **Configure Environment:**
   Copy the example configuration:
   ```bash
   cd admin_portal
   cp config.example.js config.js
   ```
   Edit `config.js`:
   ```javascript
   window.RAFIK_CONFIG = {
     SUPABASE_URL: "https://your-project-id.supabase.co",
     SUPABASE_PUBLISHABLE_KEY: "your-publishable-anon-key"
   };
   ```

2. **Run Locally:**
   Open `index.html` using any local static web server:
   ```bash
   # Using Python 3:
   python -m http.server 8080
   # Using npx serve:
   npx serve .
   ```
   Open the hosted local address (e.g. port 8080) in your browser.

3. **Deploy to Production:**
   Deploy the `admin_portal/` folder directly to **Cloudflare Pages**, **Vercel**, or **Netlify**:
   - Build Command: *(None)*
   - Output Directory: `.`
   - Ensure `config.js` is generated from your platform's environment variables during deployment or configured in CI/CD.

---

## 🗺️ Map Tile Attribution Notice

Rafik utilizes OpenStreetMap raster tile layers with Leaflet and Flutter Map.
- **Attribution:** `© OpenStreetMap contributors`
- **Production Note:** The default tile server `tile.openstreetmap.org` is intended for development and evaluation under the OSM Tile Usage Policy. Before scaling to commercial production, configure a hosted tile endpoint (such as [MapTiler](https://www.maptiler.com/), [Stadia Maps](https://stadiamaps.com/), or an in-house tile cache).

---

## 🔒 Security Best Practices

1. **No Service Role Keys in Clients:** Neither the Flutter mobile applications nor the static Admin Portal require or accept the Supabase `service_role` secret key. All operations execute strictly via user-authenticated contexts or `SECURITY DEFINER` RPCs.
2. **National ID Algorithm:** The 13th digit of Egyptian National IDs is validated cryptographically (`odd = male`, `even = female`) to prevent gender spoofing on the Rafik Girl tier.
3. **Trip PIN Handshake:** PINs are stored in a dedicated `ride_pins` table inaccessible to drivers via SELECT policies. Drivers can only submit a candidate PIN via the `start_ride` RPC. After 3 incorrect attempts, the ride is locked against brute force.
4. **Distress Protocol (SOS):** Initiating an emergency triggers the `trigger_sos` RPC, broadcasting real-time coordinates to the Admin Command Center while immediately launching a phone call to Egyptian Police (`122`).

---

## 📄 License & Copyright

All rights reserved © 2026 **Rafik (رَفِيق)**.  
Unauthorized copying, reverse engineering, or redistribution of this software is strictly prohibited.
