-- ============================================================================
-- 0001_core.sql: Rafik Core Schema, Security Model, RLS, Storage & Realtime
-- Phase 1: Pure Supabase Architecture Migration
-- ============================================================================

-- 1. Required Extensions
create extension if not exists postgis;
create extension if not exists pgcrypto;

-- 2. Clean Up Legacy / Old Tables (Safe for fresh schema setup)
drop table if exists public.messages cascade;
drop table if exists public.emergency_contacts cascade;
drop table if exists public.sos_events cascade;
drop table if exists public.wallet_transactions cascade;
drop table if exists public.identity_verifications cascade;
drop table if exists public.ride_offers cascade;
drop table if exists public.ride_pins cascade;
drop table if exists public.rides cascade;
drop table if exists public.driver_documents cascade;
drop table if exists public.driver_locations cascade;
drop table if exists public.drivers cascade;
drop table if exists public.profiles cascade;

drop type if exists public.user_role cascade;
drop type if exists public.ride_tier cascade;
drop type if exists public.ride_status cascade;
drop type if exists public.review_status cascade;
drop type if exists public.doc_kind cascade;

-- 3. Core Domain Enumerations
create type public.user_role as enum ('rider', 'driver', 'admin');
create type public.ride_tier as enum ('standard', 'rafik_girl');
create type public.ride_status as enum ('requested', 'accepted', 'arrived', 'in_progress', 'completed', 'cancelled', 'expired');
create type public.review_status as enum ('pending', 'approved', 'rejected');
create type public.doc_kind as enum (
  'national_id_front',
  'national_id_back',
  'license_front',
  'license_back',
  'vehicle_reg_front',
  'vehicle_reg_back'
);

-- ============================================================================
-- 4. Tables Definition
-- ============================================================================

-- 4.1 Profiles (extends auth.users)
create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  full_name text not null,
  phone text unique,
  email text,
  role public.user_role not null default 'rider',
  gender text not null check (gender in ('female', 'male')),
  gender_verified boolean not null default false,
  language text not null default 'en' check (language in ('en', 'ar')),
  rating_avg numeric(3,2) not null default 5.00,
  avatar_url text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- 4.2 Helper Security Functions
create or replace function public.is_admin()
returns boolean language sql stable security definer
set search_path = public as $$
  select exists (
    select 1 from public.profiles
    where id = auth.uid() and role = 'admin'
  );
$$;

-- Egyptian national ID: 14 digits; 13th digit odd = male, even = female
create or replace function public.national_id_gender(nid text)
returns text language sql immutable as $$
  select case
    when nid ~ '^[23][0-9]{13}$' then
      case when substr(nid, 13, 1)::int % 2 = 0 then 'female' else 'male' end
    else null
  end;
$$;

-- Trigger: create profile automatically when a new auth user registers
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer
set search_path = public as $$
begin
  insert into public.profiles (id, full_name, phone, email, role, gender)
  values (
    new.id,
    coalesce(new.raw_user_meta_data->>'full_name', 'Rafik User'),
    new.phone,
    new.email,
    case when new.raw_user_meta_data->>'role' = 'driver' then 'driver'::public.user_role else 'rider'::public.user_role end,
    case when new.raw_user_meta_data->>'gender' = 'female' then 'female' else 'male' end
  );
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- Trigger: protect privileged columns from client updates
create or replace function public.protect_profile()
returns trigger language plpgsql security definer
set search_path = public as $$
begin
  if auth.uid() is not null and not public.is_admin() then
    new.id := old.id;
    new.role := old.role;
    new.gender_verified := old.gender_verified;
    new.rating_avg := old.rating_avg;
    if old.gender_verified then
      new.gender := old.gender;
    end if;
  end if;
  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists protect_profile on public.profiles;
create trigger protect_profile
  before update on public.profiles
  for each row execute function public.protect_profile();

-- 4.3 Drivers
create table public.drivers (
  user_id uuid primary key references public.profiles(id) on delete cascade,
  status public.review_status not null default 'pending',
  rejection_reason text,
  national_id_number text not null unique check (national_id_number ~ '^[23][0-9]{13}$'),
  license_number text not null unique,
  vehicle_make text not null,
  vehicle_model text not null,
  vehicle_year int not null check (vehicle_year between 2000 and 2100),
  vehicle_plate text not null unique,
  vehicle_color text not null,
  is_online boolean not null default false,
  is_busy boolean not null default false,
  total_trips int not null default 0,
  wallet_balance_egp numeric(10,2) not null default 0,
  created_at timestamptz not null default now()
);

-- 4.4 Driver Realtime Locations
create table public.driver_locations (
  driver_id uuid primary key references public.drivers(user_id) on delete cascade,
  location geography(Point, 4326) not null,
  heading numeric(5,2) default 0,
  updated_at timestamptz not null default now()
);
create index driver_locations_gist on public.driver_locations using gist(location);

-- 4.5 Driver KYC Documents
create table public.driver_documents (
  driver_id uuid not null references public.drivers(user_id) on delete cascade,
  kind public.doc_kind not null,
  storage_path text not null,
  status public.review_status not null default 'pending',
  rejection_reason text,
  uploaded_at timestamptz not null default now(),
  primary key (driver_id, kind)
);

-- 4.6 Rides
create table public.rides (
  id uuid primary key default gen_random_uuid(),
  rider_id uuid not null references public.profiles(id),
  driver_id uuid references public.drivers(user_id),
  tier public.ride_tier not null,
  status public.ride_status not null default 'requested',
  pickup_address text not null,
  pickup geography(Point, 4326) not null,
  dropoff_address text not null,
  dropoff geography(Point, 4326) not null,
  distance_km numeric(6,2) not null,
  fare_egp numeric(8,2) not null,
  driver_earnings_egp numeric(8,2) not null,
  payment_method text not null default 'cash' check (payment_method in ('cash', 'card', 'wallet')),
  requested_at timestamptz not null default now(),
  expires_at timestamptz not null default now() + interval '2 minutes',
  accepted_at timestamptz,
  arrived_at timestamptz,
  started_at timestamptz,
  completed_at timestamptz,
  cancelled_at timestamptz,
  cancelled_by uuid,
  cancellation_reason text,
  rider_rating int check (rider_rating between 1 and 5),
  driver_rating int check (driver_rating between 1 and 5),
  review text
);

create unique index one_active_ride_per_rider on public.rides(rider_id)
  where status in ('requested', 'accepted', 'arrived', 'in_progress');

create unique index one_active_ride_per_driver on public.rides(driver_id)
  where status in ('accepted', 'arrived', 'in_progress');

create index rides_pickup_gist on public.rides using gist(pickup);

-- 4.7 Isolated Ride Security PINs (Drivers can NEVER select this table)
create table public.ride_pins (
  ride_id uuid primary key references public.rides(id) on delete cascade,
  pin text not null check (pin ~ '^[0-9]{4}$'),
  attempts int not null default 0
);

-- 4.8 Ride Offers (Ranked Dispatch)
create table public.ride_offers (
  ride_id uuid not null references public.rides(id) on delete cascade,
  driver_id uuid not null references public.drivers(user_id) on delete cascade,
  status text not null default 'pending' check (status in ('pending', 'accepted', 'declined', 'expired')),
  offered_at timestamptz not null default now(),
  expires_at timestamptz not null default now() + interval '30 seconds',
  primary key (ride_id, driver_id)
);

-- 4.9 Messages (In-Ride Chat)
create table public.messages (
  id uuid primary key default gen_random_uuid(),
  ride_id uuid not null references public.rides(id) on delete cascade,
  sender_id uuid not null references public.profiles(id),
  body text not null,
  created_at timestamptz not null default now()
);

-- 4.10 Emergency Contacts
create table public.emergency_contacts (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  contact_name text not null,
  phone_number text not null,
  relationship text
);

-- 4.11 SOS Events
create table public.sos_events (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  ride_id uuid references public.rides(id) on delete set null,
  location geography(Point, 4326) not null,
  status text not null default 'active' check (status in ('active', 'resolved')),
  note text,
  created_at timestamptz not null default now(),
  resolved_by uuid references public.profiles(id),
  resolved_at timestamptz
);

-- 4.12 Wallet Transactions (Drivers)
create table public.wallet_transactions (
  id uuid primary key default gen_random_uuid(),
  driver_id uuid not null references public.drivers(user_id) on delete cascade,
  ride_id uuid references public.rides(id) on delete set null,
  kind text not null check (kind in ('trip_earnings', 'cash_collected', 'withdrawal', 'bonus', 'adjustment')),
  amount_egp numeric(10,2) not null,
  created_at timestamptz not null default now()
);

-- 4.13 Rider Identity Verification (Rafik Girl Verification)
create table public.identity_verifications (
  user_id uuid primary key references public.profiles(id) on delete cascade,
  id_front_path text not null,
  selfie_path text not null,
  status public.review_status not null default 'pending',
  rejection_reason text,
  reviewed_by uuid references public.profiles(id),
  reviewed_at timestamptz,
  created_at timestamptz not null default now()
);

-- ============================================================================
-- 5. Row Level Security (RLS) Policies
-- ============================================================================

-- Enable RLS across all tables
alter table public.profiles enable row level security;
alter table public.drivers enable row level security;
alter table public.driver_locations enable row level security;
alter table public.driver_documents enable row level security;
alter table public.rides enable row level security;
alter table public.ride_pins enable row level security;
alter table public.ride_offers enable row level security;
alter table public.messages enable row level security;
alter table public.emergency_contacts enable row level security;
alter table public.sos_events enable row level security;
alter table public.wallet_transactions enable row level security;
alter table public.identity_verifications enable row level security;

-- Global revoke from anon and authenticated on direct state mutating tables
revoke all on all tables in schema public from anon;
revoke insert, update, delete on public.rides from anon, authenticated;
revoke insert, update, delete on public.ride_pins from anon, authenticated;
revoke insert, update, delete on public.ride_offers from anon, authenticated;
revoke insert, update, delete on public.drivers from anon, authenticated;
revoke insert, update, delete on public.driver_locations from anon, authenticated;
revoke insert, update, delete on public.wallet_transactions from anon, authenticated;
revoke insert, update, delete on public.sos_events from anon, authenticated;

-- 5.1 Profiles Policies
create policy "profiles_select_policy" on public.profiles
  for select to authenticated
  using (
    id = auth.uid()
    or public.is_admin()
    or exists (
      select 1 from public.rides r
      where (r.rider_id = auth.uid() and r.driver_id = profiles.id)
         or (r.driver_id = auth.uid() and r.rider_id = profiles.id)
      and r.status in ('accepted', 'arrived', 'in_progress')
    )
  );

create policy "profiles_update_own" on public.profiles
  for update to authenticated
  using (id = auth.uid())
  with check (id = auth.uid());

-- 5.2 Drivers Policies
create policy "drivers_select_policy" on public.drivers
  for select to authenticated
  using (
    user_id = auth.uid()
    or public.is_admin()
    or exists (
      select 1 from public.rides r
      where r.driver_id = drivers.user_id
        and r.rider_id = auth.uid()
        and r.status in ('accepted', 'arrived', 'in_progress')
    )
  );

-- 5.3 Driver Locations Policies
create policy "driver_locations_select" on public.driver_locations
  for select to authenticated
  using (
    driver_id = auth.uid()
    or public.is_admin()
    or exists (
      select 1 from public.rides r
      where r.driver_id = driver_locations.driver_id
        and r.rider_id = auth.uid()
        and r.status in ('accepted', 'arrived', 'in_progress')
    )
  );

-- 5.4 Driver Documents Policies
create policy "driver_documents_select" on public.driver_documents
  for select to authenticated
  using (driver_id = auth.uid() or public.is_admin());

create policy "driver_documents_insert_own" on public.driver_documents
  for insert to authenticated
  with check (
    driver_id = auth.uid()
    and status in ('pending', 'rejected')
  );

create policy "driver_documents_update_own" on public.driver_documents
  for update to authenticated
  using (driver_id = auth.uid() and status in ('pending', 'rejected'))
  with check (driver_id = auth.uid());

-- 5.5 Identity Verifications Policies
create policy "identity_verifications_select" on public.identity_verifications
  for select to authenticated
  using (user_id = auth.uid() or public.is_admin());

create policy "identity_verifications_insert_own" on public.identity_verifications
  for insert to authenticated
  with check (
    user_id = auth.uid()
    and status in ('pending', 'rejected')
  );

create policy "identity_verifications_update_own" on public.identity_verifications
  for update to authenticated
  using (user_id = auth.uid() and status in ('pending', 'rejected'))
  with check (user_id = auth.uid());

-- 5.6 Wallet Transactions Policies
create policy "wallet_transactions_select" on public.wallet_transactions
  for select to authenticated
  using (driver_id = auth.uid() or public.is_admin());

-- 5.7 Rides Policies
create policy "rides_select_policy" on public.rides
  for select to authenticated
  using (
    rider_id = auth.uid()
    or driver_id = auth.uid()
    or public.is_admin()
    or exists (
      select 1 from public.ride_offers ro
      where ro.ride_id = rides.id
        and ro.driver_id = auth.uid()
        and ro.status = 'pending'
        and ro.expires_at > now()
    )
  );

-- 5.8 Ride PINs Policies (STRICTLY Rider Only!)
create policy "ride_pins_select_rider_only" on public.ride_pins
  for select to authenticated
  using (
    exists (
      select 1 from public.rides r
      where r.id = ride_pins.ride_id
        and r.rider_id = auth.uid()
    )
  );

-- 5.9 Ride Offers Policies
create policy "ride_offers_select" on public.ride_offers
  for select to authenticated
  using (driver_id = auth.uid() or public.is_admin());

-- 5.10 Messages Policies
create policy "messages_select" on public.messages
  for select to authenticated
  using (
    exists (
      select 1 from public.rides r
      where r.id = messages.ride_id
        and (r.rider_id = auth.uid() or r.driver_id = auth.uid())
        and r.status in ('accepted', 'arrived', 'in_progress')
    )
  );

create policy "messages_insert" on public.messages
  for insert to authenticated
  with check (
    sender_id = auth.uid()
    and exists (
      select 1 from public.rides r
      where r.id = messages.ride_id
        and (r.rider_id = auth.uid() or r.driver_id = auth.uid())
        and r.status in ('accepted', 'arrived', 'in_progress')
    )
  );

-- 5.11 SOS Events Policies
create policy "sos_events_select" on public.sos_events
  for select to authenticated
  using (user_id = auth.uid() or public.is_admin());

create policy "sos_events_update_admin" on public.sos_events
  for update to authenticated
  using (public.is_admin())
  with check (public.is_admin());

-- 5.12 Emergency Contacts Policies
create policy "emergency_contacts_all_own" on public.emergency_contacts
  for all to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

-- ============================================================================
-- 6. Storage Buckets & Policies
-- ============================================================================

-- Ensure storage buckets exist and are marked private
insert into storage.buckets (id, name, public)
values ('driver-documents', 'driver-documents', false)
on conflict (id) do update set public = false;

insert into storage.buckets (id, name, public)
values ('identity-documents', 'identity-documents', false)
on conflict (id) do update set public = false;

-- Storage object policies (owner folder scoped)
do $$
begin
  -- Policy for owner upload
  if not exists (select 1 from pg_policies where policyname = 'storage_owner_upload') then
    create policy "storage_owner_upload" on storage.objects
      for insert to authenticated
      with check (
        bucket_id in ('driver-documents', 'identity-documents')
        and (storage.foldername(name))[1] = auth.uid()::text
      );
  end if;

  -- Policy for owner read
  if not exists (select 1 from pg_policies where policyname = 'storage_owner_read') then
    create policy "storage_owner_read" on storage.objects
      for select to authenticated
      using (
        bucket_id in ('driver-documents', 'identity-documents')
        and (
          (storage.foldername(name))[1] = auth.uid()::text
          or public.is_admin()
        )
      );
  end if;
end $$;

-- ============================================================================
-- 7. Realtime Publication
-- ============================================================================
do $$
begin
  if not exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    create publication supabase_realtime;
  end if;
end $$;

alter publication supabase_realtime add table public.rides;
alter publication supabase_realtime add table public.ride_offers;
alter publication supabase_realtime add table public.messages;
alter publication supabase_realtime add table public.sos_events;
alter publication supabase_realtime add table public.driver_locations;
