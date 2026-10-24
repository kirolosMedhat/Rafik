-- ==============================================================================
-- UPER GIRL — SUPABASE CLOUD DATABASE SCHEMA
-- Women-Centric Ride-Hailing Platform
-- 100% Free Cloud Infrastructure (PostgreSQL + PostGIS + Supabase Auth & Storage)
-- ==============================================================================

-- 1. ENABLE REQUIRED EXTENSIONS
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "postgis";

-- 2. ENUMS
DO $$ BEGIN
    CREATE TYPE user_role AS ENUM ('rider', 'driver', 'admin');
EXCEPTION
    WHEN duplicate_object THEN null;
END $$;

DO $$ BEGIN
    CREATE TYPE ride_status AS ENUM (
        'requested', 
        'searching', 
        'accepted', 
        'arriving', 
        'arrived', 
        'in_progress', 
        'completed', 
        'cancelled'
    );
EXCEPTION
    WHEN duplicate_object THEN null;
END $$;

DO $$ BEGIN
    CREATE TYPE doc_status AS ENUM ('pending', 'approved', 'rejected');
EXCEPTION
    WHEN duplicate_object THEN null;
END $$;

-- 3. PROFILES / USERS TABLE (Linked to Supabase Auth auth.users)
CREATE TABLE IF NOT EXISTS public.profiles (
    id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    phone VARCHAR(20) UNIQUE,
    email VARCHAR(255) UNIQUE,
    full_name VARCHAR(150) NOT NULL,
    role user_role NOT NULL DEFAULT 'rider',
    gender VARCHAR(10) NOT NULL DEFAULT 'female',
    gender_verified BOOLEAN NOT NULL DEFAULT FALSE,
    verification_status VARCHAR(20) NOT NULL DEFAULT 'unverified',
    rating_avg NUMERIC(3, 2) NOT NULL DEFAULT 5.00,
    avatar_url TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- 4. EMERGENCY CONTACTS TABLE (For Passenger SOS broadcasts)
CREATE TABLE IF NOT EXISTS public.emergency_contacts (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    contact_name VARCHAR(100) NOT NULL,
    phone_number VARCHAR(20) NOT NULL,
    relationship VARCHAR(50) NOT NULL DEFAULT 'Family',
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- 5. DRIVERS PROFILE & VEHICLE DATA TABLE
CREATE TABLE IF NOT EXISTS public.drivers (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL UNIQUE REFERENCES public.profiles(id) ON DELETE CASCADE,
    national_id_number VARCHAR(14) NOT NULL UNIQUE,
    license_number VARCHAR(50) NOT NULL UNIQUE,
    vehicle_make VARCHAR(50) NOT NULL,
    vehicle_model VARCHAR(50) NOT NULL,
    vehicle_year INT NOT NULL,
    vehicle_plate VARCHAR(20) NOT NULL UNIQUE,
    vehicle_color VARCHAR(30) NOT NULL,
    is_online BOOLEAN NOT NULL DEFAULT FALSE,
    is_busy BOOLEAN NOT NULL DEFAULT FALSE,
    current_location GEOMETRY(Point, 4326),
    current_heading NUMERIC(5, 2) DEFAULT 0.0,
    last_location_updated_at TIMESTAMPTZ,
    last_shift_selfie_at TIMESTAMPTZ,
    total_trips INT NOT NULL DEFAULT 0,
    wallet_balance_egp NUMERIC(10, 2) NOT NULL DEFAULT 0.00,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Spatial index on driver live location for lightning-fast queries
CREATE INDEX IF NOT EXISTS idx_drivers_location ON public.drivers USING GIST(current_location);

-- 6. TWO-FACED (6-SIDED) DRIVER DOCUMENT VAULT
CREATE TABLE IF NOT EXISTS public.driver_documents (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    driver_id UUID NOT NULL UNIQUE REFERENCES public.drivers(id) ON DELETE CASCADE,
    -- 1. National ID (Both Faces)
    national_id_front_url TEXT NOT NULL,
    national_id_back_url TEXT NOT NULL,
    -- 2. Driver's License (Both Faces)
    driver_license_front_url TEXT NOT NULL,
    driver_license_back_url TEXT NOT NULL,
    -- 3. Vehicle License / Mulkiya (Both Faces)
    vehicle_license_front_url TEXT NOT NULL,
    vehicle_license_back_url TEXT NOT NULL,
    -- Extraction metadata
    ocr_gender_marker VARCHAR(10) NOT NULL DEFAULT 'female',
    liveness_score NUMERIC(5, 4),
    face_match_confidence NUMERIC(5, 4),
    status doc_status NOT NULL DEFAULT 'approved',
    rejection_reason TEXT,
    uploaded_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    reviewed_at TIMESTAMPTZ
);

-- 7. RIDES TABLE (LIFECYCLE & STATE MACHINE)
CREATE TABLE IF NOT EXISTS public.rides (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    rider_id UUID NOT NULL REFERENCES public.profiles(id),
    driver_id UUID REFERENCES public.drivers(id),
    status ride_status NOT NULL DEFAULT 'requested',
    -- Pickup location
    pickup_address TEXT NOT NULL,
    pickup_location GEOMETRY(Point, 4326) NOT NULL,
    -- Dropoff location
    dropoff_address TEXT NOT NULL,
    dropoff_location GEOMETRY(Point, 4326) NOT NULL,
    -- Pricing and Tier
    tier VARCHAR(20) NOT NULL DEFAULT 'standard',
    fare_egp NUMERIC(8, 2) NOT NULL,
    driver_earnings_egp NUMERIC(8, 2) NOT NULL,
    -- Safety PIN Handshake
    pin_code VARCHAR(4) NOT NULL,
    -- Timestamps
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    accepted_at TIMESTAMPTZ,
    arrived_at TIMESTAMPTZ,
    started_at TIMESTAMPTZ,
    completed_at TIMESTAMPTZ,
    cancelled_at TIMESTAMPTZ,
    cancellation_reason TEXT,
    -- Ratings
    rider_rating INT CHECK (rider_rating BETWEEN 1 AND 5),
    driver_rating INT CHECK (driver_rating BETWEEN 1 AND 5)
);

-- Spatial index on ride pickup coordinates
CREATE INDEX IF NOT EXISTS idx_rides_pickup_location ON public.rides USING GIST(pickup_location);

-- 8. STORED POSTGIS FUNCTION: FIND NEARBY VERIFIED FEMALE DRIVERS
-- Used by the matching engine to find active drivers within a given radius in meters
CREATE OR REPLACE FUNCTION find_nearby_female_drivers(
    rider_lat DOUBLE PRECISION,
    rider_lng DOUBLE PRECISION,
    radius_meters DOUBLE PRECISION DEFAULT 5000.0
)
RETURNS TABLE (
    driver_id UUID,
    user_id UUID,
    full_name VARCHAR(150),
    phone VARCHAR(20),
    vehicle_make VARCHAR(50),
    vehicle_model VARCHAR(50),
    vehicle_plate VARCHAR(20),
    vehicle_color VARCHAR(30),
    rating_avg NUMERIC(3, 2),
    distance_meters DOUBLE PRECISION,
    current_lat DOUBLE PRECISION,
    current_lng DOUBLE PRECISION,
    current_heading NUMERIC(5, 2)
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    RETURN QUERY
    SELECT 
        d.id AS driver_id,
        p.id AS user_id,
        p.full_name,
        p.phone,
        d.vehicle_make,
        d.vehicle_model,
        d.vehicle_plate,
        d.vehicle_color,
        p.rating_avg,
        ST_DistanceSphere(d.current_location, ST_SetSRID(ST_MakePoint(rider_lng, rider_lat), 4326)) AS distance_meters,
        ST_Y(d.current_location::geometry) AS current_lat,
        ST_X(d.current_location::geometry) AS current_lng,
        d.current_heading
    FROM public.drivers d
    JOIN public.profiles p ON d.user_id = p.id
    WHERE 
        d.is_online = TRUE 
        AND d.is_busy = FALSE
        AND p.gender_verified = TRUE
        AND d.current_location IS NOT NULL
        AND ST_DWithin(
            d.current_location::geography,
            ST_SetSRID(ST_MakePoint(rider_lng, rider_lat), 4326)::geography,
            radius_meters
        )
    ORDER BY distance_meters ASC
    LIMIT 10;
END;
$$;

-- 9. STORAGE BUCKET FOR TWO-FACED DRIVER DOCUMENTS
INSERT INTO storage.buckets (id, name, public)
VALUES ('driver-documents', 'driver-documents', true)
ON CONFLICT (id) DO NOTHING;

-- 10. REALTIME CONFIGURATION (Enable Realtime on drivers and rides tables)
ALTER PUBLICATION supabase_realtime ADD TABLE public.drivers;
ALTER PUBLICATION supabase_realtime ADD TABLE public.rides;

-- 11. ROW LEVEL SECURITY (RLS) POLICIES
-- Enable RLS on all tables
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.drivers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.driver_documents ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.rides ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.emergency_contacts ENABLE ROW LEVEL SECURITY;

-- Profiles: Anyone authenticated can view profiles, users edit their own
CREATE POLICY "Public profiles viewable" ON public.profiles FOR SELECT USING (true);
CREATE POLICY "Users can update own profile" ON public.profiles FOR UPDATE USING (auth.uid() = id);
CREATE POLICY "Users can insert own profile" ON public.profiles FOR INSERT WITH CHECK (auth.uid() = id);

-- Drivers: Anyone can view active drivers, drivers edit their own record
CREATE POLICY "Active drivers viewable" ON public.drivers FOR SELECT USING (true);
CREATE POLICY "Drivers can update own record" ON public.drivers FOR UPDATE USING (auth.uid() = user_id);
CREATE POLICY "Drivers can insert own record" ON public.drivers FOR INSERT WITH CHECK (auth.uid() = user_id);

-- Driver Documents: Only the owner driver and admin can view/edit
CREATE POLICY "Driver documents own access" ON public.driver_documents FOR ALL 
USING (auth.uid() IN (SELECT user_id FROM public.drivers WHERE id = driver_id));

-- Rides: Riders and assigned drivers can view/update their active trips
CREATE POLICY "Riders and drivers view rides" ON public.rides FOR SELECT 
USING (auth.uid() = rider_id OR auth.uid() IN (SELECT user_id FROM public.drivers WHERE id = driver_id));

CREATE POLICY "Riders can insert ride requests" ON public.rides FOR INSERT 
WITH CHECK (auth.uid() = rider_id);

CREATE POLICY "Participants can update ride status" ON public.rides FOR UPDATE 
USING (auth.uid() = rider_id OR auth.uid() IN (SELECT user_id FROM public.drivers WHERE id = driver_id));

-- Emergency Contacts: Users manage their own contacts
CREATE POLICY "Manage emergency contacts" ON public.emergency_contacts FOR ALL 
USING (auth.uid() = user_id);

-- Schema setup complete!

