/**
 * Rafik User Registration & Role Claims Engine
 * Strict differentiation between Login and Registration.
 * No silent profile creation.
 */

import * as admin from 'firebase-admin';
import { nationalIdGender, normalizeEgyptianPhone } from './spatial.js';
import { DriverProfile, UserGender, UserProfile, UserRole, VehicleProfile } from './types.js';

export interface RegisterProfilePayload {
  full_name: string;
  gender: UserGender;
  role: UserRole;
  email?: string;
  // Captain-specific fields
  national_id_number?: string;
  license_number?: string;
  vehicle_make?: string;
  vehicle_model?: string;
  vehicle_year?: number;
  vehicle_plate?: string;
  vehicle_color?: string;
}

export async function executeRegisterUserProfile(
  callerUid: string,
  callerPhone: string | undefined,
  payload: RegisterProfilePayload
): Promise<{ success: boolean; role: UserRole; status?: string }> {
  const db = admin.firestore();

  // 1. Verify User Document Does Not Already Exist
  const existingUser = await db.collection('users').doc(callerUid).get();
  if (existingUser.exists) {
    throw new Error('ACCOUNT_ALREADY_EXISTS: A profile already exists for this account. Please log in.');
  }

  // 2. Normalize and Verify Phone Number
  const phone = callerPhone ? normalizeEgyptianPhone(callerPhone) : null;
  if (!phone) {
    throw new Error('INVALID_PHONE: Caller does not have a verified Egyptian mobile number.');
  }

  const batch = db.batch();
  const userRef = db.collection('users').doc(callerUid);

  const baseUserData: UserProfile = {
    uid: callerUid,
    phone: phone,
    full_name: payload.full_name.trim(),
    email: payload.email?.trim() || null,
    role: payload.role,
    gender: payload.gender,
    gender_verified: false, // Default false until admin KYC verification
    language: 'ar',
    is_active: true,
    created_at: admin.firestore.FieldValue.serverTimestamp(),
    updated_at: admin.firestore.FieldValue.serverTimestamp(),
  };

  batch.set(userRef, baseUserData);

  if (payload.role === 'rider') {
    // 3. Create Rider Profile
    const riderRef = db.collection('riders').doc(callerUid);
    batch.set(riderRef, {
      rider_id: callerUid,
      rating_avg: 5.0,
      total_rides: 0,
      default_payment_method: 'cash',
      emergency_contacts: [],
      created_at: admin.firestore.FieldValue.serverTimestamp(),
      updated_at: admin.firestore.FieldValue.serverTimestamp(),
    });

    await batch.commit();

    // 4. Set Custom Claims
    await admin.auth().setCustomUserClaims(callerUid, {
      role: 'rider',
      rider: true,
      gender_verified: false,
    });

    return { success: true, role: 'rider' };

  } else if (payload.role === 'driver') {
    // 5. Validate Captain & Vehicle Details
    const nid = payload.national_id_number?.trim();
    if (!nid || !/^[23]\d{13}$/.test(nid)) {
      throw new Error('INVALID_NATIONAL_ID: Egyptian National ID must be exactly 14 digits.');
    }

    if (payload.gender === 'female') {
      const derivedGender = nationalIdGender(nid);
      if (derivedGender !== 'female') {
        throw new Error('GENDER_PARITY_MISMATCH: National ID 13th digit indicates male identity.');
      }
    }

    const driverRef = db.collection('drivers').doc(callerUid);
    const driverData: DriverProfile = {
      driver_id: callerUid,
      national_id_number: nid,
      license_number: payload.license_number?.trim() || `LIC-${nid}`,
      status: 'pending', // Starts strictly in pending review
      rejection_reason: null,
      is_online: false,
      is_busy: false,
      current_ride_id: null,
      total_trips: 0,
      wallet_balance_egp: 0.0,
      rating_avg: 5.0,
      created_at: admin.firestore.FieldValue.serverTimestamp(),
      updated_at: admin.firestore.FieldValue.serverTimestamp(),
    };
    batch.set(driverRef, driverData);

    // 6. Create Vehicle Profile
    const vehicleRef = db.collection('vehicles').doc(callerUid);
    const vehicleData: VehicleProfile = {
      driver_id: callerUid,
      make: payload.vehicle_make?.trim() || 'Sedan',
      model: payload.vehicle_model?.trim() || 'Standard',
      year: payload.vehicle_year || 2022,
      plate_number: payload.vehicle_plate?.trim() || 'Cairo Plate',
      color: payload.vehicle_color?.trim() || 'Black',
      tier_eligibility: payload.gender === 'female' ? ['standard', 'rafik_girl'] : ['standard'],
      created_at: admin.firestore.FieldValue.serverTimestamp(),
      updated_at: admin.firestore.FieldValue.serverTimestamp(),
    };
    batch.set(vehicleRef, vehicleData);

    await batch.commit();

    // 7. Set Custom Claims: Approved is strictly false
    await admin.auth().setCustomUserClaims(callerUid, {
      role: 'driver',
      driver: true,
      approved: false, // Locked until admin review
      gender_verified: false,
    });

    return { success: true, role: 'driver', status: 'pending' };
  } else {
    throw new Error('INVALID_ROLE: Role must be either rider or driver.');
  }
}
