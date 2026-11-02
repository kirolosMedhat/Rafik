/**
 * Rafik Enterprise Domain Models & Type Definitions
 */

export type UserRole = 'rider' | 'driver' | 'admin';
export type UserGender = 'female' | 'male';
export type DriverStatus = 'pending' | 'approved' | 'rejected' | 'suspended';
export type RideTier = 'standard' | 'rafik_girl';
export type RideStatus = 'requested' | 'accepted' | 'arrived' | 'in_progress' | 'completed' | 'cancelled' | 'expired';
export type OfferStatus = 'pending' | 'accepted' | 'declined' | 'expired' | 'cancelled';
export type PaymentMethod = 'cash' | 'wallet' | 'card';
export type PaymentKind = 'trip_earnings' | 'cash_collection' | 'payout' | 'adjustment';
export type SosStatus = 'active' | 'investigating' | 'resolved';

export interface UserProfile {
  uid: string;
  phone: string;
  full_name: string;
  email?: string | null;
  role: UserRole;
  gender: UserGender;
  gender_verified: boolean;
  language: 'en' | 'ar';
  is_active: boolean;
  created_at: FirebaseFirestore.Timestamp | FirebaseFirestore.FieldValue;
  updated_at?: FirebaseFirestore.Timestamp | FirebaseFirestore.FieldValue;
}

export interface DriverProfile {
  driver_id: string;
  national_id_number: string;
  license_number: string;
  status: DriverStatus;
  rejection_reason?: string | null;
  is_online: boolean;
  is_busy: boolean;
  current_ride_id?: string | null;
  total_trips: number;
  wallet_balance_egp: number;
  rating_avg: number;
  approved_by?: string | null;
  approved_at?: FirebaseFirestore.Timestamp | null;
  created_at: FirebaseFirestore.Timestamp | FirebaseFirestore.FieldValue;
  updated_at?: FirebaseFirestore.Timestamp | FirebaseFirestore.FieldValue;
}

export interface VehicleProfile {
  driver_id: string;
  make: string;
  model: string;
  year: number;
  plate_number: string;
  color: string;
  tier_eligibility: RideTier[];
  created_at: FirebaseFirestore.Timestamp | FirebaseFirestore.FieldValue;
  updated_at?: FirebaseFirestore.Timestamp | FirebaseFirestore.FieldValue;
}

export interface RideDocument {
  ride_id: string;
  rider_id: string;
  rider_name: string;
  rider_phone: string;
  driver_id?: string | null;
  driver_name?: string | null;
  driver_phone?: string | null;
  vehicle_plate?: string | null;
  vehicle_model?: string | null;
  tier: RideTier;
  status: RideStatus;
  pickup_address: string;
  pickup_lat: number;
  pickup_lng: number;
  dropoff_address: string;
  dropoff_lat: number;
  dropoff_lng: number;
  distance_km: number;
  fare_egp: number;
  driver_earnings_egp: number;
  platform_fee_egp: number;
  payment_method: PaymentMethod;
  attempts: number;
  requested_at: FirebaseFirestore.Timestamp | FirebaseFirestore.FieldValue;
  expires_at: FirebaseFirestore.Timestamp;
  accepted_at?: FirebaseFirestore.Timestamp | null;
  arrived_at?: FirebaseFirestore.Timestamp | null;
  started_at?: FirebaseFirestore.Timestamp | null;
  completed_at?: FirebaseFirestore.Timestamp | null;
  cancelled_at?: FirebaseFirestore.Timestamp | null;
  cancelled_by?: string | null;
  cancellation_reason?: string | null;
  rider_rating?: number | null;
  driver_rating?: number | null;
  review?: string | null;
}

export interface RidePinDocument {
  pin: string;
  attempts: number;
  is_locked: boolean;
  created_at: FirebaseFirestore.Timestamp | FirebaseFirestore.FieldValue;
}

export interface RideOfferDocument {
  offer_id: string;
  ride_id: string;
  driver_id: string;
  tier: RideTier;
  pickup_address: string;
  dropoff_address: string;
  distance_km: number;
  fare_egp: number;
  status: OfferStatus;
  offered_at: FirebaseFirestore.Timestamp | FirebaseFirestore.FieldValue;
  expires_at: FirebaseFirestore.Timestamp;
}

export interface RTDBDriverLocation {
  lat: number;
  lng: number;
  heading?: number;
  speed_kmh?: number;
  geohash?: string;
  tier?: RideTier | 'both';
  gender?: UserGender;
  gender_verified?: boolean;
  is_online?: boolean;
  is_busy?: boolean;
  status?: DriverStatus;
  updated_at: number;
}

export interface PlatformSettings {
  pricing: {
    base_fare_egp: number;
    per_km_rate_egp: number;
    min_fare_egp: number;
    cairo_traffic_multiplier: number;
    platform_commission_rate: number; // e.g. 0.0 for 0%
    night_multiplier: number;
    rafik_girl_premium_multiplier: number;
  };
  dispatch: {
    initial_radius_km: number; // default: 3.0 KM
    expanded_radius_km: number; // default: 5.0 KM
    max_radius_km: number; // default: 7.0 KM
    offer_timeout_seconds: number; // default: 30s
    ride_request_ttl_seconds: number; // default: 120s
    max_candidate_drivers: number; // default: 10
    driver_heartbeat_timeout_seconds: number; // default: 60s
  };
  safety: {
    max_pin_attempts: number; // default: 3
    require_national_id_parity_for_female: boolean; // default: true
    max_arrival_distance_meters: number; // default: 200m
  };
}
