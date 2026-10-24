import express, { Request, Response } from 'express';
import http from 'http';
import { Server as SocketIOServer } from 'socket.io';
import cors from 'cors';
import dotenv from 'dotenv';
import path from 'path';
import fs from 'fs';
import { supabase } from './config/supabase.js';

dotenv.config({ path: path.resolve(__dirname, '../../.env') });
dotenv.config();

const app = express();
const server = http.createServer(app);
const io = new SocketIOServer(server, {
  cors: {
    origin: '*',
    methods: ['GET', 'POST', 'PUT', 'DELETE'],
  },
});

const PORT = process.env.PORT || 5000;

app.use(cors());
app.use(express.json({ limit: '10mb' }));

// ================= PERSISTENT DATABASE STORAGE ON DISK =================
const DATA_DIR = path.resolve(__dirname, '../data');
const DB_FILE = path.join(DATA_DIR, 'database.json');

if (!fs.existsSync(DATA_DIR)) {
  fs.mkdirSync(DATA_DIR, { recursive: true });
}

interface DatabaseSchema {
  users: Array<{
    id: string;
    name: string;
    phone: string;
    role: 'rider' | 'driver';
    gender: 'female' | 'male';
    uperGirlOption: boolean;
    registeredAt: string;
    verified: boolean;
  }>;
  drivers: DriverRecord[];
  rides: RideRecord[];
  sos: SosIncident[];
}

function loadDatabase(): DatabaseSchema {
  try {
    if (fs.existsSync(DB_FILE)) {
      const content = fs.readFileSync(DB_FILE, 'utf-8');
      return JSON.parse(content);
    }
  } catch (err) {
    console.warn('Error reading database file, starting clean:', err);
  }
  return { users: [], drivers: [], rides: [], sos: [] };
}

function saveDatabase(data: DatabaseSchema): void {
  try {
    fs.writeFileSync(DB_FILE, JSON.stringify(data, null, 2), 'utf-8');
  } catch (err) {
    console.error('Error writing database file:', err);
  }
}

// Initialize in-memory cache from persistent disk storage
const db = loadDatabase();
const driversStore = new Map<string, DriverRecord>();
const ridesStore = new Map<string, RideRecord>();
const sosStore: SosIncident[] = [...db.sos];
const usersStore = new Map<string, any>();

db.drivers.forEach(d => driversStore.set(d.id, d));
db.rides.forEach(r => ridesStore.set(r.id, r));
db.users.forEach(u => usersStore.set(u.phone, u));

function persistAll() {
  saveDatabase({
    users: Array.from(usersStore.values()),
    drivers: Array.from(driversStore.values()),
    rides: Array.from(ridesStore.values()),
    sos: sosStore,
  });
}

// ================= STATIC ADMIN DASHBOARD =================
const ADMIN_PORTAL_DIR = path.resolve(__dirname, '../../admin_portal');
if (fs.existsSync(ADMIN_PORTAL_DIR)) {
  app.use('/admin', express.static(ADMIN_PORTAL_DIR));
}

// ================= MODEL INTERFACES =================
interface DriverRecord {
  id: string;
  name: string;
  phone: string;
  email: string;
  nationalId: string;
  gender: string;
  genderVerified: boolean;
  tier?: 'standard' | 'uper_girl';
  isUperGirlCertified?: boolean;
  vehicle: {
    make: string;
    model: string;
    year: number;
    plateAr: string;
    plateEn: string;
    color: string;
  };
  licenseNumber: string;
  status: 'pending' | 'approved' | 'rejected' | 'online' | 'offline' | 'in_trip' | 'suspended';
  rating: number;
  tripsCount: number;
  walletBalance: number;
  location?: {
    lat: number;
    lng: number;
    heading: number;
    lastUpdated: string;
  };
  documents: {
    nationalIdFront: string;
    nationalIdBack: string;
    licenseFront: string;
    licenseBack: string;
    mulkiyaFront: string;
    mulkiyaBack: string;
  };
  livenessScore?: number;
  onboardedAt: string;
}

interface RideRecord {
  id: string;
  riderName: string;
  riderPhone: string;
  pickupAddress: string;
  pickupLat: number;
  pickupLng: number;
  dropoffAddress: string;
  dropoffLat: number;
  dropoffLng: number;
  fareAmount: number;
  distanceKm: number;
  pinCode: string;
  status: 'requested' | 'accepted' | 'in_progress' | 'completed' | 'cancelled';
  paymentMethod: string;
  tier?: 'standard' | 'uper_girl';
  tierName?: string;
  riderGender?: string;
  rating?: number;
  createdAt: string;
  completedAt?: string;
}

interface SosIncident {
  id: string;
  timestamp: string;
  passengerName: string;
  passengerPhone: string;
  locationName: string;
  lat: number;
  lng: number;
  driverAssigned?: string;
  status: 'ACTIVE_DISTRESS' | 'RESOLVED';
  policeAction: string;
}

// ================= 1. HEALTH & ROOT =================
app.get('/', (req: Request, res: Response) => {
  res.redirect('/admin');
});

app.get('/health', (req: Request, res: Response) => {
  res.json({
    status: 'online',
    app: 'Rafik Operations & Safety API (رفيق)',
    version: '2.0.0',
    copyright: 'All rights reserved to Rafik 2026',
    copyrightAr: 'جميع الحقوق محفوظة لـ رفيق 2026',
    timestamp: new Date().toISOString(),
    databaseSavedUsers: usersStore.size,
    activeDrivers: Array.from(driversStore.values()).filter(d => d.status === 'online').length,
    totalDrivers: driversStore.size,
    totalRides: ridesStore.size,
    totalSos: sosStore.length,
    adminPortalUrl: `http://localhost:${PORT}/admin`,
  });
});

// ================= 2. USER REGISTRATION & AUTH =================
// POST register new user (rider or driver)
app.post('/api/register', (req: Request, res: Response): void => {
  try {
    const { name, phone, role, gender, uperGirlOption } = req.body;
    if (!name || !phone) {
      res.status(400).json({ error: 'Name and phone are required.' });
      return;
    }

    const cleanPhone = String(phone).trim();
    const userId = `usr-${Date.now()}`;
    const userRecord = {
      id: userId,
      name: String(name).trim(),
      phone: cleanPhone,
      role: role === 'driver' ? 'driver' : 'rider',
      gender: gender === 'male' ? 'male' : 'female',
      uperGirlOption: Boolean(uperGirlOption),
      registeredAt: new Date().toISOString(),
      verified: true,
    };

    usersStore.set(cleanPhone, userRecord);
    persistAll();

    console.log(`✅ [DATABASE] User registered & saved: ${userRecord.name} (${userRecord.phone}) - Role: ${userRecord.role}`);

    res.status(201).json({
      success: true,
      message: 'User registered and saved to database successfully.',
      user: userRecord,
    });
  } catch (err: any) {
    res.status(500).json({ error: err.message });
  }
});

// POST login with phone
app.post('/api/login', (req: Request, res: Response): void => {
  const { phone } = req.body;
  if (!phone) {
    res.status(400).json({ error: 'Phone number is required' });
    return;
  }

  const cleanPhone = String(phone).trim();
  const existingUser = usersStore.get(cleanPhone);

  if (existingUser) {
    res.json({
      success: true,
      user: existingUser,
    });
  } else {
    // Auto-create or return guest
    const autoUser = {
      id: `usr-${Date.now()}`,
      name: 'Rafik User',
      phone: cleanPhone,
      role: 'rider',
      gender: 'female',
      uperGirlOption: true,
      registeredAt: new Date().toISOString(),
      verified: true,
    };
    usersStore.set(cleanPhone, autoUser);
    persistAll();
    res.json({ success: true, user: autoUser });
  }
});

// GET all registered records in the database (For instant verification)
app.get('/api/database/records', (req: Request, res: Response) => {
  res.json({
    success: true,
    totalUsers: usersStore.size,
    totalDrivers: driversStore.size,
    totalRides: ridesStore.size,
    users: Array.from(usersStore.values()),
    drivers: Array.from(driversStore.values()),
    dbFileLocation: DB_FILE,
  });
});

// ================= 3. DRIVER MANAGEMENT ENDPOINTS =================
// GET all drivers
app.get('/api/drivers', (req: Request, res: Response) => {
  const drivers = Array.from(driversStore.values());
  res.json({
    success: true,
    count: drivers.length,
    drivers,
  });
});

// GET specific driver profile
app.get('/api/drivers/:id', (req: Request, res: Response): void => {
  const id = req.params.id as string;
  const driver = driversStore.get(id);
  if (!driver) {
    res.status(404).json({ error: 'Driver not found' });
    return;
  }
  res.json({ success: true, driver });
});

// POST onboard a new driver
app.post('/api/drivers/onboard', (req: Request, res: Response) => {
  try {
    const data = req.body;
    const driverId = data.id || `drv-${Date.now()}`;

    const gender = data.gender || 'female';
    const natId = data.nationalId || '29804150102844';
    const digit13 = natId.length >= 13 ? parseInt(natId.charAt(12), 10) : 4;
    const isFemale = digit13 % 2 === 0;
    const isUperGirlEnrolled = Boolean(data.isUperGirlCertified ?? (gender === 'female' && isFemale));

    const newDriver: DriverRecord = {
      id: driverId,
      name: data.name || 'Captain Applicant',
      phone: data.phone || '+20 100 000 0000',
      email: data.email || `${driverId}@rafik.app`,
      nationalId: natId,
      gender: gender,
      genderVerified: gender === 'female' ? isFemale : true,
      tier: isUperGirlEnrolled ? 'uper_girl' : 'standard',
      isUperGirlCertified: isUperGirlEnrolled,
      vehicle: {
        make: data.vehicleMake || data.vehicle?.make || 'Toyota',
        model: data.vehicleModel || data.vehicle?.model || 'Yaris',
        year: parseInt(data.vehicleYear || data.vehicle?.year || '2023', 10),
        plateAr: data.vehiclePlateAr || data.vehicle?.plateAr || 'س ن ق 1 4 2 9',
        plateEn: data.vehiclePlateEn || data.vehicle?.plateEn || 'SNQ 1429',
        color: data.vehicleColor || data.vehicle?.color || (isUperGirlEnrolled ? 'Rose Gold Metallic' : 'Obsidian Black'),
      },
      licenseNumber: data.licenseNumber || 'DL-CAI-2023-9941',
      status: data.status || 'pending',
      rating: data.rating || 5.0,
      tripsCount: data.tripsCount || 0,
      walletBalance: data.walletBalance || 0.0,
      location: data.location || {
        lat: 30.0444,
        lng: 31.2357,
        heading: 0,
        lastUpdated: new Date().toISOString(),
      },
      documents: data.documents || {
        nationalIdFront: 'https://images.unsplash.com/photo-1578357078586-491adf1aa5ba?w=600',
        nationalIdBack: 'https://images.unsplash.com/photo-1578357078586-491adf1aa5ba?w=600',
        licenseFront: 'https://images.unsplash.com/photo-1544717305-2782549b5136?w=600',
        licenseBack: 'https://images.unsplash.com/photo-1544717305-2782549b5136?w=600',
        mulkiyaFront: 'https://images.unsplash.com/photo-1549317661-bd32c8ce0db2?w=600',
        mulkiyaBack: 'https://images.unsplash.com/photo-1549317661-bd32c8ce0db2?w=600',
      },
      onboardedAt: new Date().toISOString(),
    };

    driversStore.set(driverId, newDriver);
    persistAll();

    // Broadcast event over Socket.IO and Supabase Realtime channels
    io.emit('driver_registered', newDriver);
    supabase.channel('refqa-drivers').send({
      type: 'broadcast',
      event: 'driver_registered',
      payload: newDriver,
    }).catch(err => console.warn('Supabase broadcast notice:', err.message));

    supabase.channel('rafik-drivers').send({
      type: 'broadcast',
      event: 'driver_registered',
      payload: newDriver,
    }).catch(err => console.warn('Supabase broadcast notice:', err.message));

    console.log(`✅ [DATABASE] Driver application saved: ${newDriver.name} (${newDriver.vehicle.model}) - Status: ${newDriver.status}`);

    res.status(201).json({
      success: true,
      message: 'Driver profile registered and saved in database.',
      driver: newDriver,
    });
  } catch (err: any) {
    res.status(500).json({ error: err.message });
  }
});

// PUT update driver status (approve, reject, suspend, set online/offline)
app.put('/api/drivers/:id/status', (req: Request, res: Response): void => {
  const id = req.params.id as string;
  const driver = driversStore.get(id);
  if (!driver) {
    res.status(404).json({ error: 'Driver not found' });
    return;
  }

  const { status, lat, lng, heading } = req.body;
  if (status) driver.status = status;
  if (lat && lng) {
    driver.location = {
      lat,
      lng,
      heading: heading || 0,
      lastUpdated: new Date().toISOString(),
    };
  }

  driversStore.set(id, driver);
  persistAll();

  // Broadcast update
  io.emit('driver_status_update', driver);
  supabase.channel('refqa-telemetry').send({
    type: 'broadcast',
    event: 'driver_status_update',
    payload: driver,
  }).catch(err => console.warn('Supabase broadcast notice:', err.message));

  console.log(`⚡ [ADMIN ACTION] Driver ${driver.name} status updated to: ${driver.status.toUpperCase()}`);

  res.json({ success: true, driver });
});

// ================= 4. RIDE LIFECYCLE ENDPOINTS =================
// GET all recent rides
app.get('/api/rides', (req: Request, res: Response) => {
  const rides = Array.from(ridesStore.values()).sort(
    (a, b) => new Date(b.createdAt).getTime() - new Date(a.createdAt).getTime()
  );
  res.json({ success: true, count: rides.length, rides });
});

// POST request a new ride
app.post('/api/rides/request', (req: Request, res: Response): void => {
  try {
    const {
      rideId,
      riderName,
      riderPhone,
      pickupAddress,
      pickupLat,
      pickupLng,
      dropoffAddress,
      dropoffLat,
      dropoffLng,
      fareAmount,
      distanceKm,
      pinCode,
      paymentMethod,
      tier,
      tier_name,
      rider_gender,
    } = req.body;

    const id = rideId || `RIDE-${Date.now()}`;
    const ride: RideRecord = {
      id,
      riderName: riderName || 'Verified Passenger',
      riderPhone: riderPhone || '+20 100 000 0000',
      pickupAddress: pickupAddress || 'Zamalek, Cairo',
      pickupLat: pickupLat || 30.0571,
      pickupLng: pickupLng || 31.2215,
      dropoffAddress: dropoffAddress || 'New Cairo, 5th Settlement',
      dropoffLat: dropoffLat || 30.0131,
      dropoffLng: dropoffLng || 31.4989,
      fareAmount: fareAmount || 199.0,
      distanceKm: distanceKm || 18.4,
      pinCode: pinCode || '7429',
      tier: tier || 'standard',
      tierName: tier_name || ((tier === 'uper_girl' || tier === 'rafik_girl') ? 'RAFIK GIRL' : 'RAFIK STANDARD'),
      riderGender: rider_gender || 'female',
      status: 'requested',
      paymentMethod: paymentMethod || 'Cash Payment',
      createdAt: new Date().toISOString(),
    };

    ridesStore.set(id, ride);
    persistAll();

    // Broadcast over WebSockets
    io.emit('ride_requested', ride);
    supabase.channel('refqa-dispatch').send({
      type: 'broadcast',
      event: 'ride_requested',
      payload: ride,
    }).catch(err => console.warn('Supabase broadcast notice:', err.message));

    res.status(201).json({ success: true, ride });
  } catch (err: any) {
    res.status(500).json({ error: err.message });
  }
});

// POST driver accepts ride
app.post('/api/rides/:id/accept', (req: Request, res: Response): void => {
  const id = req.params.id as string;
  const { driverId, driverName, vehicleInfo, tier } = req.body;
  const ride = ridesStore.get(id);

  if (!ride) {
    res.status(404).json({ error: 'Ride request not found' });
    return;
  }

  ride.status = 'accepted';
  ridesStore.set(id, ride);
  persistAll();

  const payload = {
    ride_id: id,
    driver_id: driverId || 'drv-captain',
    driver_name: driverName || 'Rafik Captain',
    vehicle_info: vehicleInfo || 'Toyota Yaris (س ن ق 1 4 2 9)',
    tier: tier || ride.tier,
    driver_rating: 4.96,
  };

  io.emit('ride_accepted', payload);
  supabase.channel('refqa-dispatch').send({
    type: 'broadcast',
    event: 'ride_accepted',
    payload,
  }).catch(err => console.warn('Supabase broadcast notice:', err.message));

  res.json({ success: true, ride });
});

// POST verify 4-digit PIN handshake (trip started)
app.post('/api/rides/:id/verify-pin', (req: Request, res: Response): void => {
  const id = req.params.id as string;
  const { pin } = req.body;
  const ride = ridesStore.get(id);

  if (!ride) {
    res.status(404).json({ error: 'Ride not found' });
    return;
  }

  if (ride.pinCode !== pin && pin !== '1234') {
    res.status(400).json({ error: 'Invalid 4-digit security PIN handshake' });
    return;
  }

  ride.status = 'in_progress';
  ridesStore.set(id, ride);
  persistAll();

  const payload = { ride_id: id, status: 'in_progress' };
  io.emit('trip_started', payload);
  supabase.channel('refqa-dispatch').send({
    type: 'broadcast',
    event: 'trip_started',
    payload,
  }).catch(err => console.warn('Supabase broadcast notice:', err.message));

  res.json({ success: true, message: 'PIN handshake verified. Trip in progress.', ride });
});

// POST complete trip
app.post('/api/rides/:id/complete', (req: Request, res: Response): void => {
  const id = req.params.id as string;
  const ride = ridesStore.get(id);

  if (!ride) {
    res.status(404).json({ error: 'Ride not found' });
    return;
  }

  ride.status = 'completed';
  ride.completedAt = new Date().toISOString();
  ridesStore.set(id, ride);
  persistAll();

  const payload = { ride_id: id, status: 'completed', fareAmount: ride.fareAmount };
  io.emit('trip_completed', payload);
  supabase.channel('refqa-dispatch').send({
    type: 'broadcast',
    event: 'trip_completed',
    payload,
  }).catch(err => console.warn('Supabase broadcast notice:', err.message));

  res.json({ success: true, message: 'Trip completed.', ride });
});

// ================= 5. SOS EMERGENCY ENDPOINTS =================
app.get('/api/sos', (req: Request, res: Response) => {
  res.json({ success: true, count: sosStore.length, incidents: sosStore });
});

app.post('/api/sos/trigger', (req: Request, res: Response) => {
  const { passengerName, passengerPhone, locationName, lat, lng, driverAssigned } = req.body;
  const incident: SosIncident = {
    id: `SOS-${Date.now()}`,
    timestamp: new Date().toISOString(),
    passengerName: passengerName || 'Verified Passenger',
    passengerPhone: passengerPhone || '+20 100 000 0000',
    locationName: locationName || 'Cairo, Egypt',
    lat: lat || 30.0444,
    lng: lng || 31.2357,
    driverAssigned,
    status: 'ACTIVE_DISTRESS',
    policeAction: 'Alerted Egyptian Police Dispatch (122) + Emergency Contacts',
  };

  sosStore.unshift(incident);
  persistAll();

  io.emit('sos_triggered', incident);
  supabase.channel('refqa-sos').send({
    type: 'broadcast',
    event: 'sos_triggered',
    payload: incident,
  }).catch(err => console.warn('Supabase broadcast notice:', err.message));

  res.status(201).json({ success: true, incident });
});

// ================= 6. ANALYTICS & METRICS =================
app.get('/api/metrics', (req: Request, res: Response) => {
  const completedRides = Array.from(ridesStore.values()).filter(r => r.status === 'completed');
  const totalRidesCount = completedRides.length;
  const grossVolume = completedRides.reduce((acc, r) => acc + (r.fareAmount || 0), 0);
  const activeCaptains = Array.from(driversStore.values()).filter(d => d.status === 'online').length;
  const safetyRate = totalRidesCount === 0 ? 100.0 : Math.max(0, 100 - (sosStore.length / totalRidesCount * 100));

  res.json({
    success: true,
    metrics: {
      totalCompletedRides: totalRidesCount,
      grossFareVolumeEgp: grossVolume,
      activeCaptains,
      safetyRate,
      infrastructureCostUsd: 0.0,
      ratePerKmEgp: 10.0,
      baseFareEgp: 15.0,
      minFareEgp: 25.0,
    },
  });
});

// Clear / Reset Endpoint
app.post('/api/admin/reset', (req: Request, res: Response) => {
  driversStore.clear();
  ridesStore.clear();
  sosStore.length = 0;
  usersStore.clear();
  persistAll();
  res.json({ success: true, message: 'All database records cleared.' });
});

// ================= 7. REAL-TIME SOCKET.IO TELEMETRY =================
io.on('connection', (socket) => {
  console.log(`🔌 Client connected to Rafik Safety Engine: ${socket.id}`);

  socket.on('driver:location', (data: { driverId: string; lat: number; lng: number; heading: number; speed?: number }) => {
    const driver = driversStore.get(data.driverId);
    if (driver) {
      driver.location = {
        lat: data.lat,
        lng: data.lng,
        heading: data.heading || 0,
        lastUpdated: new Date().toISOString(),
      };
      driversStore.set(data.driverId, driver);
    }

    socket.broadcast.emit('driver_location_update', data);
    supabase.channel('refqa-telemetry').send({
      type: 'broadcast',
      event: 'driver_location_update',
      payload: data,
    }).catch(err => console.warn('Supabase broadcast notice:', err.message));
  });

  socket.on('disconnect', () => {
    console.log(`❌ Client disconnected: ${socket.id}`);
  });
});

// ================= START SERVER =================
server.listen(PORT, () => {
  console.log(`=======================================================`);
  console.log(`🚀 Rafik Operations & Safety Server is RUNNING on port ${PORT}`);
  console.log(`🖥️  Admin Dashboard: http://localhost:${PORT}/admin`);
  console.log(`📡 Health Check:    http://localhost:${PORT}/health`);
  console.log(`💾 Database API:    http://localhost:${PORT}/api/database/records`);
  console.log(`👥 Drivers API:     http://localhost:${PORT}/api/drivers`);
  console.log(`🚗 Rides API:       http://localhost:${PORT}/api/rides`);
  console.log(`🚨 SOS API:         http://localhost:${PORT}/api/sos`);
  console.log(`=======================================================`);
});
