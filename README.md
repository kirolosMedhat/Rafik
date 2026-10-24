# Rafik (رَفِيق) — Next-Generation Ride-Hailing Platform

[![Platform](https://img.shields.io/badge/Platform-Flutter%20%7C%20Node.js%20%7C%20Supabase-blue.svg)](https://flutter.dev)
[![Status](https://img.shields.io/badge/Status-Production%20Ready-success.svg)]()
[![Copyright](https://img.shields.io/badge/Copyright-Rafik%202026-rose.svg)]()

> **All rights reserved to Rafik 2026.**  
> *Rafik (رَفِيق)* is a modern, high-performance Egyptian ride-hailing ecosystem featuring a seamless dual-tier architecture: **Rafik Standard** and the dedicated **Rafik Girl** women-centric safety network.

---

## 🌟 Platform Overview

Rafik is designed specifically for Greater Cairo’s transit dynamics, addressing passenger safety, fair driver compensation, and high-frequency dispatch across Cairo, Giza, New Cairo (Tagamoa - AUC), Sheikh Zayed, Zamalek, and Heliopolis.

### 🚗 Dual-Tier Service Tiers
1. **Rafik Standard (رَفِيق ستاندرد)**
   - Open to all passengers and certified Egyptian captains.
   - **Signature Visual Identity:** Sleek Jet Black (`#000000`) and Titanium Ice Blue (`#3B82F6`) palette.
   - Fair and transparent Cairo pricing with 0% platform commission on promotional trips.
2. **Rafik Girl (رَفِيق جيرل)**
   - A dedicated, secure ride-hailing option exclusively pairing female passengers with rigorously verified female captains.
   - **Signature Visual Identity:** Obsidian Berry (`#12080C`) and Egyptian Rose Gold (`#B76E79`) luxury theme.
   - Enhanced security features, automatic route monitoring, and strict gender validation.

---

## 🚀 Key Features

### 📱 1. Mobile Applications (Flutter)
- **Unified Dual-Flavored Codebase:**
  - `Rafik-Rider.apk`: Passenger booking, route selection, live fare estimates, driver tracking, and SOS safety shield.
  - `Rafik-Driver.apk`: Real-time dispatch radar, 1-tap "Go Online", route navigation, in-ride chat, earnings wallet, and 6-sided document vault.
- **Dynamic Adaptive UI & Theme Switching:**
  - Auto-switches between Jet Black (Male) and Obsidian Berry / Rose Gold (Female) based on selected gender profile.
  - OLED Night / Dark Mode by default.
- **Bilingual Interface:**
  - English by default with instant 1-tap Arabic toggle (🌐 EN | عربي).
- **Streamlined Authentication & Intake:**
  - Dual tabs for **Log In** and **Register**.
  - Auto-login session caching: once registered, users are never shown the registration screen on relaunch.
  - 1-Tap Google Sign-In and Instant Demo Bypass for rapid testing and demonstrations.
- **Trip Security Handshake:**
  - Cryptographic 4-digit PIN verification before trip start to ensure correct passenger-driver matching.
- **Emergency Safety Shield (SOS):**
  - Instant 1-tap distress trigger linking directly to Egyptian Emergency Police (122) and streaming real-time GPS telemetry to the Operations Command Center.

### 🖥️ 2. Admin Operations & Safety Command Center
- **Interactive Cairo Fleet Radar:**
  - Leaflet & OpenStreetMap real-time driver locations, heading, and live ride routes across Greater Cairo.
- **Live KYC & Driver Intake Vault:**
  - 6-Sided document inspection: National ID (front & back), Driving License (front & back), and Vehicle Mulkiya (front & back).
  - One-click **Approve Captain** and **Reject Application** actions.
- **Empty-by-Default Production Database:**
  - Zero dummy data: new registrations stream directly into the **Pending** queue in real time.
- **Emergency Telemetry Log:**
  - Real-time audit logs for dispatch events, GPS updates, and SOS distress events.

### ⚡ 3. Backend & Realtime Architecture (Node.js & TypeScript)
- **High-Performance REST & WebSocket Server:**
  - Persistent disk database (`backend/data/database.json`) ensures no data loss across server restarts.
  - REST endpoints:
    - `POST /api/register` — Universal user and captain registration.
    - `POST /api/login` — Phone-based authentication.
    - `GET /api/database/records` — Full database inspection endpoint.
    - `GET /api/drivers` & `GET /api/drivers/:id` — Driver fleet querying.
    - `PUT /api/drivers/:id/status` — Admin status updates (`approved`, `rejected`, `online`, `offline`).
    - `POST /api/rides/request` & `POST /api/rides/:id/accept` — Real-time dispatch lifecycle.
    - `POST /api/sos` — Emergency alert ingestion.
- **Cloud Database Support:**
  - Fully wired for **Supabase Cloud** (PostgreSQL + PostGIS + Supabase Realtime).
  - Automatic fallback to local persistence so apps remain 100% responsive and crash-free even during cloud DNS outages.

---

## 📐 Cairo Fare Formula

$$\text{Fare (EGP)} = \max\Big(25.00,\, 15.00 + (\text{Distance in km} \times 10.00)\Big)$$

- **Base Pickup Fare:** 15.00 LE
- **Per Kilometer Rate:** 10.00 LE
- **Minimum Trip Fare:** 25.00 LE
- **Platform Commission:** 0.00 LE (100% earnings to captains)

---

## 🛠️ Getting Started

### Prerequisites
- [Node.js](https://nodejs.org/) (v18+)
- [Flutter SDK](https://flutter.dev/) (v3.24+)
- Android Studio / Android SDK (API 34+)

### 1. Start Backend & Admin Portal
```bash
# Navigate to backend directory
cd backend

# Install dependencies
npm install

# Compile TypeScript
npm run build

# Start the server (Port 5000)
npm start
```
- **Admin Dashboard:** Open [http://localhost:5000/admin](http://localhost:5000/admin) in your browser.
- **Database Inspection:** [http://localhost:5000/api/database/records](http://localhost:5000/api/database/records).

### 2. Run Mobile Applications
```bash
# Navigate to mobile app directory
cd mobile_app

# Fetch dependencies
flutter pub get

# Run Rider App
flutter run --flavor rider -t lib/main_rider.dart

# Run Driver App
flutter run --flavor driver -t lib/main_driver.dart
```

### 3. Build Release APKs
```bash
# Build Rider Release APK
flutter build apk --flavor rider -t lib/main_rider.dart --release --no-tree-shake-icons

# Build Driver Release APK
flutter build apk --flavor driver -t lib/main_driver.dart --release --no-tree-shake-icons
```
Output binaries:
- `build/app/outputs/flutter-apk/app-rider-release.apk`
- `build/app/outputs/flutter-apk/app-driver-release.apk`

---

## 📂 Project Structure

```
Rafik/
├── admin_portal/                  # Operations Command Center (HTML5, Tailwind, Leaflet, Supabase)
│   └── index.html                 # Fleet radar, live KYC vault, SOS dispatch center
├── backend/                       # Node.js + TypeScript REST & WebSocket Server
│   ├── data/
│   │   └── database.json          # Persistent disk database storage
│   ├── src/
│   │   ├── index.ts               # Core server and API endpoints
│   │   └── config/supabase.ts     # Supabase client configuration
│   └── package.json
├── mobile_app/                    # Flutter Multi-Platform App (Rider & Driver)
│   ├── lib/
│   │   ├── main_rider.dart        # Entrypoint for Rafik Rider
│   │   ├── main_driver.dart       # Entrypoint for Rafik Driver
│   │   ├── core/                  # Theme, persistent storage, location & Supabase services
│   │   └── features/
│   │       ├── auth/              # Dual-tier responsive Auth & Intake Screen
│   │       ├── rider/             # Rider map, booking sheet, safety shield, ratings
│   │       ├── driver/            # Driver radar, 1-tap online, wallet, KYC onboarding
│   │       ├── chat/              # In-ride passenger-driver messaging
│   │       └── biometrics/        # ID OCR & verification
│   └── pubspec.yaml
├── design/                        # Brand identity, icons, and SVG assets
├── supabase_schema.sql            # PostgreSQL + PostGIS database schema
├── .env.example                   # Environment configuration template
├── .gitignore                     # Git exclusion rules
└── README.md                      # Platform documentation
```

---

## 🔒 Security & Privacy
- **Zero Secrets in Repository:** Real API keys and credentials are kept out of version control via `.gitignore`.
- **Driver Verification:** Rigorous verification including Egyptian National ID, driving license, and vehicle registration mulkiya.
- **Privacy by Design:** Phone numbers are masked in transit communications.

---

## ⚖️ License
All rights reserved to **Rafik 2026**. Unauthorized distribution, modification, or commercial reproduction is strictly prohibited.
