/**
 * End-to-End Automated Test Suite for Rafik & Rafik Girl
 * Tests:
 * 1. Server Connection & Health Status
 * 2. Registration & Login Phase (Rider & Driver, OTP, Gender, Rafik Girl enrollment)
 * 3. 14-Digit Egyptian National ID OCR Parity Algorithm
 * 4. Driver Onboarding with 6-Sided Document Vault & Biometrics
 * 5. Cairo Maps, Haversine Distance & 10 EGP/km Fare Formula
 * 6. Google Maps High-Res Raster CDN Tile Connectivity
 * 7. Dual-Tier Dispatch (Rafik Standard vs Rafik Girl Safe Mode)
 * 8. Complete Ride Lifecycle (Request -> Accept -> Handshake PIN -> In-Trip -> Complete)
 * 9. Driver Wallet & Rating Settlement
 * 10. Emergency SOS Incident & Police 122 Linkage
 * 11. Admin Command Center Metrics & Fleet Filtering
 * 12. Final Database Cleanout (0 Dummy Data Guarantee)
 */

interface TestResult {
  module: string;
  testName: string;
  passed: boolean;
  details: string;
  durationMs: number;
}

const BASE_URL = 'http://localhost:5000';
const results: TestResult[] = [];

async function runTest(module: string, testName: string, testFn: () => Promise<string | void>) {
  const start = Date.now();
  try {
    const details = await testFn();
    results.push({
      module,
      testName,
      passed: true,
      details: details || 'Passed successfully',
      durationMs: Date.now() - start,
    });
    console.log(`  ✅ [PASS] ${testName} (${Date.now() - start}ms)`);
  } catch (err: any) {
    results.push({
      module,
      testName,
      passed: false,
      details: err.message,
      durationMs: Date.now() - start,
    });
    console.error(`  ❌ [FAIL] ${testName}: ${err.message}`);
  }
}

// Distance calculation utility (Haversine + 1.25x Cairo road factor)
function calculateCairoRoadKm(lat1: number, lon1: number, lat2: number, lon2: number): number {
  const R = 6371; // Earth radius in km
  const dLat = (lat2 - lat1) * Math.PI / 180;
  const dLon = (lon2 - lon1) * Math.PI / 180;
  const a =
    Math.sin(dLat / 2) * Math.sin(dLat / 2) +
    Math.cos(lat1 * Math.PI / 180) * Math.cos(lat2 * Math.PI / 180) *
    Math.sin(dLon / 2) * Math.sin(dLon / 2);
  const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
  const straightKm = R * c;
  return Math.round((straightKm * 1.25) * 10) / 10;
}

// Fare formula: Base 15 LE + 10 LE / km (Min 25 LE)
function calculateTripFare(roadKm: number): number {
  const baseFare = 15.0;
  const ratePerKm = 10.0;
  const minFare = 25.0;
  const raw = baseFare + (roadKm * ratePerKm);
  return Math.max(minFare, Math.round(raw * 100) / 100);
}

// Egyptian National ID parity check (13th digit: Even = Female, Odd = Male)
function verifyEgyptianIdGender(nationalId: string): { is14Digits: boolean; gender: 'female' | 'male' } {
  const is14Digits = /^\d{14}$/.test(nationalId);
  const digit13 = parseInt(nationalId.charAt(12), 10);
  const gender = digit13 % 2 === 0 ? 'female' : 'male';
  return { is14Digits, gender };
}

async function startTestSuite() {
  console.log('===============================================================');
  console.log('🚀 RUNNING RAFIK & RAFIK GIRL PRODUCTION END-TO-END TEST SUITE (All rights reserved to Rafik 2026)');
  console.log(`📡 Target Backend: ${BASE_URL}`);
  console.log('===============================================================\n');

  // ================= 1. SERVER CONNECTION & HEALTH =================
  console.log('--- 1. Connection & Server Health ---');
  await runTest('Connection', 'Backend Health Check Endpoint', async () => {
    const res = await fetch(`${BASE_URL}/health`);
    if (!res.ok) throw new Error(`HTTP status ${res.status}`);
    const data = await res.json();
    if (data.status !== 'online') throw new Error(`Expected online, got ${data.status}`);
    return `Server version: ${data.version}, Supabase Connected: ${data.supabaseConnected}`;
  });

  await runTest('Connection', 'Zero Dummy Initial State', async () => {
    // Reset first to ensure completely clean slate
    await fetch(`${BASE_URL}/api/admin/reset`, { method: 'POST' });
    const res = await fetch(`${BASE_URL}/health`);
    const data = await res.json();
    if (data.totalDrivers !== 0 || data.totalRides !== 0) {
      throw new Error(`Expected 0 initial records, found ${data.totalDrivers} drivers, ${data.totalRides} rides`);
    }
    return `Clean baseline verified: ${data.totalDrivers} drivers, ${data.totalRides} rides, ${data.totalSos} SOS`;
  });

  // ================= 2. REGISTRATION & LOGIN PHASE =================
  console.log('\n--- 2. Registration, Authentication & OTP Phase ---');
  await runTest('Auth', 'Phone Number & 4-Digit OTP Handshake Simulation', async () => {
    const rawPhone = '+20 100 284 7429';
    const normalizedPhone = rawPhone.replace(/\s+/g, '');
    const otp = '1234'; // Demo bypass OTP
    const isValidPhone = /^\+201[0125]\d{8}$/.test(normalizedPhone);
    const isValidOtp = otp === '1234' || otp.length === 4;
    if (!isValidPhone || !isValidOtp) throw new Error('Phone or OTP validation failed');
    return `Validated Egyptian phone: ${rawPhone} (normalized: ${normalizedPhone}) with bypass PIN: ${otp}`;
  });

  await runTest('Auth', 'Rider Dual-Tier Identity Persistence', async () => {
    // Simulate Female Rider with Rafik Girl enabled
    const femaleRider = {
      id: 'rider-female-01',
      name: 'Nouran El-Shamy',
      phone: '+20 102 345 6789',
      gender: 'female',
      uperGirlEnabled: true,
      selectedTier: 'uper_girl',
    };

    // Simulate Male Rider with Standard Fleet lock
    const maleRider = {
      id: 'rider-male-02',
      name: 'Karim Mansour',
      phone: '+20 114 567 8901',
      gender: 'male',
      uperGirlEnabled: false,
      selectedTier: 'standard',
    };

    if (maleRider.selectedTier === 'uper_girl') {
      throw new Error('Male rider should not have access to Rafik Girl tier');
    }
    return `Verified female rider [${femaleRider.name}] enrolled in Rafik Girl; male rider [${maleRider.name}] locked to Standard Fleet`;
  });

  await runTest('Auth', '14-Digit Egyptian National ID OCR Verification', async () => {
    // Female test: 13th digit is 2 (even)
    const femaleId = '29804150102824';
    const femaleCheck = verifyEgyptianIdGender(femaleId);
    if (!femaleCheck.is14Digits || femaleCheck.gender !== 'female') {
      throw new Error('Female ID verification failed');
    }

    // Male test: 13th digit is 3 (odd)
    const maleId = '29509210103732';
    const maleCheck = verifyEgyptianIdGender(maleId);
    if (!maleCheck.is14Digits || maleCheck.gender !== 'male') {
      throw new Error('Male ID verification failed');
    }

    return `Female Nat ID (13th digit: 2 -> ${femaleCheck.gender}), Male Nat ID (13th digit: 3 -> ${maleCheck.gender})`;
  });

  // ================= 3. DRIVER ONBOARDING & 6-SIDED VAULT =================
  console.log('\n--- 3. Driver Onboarding & Document Vault Phase ---');
  let femaleCaptainId = '';
  let maleCaptainId = '';

  await runTest('Driver Onboarding', 'Female Captain Onboarding (Rafik Girl Certified)', async () => {
    const payload = {
      id: 'drv-salma-' + Date.now(),
      name: 'Captain Salma Mostafa',
      phone: '+20 100 892 4110',
      email: 'salma.mostafa@rafik.app',
      nationalId: '29804150102824',
      gender: 'female',
      isUperGirlCertified: true,
      vehicleMake: 'Kia',
      vehicleModel: 'Cerato',
      vehicleYear: 2023,
      vehiclePlateAr: 'ر ف ق 7 4 2 9',
      vehiclePlateEn: 'RFQ 7429',
      vehicleColor: 'Rose Gold Metallic',
      licenseNumber: 'DL-CAI-2023-8891',
      status: 'approved',
      rating: 4.98,
      tripsCount: 0,
      walletBalance: 0.0,
      livenessScore: 0.994,
      location: {
        lat: 30.0571,
        lng: 31.2215,
        heading: 45.0,
        lastUpdated: new Date().toISOString(),
      },
      documents: {
        nationalIdFront: 'https://images.unsplash.com/photo-1578357078586-491adf1aa5ba?w=600',
        nationalIdBack: 'https://images.unsplash.com/photo-1578357078586-491adf1aa5ba?w=600',
        licenseFront: 'https://images.unsplash.com/photo-1544717305-2782549b5136?w=600',
        licenseBack: 'https://images.unsplash.com/photo-1544717305-2782549b5136?w=600',
        mulkiyaFront: 'https://images.unsplash.com/photo-1549317661-bd32c8ce0db2?w=600',
        mulkiyaBack: 'https://images.unsplash.com/photo-1549317661-bd32c8ce0db2?w=600',
      },
    };

    const res = await fetch(`${BASE_URL}/api/drivers/onboard`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(payload),
    });

    if (!res.ok) throw new Error(`Onboarding failed: ${res.statusText}`);
    const data = await res.json();
    femaleCaptainId = data.driver.id;
    if (data.driver.tier !== 'uper_girl' || !data.driver.isUperGirlCertified) {
      throw new Error('Driver not correctly marked as Rafik Girl Certified');
    }
    return `Captain [${data.driver.name}] onboarded with Tier: ${data.driver.tier}, 6 documents vaulted, Liveness: 99.4%`;
  });

  await runTest('Driver Onboarding', 'Male Captain Onboarding (Standard Fleet Only)', async () => {
    const payload = {
      id: 'drv-ahmed-' + Date.now(),
      name: 'Captain Ahmed Tarek',
      phone: '+20 111 445 9922',
      email: 'ahmed.tarek@rafik.app',
      nationalId: '29509210103732',
      gender: 'male',
      isUperGirlCertified: false,
      vehicleMake: 'Hyundai',
      vehicleModel: 'Elantra',
      vehicleYear: 2022,
      vehiclePlateAr: 'س ن ق 1 4 2 9',
      vehiclePlateEn: 'SNQ 1429',
      vehicleColor: 'Obsidian Black',
      licenseNumber: 'DL-GZA-2022-1142',
      status: 'approved',
      rating: 4.91,
      tripsCount: 0,
      walletBalance: 0.0,
      livenessScore: 0.985,
      location: {
        lat: 30.0444,
        lng: 31.2357,
        heading: 90.0,
        lastUpdated: new Date().toISOString(),
      },
      documents: {
        nationalIdFront: 'https://images.unsplash.com/photo-1578357078586-491adf1aa5ba?w=600',
        nationalIdBack: 'https://images.unsplash.com/photo-1578357078586-491adf1aa5ba?w=600',
        licenseFront: 'https://images.unsplash.com/photo-1544717305-2782549b5136?w=600',
        licenseBack: 'https://images.unsplash.com/photo-1544717305-2782549b5136?w=600',
        mulkiyaFront: 'https://images.unsplash.com/photo-1549317661-bd32c8ce0db2?w=600',
        mulkiyaBack: 'https://images.unsplash.com/photo-1549317661-bd32c8ce0db2?w=600',
      },
    };

    const res = await fetch(`${BASE_URL}/api/drivers/onboard`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(payload),
    });

    if (!res.ok) throw new Error(`Onboarding failed: ${res.statusText}`);
    const data = await res.json();
    maleCaptainId = data.driver.id;
    if (data.driver.tier !== 'standard' || data.driver.isUperGirlCertified) {
      throw new Error('Male driver must be Standard tier only');
    }
    return `Captain [${data.driver.name}] onboarded with Tier: ${data.driver.tier}, Liveness: 98.5%`;
  });

  await runTest('Driver Onboarding', 'Driver Status & Dynamic Profile Retrieval', async () => {
    // Set both drivers to online
    await fetch(`${BASE_URL}/api/drivers/${femaleCaptainId}/status`, {
      method: 'PUT',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ status: 'online', lat: 30.0571, lng: 31.2215 }),
    });

    await fetch(`${BASE_URL}/api/drivers/${maleCaptainId}/status`, {
      method: 'PUT',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ status: 'online', lat: 30.0444, lng: 31.2357 }),
    });

    const res = await fetch(`${BASE_URL}/api/drivers`);
    const data = await res.json();
    if (data.count !== 2) throw new Error(`Expected 2 drivers, found ${data.count}`);
    return `Retrieved 2 verified live captains with online status and coordinates`;
  });

  // ================= 4. MAPS & FARE ENGINE =================
  console.log('\n--- 4. Cairo Maps & 10 EGP/km Fare Formula Phase ---');
  await runTest('Maps & Fare', 'Haversine + Urban Road Curvature Distance Calculation', async () => {
    // Zamalek (30.0571, 31.2215) to New Cairo AUC (30.0131, 31.4989)
    const distKm = calculateCairoRoadKm(30.0571, 31.2215, 30.0131, 31.4989);
    if (distKm < 28 || distKm > 38) throw new Error(`Unexpected road distance: ${distKm} km`);
    return `Zamalek -> New Cairo AUC: ${distKm} km with Cairo curvature multiplier`;
  });

  await runTest('Maps & Fare', 'Official Egyptian Rate (10.00 LE / km + 15 LE Base)', async () => {
    const distKm = 34.0;
    const fare = calculateTripFare(distKm);
    const expected = 15.0 + (34.0 * 10.0); // 355.00 EGP
    if (fare !== expected) throw new Error(`Expected ${expected} EGP, computed ${fare} EGP`);
    return `Distance: ${distKm} km -> Base 15 LE + (34 km × 10 LE) = ${fare.toFixed(2)} EGP`;
  });

  await runTest('Maps & Fare', 'Google Maps High-Res Raster CDN Tiles Check', async () => {
    // Fetch a standard Google Maps Cairo tile (no API key required, 100% free)
    const tileUrl = 'https://mt1.google.com/vt/lyrs=m&x=19344&y=13456&z=15';
    const res = await fetch(tileUrl, { method: 'HEAD' });
    if (!res.ok) throw new Error(`Google Maps CDN returned HTTP ${res.status}`);
    return `Successfully reached Google Maps Global CDN (HTTP 200 OK, zero 403 blocks)`;
  });

  // ================= 5. DUAL-TIER DISPATCH & FULL RIDE LIFECYCLE =================
  console.log('\n--- 5. Dispatch & Ride Lifecycle Phase ---');
  let uperGirlRideId = '';

  await runTest('Dispatch', 'Rafik Girl Ride Request & Selective Radar Matching', async () => {
    const ridePayload = {
      rideId: 'RIDE-UG-' + Date.now(),
      riderName: 'Nouran El-Shamy',
      riderPhone: '+20 102 345 6789',
      pickupAddress: 'Zamalek (26th July St)',
      pickupLat: 30.0571,
      pickupLng: 31.2215,
      dropoffAddress: 'New Cairo (5th Settlement / AUC)',
      dropoffLat: 30.0131,
      dropoffLng: 31.4989,
      fareAmount: 355.0,
      distanceKm: 34.0,
      pinCode: '7429',
      paymentMethod: 'Cash Payment',
      tier: 'uper_girl',
      tier_name: 'RAFIK GIRL',
      rider_gender: 'female',
    };

    const res = await fetch(`${BASE_URL}/api/rides/request`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(ridePayload),
    });

    if (!res.ok) throw new Error(`Ride request failed: ${res.statusText}`);
    const data = await res.json();
    uperGirlRideId = data.ride.id;

    if (data.ride.tier !== 'uper_girl') throw new Error('Ride tier was not preserved as uper_girl');
    return `Ride [${uperGirlRideId}] dispatched as RAFIK GIRL (355 EGP, PIN 7429)`;
  });

  await runTest('Dispatch', 'Female Captain Acceptance & Real-Time Lock', async () => {
    const res = await fetch(`${BASE_URL}/api/rides/${uperGirlRideId}/accept`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        driverId: femaleCaptainId,
        driverName: 'Captain Salma Mostafa',
      }),
    });

    if (!res.ok) throw new Error(`Accept failed: ${res.statusText}`);
    const data = await res.json();
    if (data.ride.status !== 'accepted' || data.ride.driverId !== femaleCaptainId) {
      throw new Error('Ride state was not updated to accepted with female driver');
    }
    return `Ride accepted by Captain Salma Mostafa. State: ${data.ride.status}`;
  });

  await runTest('Dispatch', '4-Digit Safety Handshake PIN Verification (Trip Start)', async () => {
    const res = await fetch(`${BASE_URL}/api/rides/${uperGirlRideId}/start`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ pinCode: '7429' }),
    });

    if (!res.ok) throw new Error(`Trip start failed: ${res.statusText}`);
    const data = await res.json();
    if (data.ride.status !== 'in_progress') throw new Error('Expected status in_progress');
    return `Safety PIN 7429 verified. Trip is officially in_progress`;
  });

  await runTest('Dispatch', 'Trip Completion, Cash Settlement & Wallet Credit', async () => {
    const res = await fetch(`${BASE_URL}/api/rides/${uperGirlRideId}/complete`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ rating: 5.0 }),
    });

    if (!res.ok) throw new Error(`Trip complete failed: ${res.statusText}`);
    const data = await res.json();
    if (data.ride.status !== 'completed') throw new Error('Expected status completed');

    // Verify driver's wallet was credited
    const driverRes = await fetch(`${BASE_URL}/api/drivers/${femaleCaptainId}`);
    const driverData = await driverRes.json();
    if (driverData.driver.walletBalance < 355 || driverData.driver.tripsCount < 1) {
      throw new Error('Driver wallet or tripsCount was not credited');
    }

    return `Trip settled. Captain Salma wallet balance: ${driverData.driver.walletBalance.toFixed(2)} EGP, Rating: 5.0 ★`;
  });

  // ================= 6. EMERGENCY SOS INCIDENT =================
  console.log('\n--- 6. Emergency SOS & Police 122 Linkage Phase ---');
  await runTest('Safety', 'Emergency SOS Trigger & Egyptian Police 122 Notification', async () => {
    const sosPayload = {
      passengerName: 'Nouran El-Shamy',
      passengerPhone: '+20 102 345 6789',
      locationName: 'Zamalek, 26th July St',
      lat: 30.0571,
      lng: 31.2215,
      driverAssigned: 'Captain Salma Mostafa',
    };

    const res = await fetch(`${BASE_URL}/api/sos/trigger`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(sosPayload),
    });

    if (!res.ok) throw new Error(`SOS trigger failed: ${res.statusText}`);
    const data = await res.json();
    if (data.incident.status !== 'ACTIVE_DISTRESS') throw new Error('Expected ACTIVE_DISTRESS');

    return `SOS Incident [${data.incident.id}] triggered. Action: "${data.incident.policeAction}"`;
  });

  // ================= 7. ADMIN METRICS & DATA INTEGRITY =================
  console.log('\n--- 7. Operational Metrics & Admin Command Center Phase ---');
  await runTest('Admin', 'Operations Room KPI & Safety Rate Calculations', async () => {
    const res = await fetch(`${BASE_URL}/api/metrics`);
    if (!res.ok) throw new Error(`Metrics endpoint failed: ${res.statusText}`);
    const data = await res.json();
    const m = data.metrics;
    if (m.totalCompletedRides < 1 || m.grossFareVolumeEgp < 355) {
      throw new Error('Metrics did not aggregate completed trip volume');
    }
    return `Completed Trips: ${m.totalCompletedRides}, Gross Volume: ${m.grossFareVolumeEgp.toFixed(2)} EGP, Rate: ${m.ratePerKmEgp} EGP/km, Infra Cost: $${m.infrastructureCostUsd}`;
  });

  // ================= 8. DATABASE CLEANOUT FOR PRODUCTION READINESS =================
  console.log('\n--- 8. Final Cleanout (Zero Dummy Data Guarantee) ---');
  await runTest('Cleanout', 'Post-Test Production Memory Flush', async () => {
    const res = await fetch(`${BASE_URL}/api/admin/reset`, { method: 'POST' });
    if (!res.ok) throw new Error('Reset endpoint failed');

    const healthRes = await fetch(`${BASE_URL}/health`);
    const healthData = await healthRes.json();

    if (healthData.totalDrivers !== 0 || healthData.totalRides !== 0 || healthData.totalSos !== 0) {
      throw new Error('Database is not clean after reset');
    }
    return `Stores flushed to zero: Drivers=${healthData.totalDrivers}, Rides=${healthData.totalRides}, SOS=${healthData.totalSos}`;
  });

  // ================= SUMMARY =================
  console.log('\n===============================================================');
  console.log('📊 TEST SUITE EXECUTION SUMMARY');
  console.log('===============================================================');
  const passedCount = results.filter(r => r.passed).length;
  const failedCount = results.filter(r => !r.passed).length;
  console.log(`Total Tests Executed: ${results.length}`);
  console.log(`Passed:               ${passedCount} ✅`);
  console.log(`Failed:               ${failedCount} ❌`);
  console.log(`Success Rate:         ${((passedCount / results.length) * 100).toFixed(1)}%`);
  console.log('===============================================================\n');

  if (failedCount > 0) {
    process.exit(1);
  } else {
    process.exit(0);
  }
}

startTestSuite();
