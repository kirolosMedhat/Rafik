-- ============================================================================
-- 0002_rpcs.sql: Rafik Database RPC Contracts & Stored Procedures
-- Phase 2: All State Mutations via SECURITY DEFINER Stored Procedures
-- ============================================================================

-- 1. compute_fare: Deterministic pricing formula
-- Fare = max(25, 15 + km * 10) EGP
create or replace function public.compute_fare(km numeric)
returns numeric language sql immutable security definer
set search_path = public as $$
  select greatest(25.00, round((15.00 + km * 10.00)::numeric, 2));
$$;

-- 2. request_ride: Rider creates ride, server computes distance/fare/PIN, dispatches to up to 10 nearby eligible drivers
create or replace function public.request_ride(
  tier public.ride_tier,
  pickup_address text,
  pickup_lat double precision,
  pickup_lng double precision,
  dropoff_address text,
  dropoff_lat double precision,
  dropoff_lng double precision,
  payment text default 'cash'
)
returns uuid language plpgsql security definer
set search_path = public as $$
declare
  v_caller_id uuid := auth.uid();
  v_caller_role public.user_role;
  v_caller_gender text;
  v_caller_verified boolean;
  v_pickup geography;
  v_dropoff geography;
  v_dist_km numeric(6,2);
  v_fare numeric(8,2);
  v_earnings numeric(8,2);
  v_ride_id uuid;
  v_pin text;
  v_random_bytes bytea;
  v_random_int int;
begin
  if v_caller_id is null then
    raise exception 'unauthorized';
  end if;

  -- 1. Validate caller role and profile
  select role, gender, gender_verified
  into v_caller_role, v_caller_gender, v_caller_verified
  from public.profiles
  where id = v_caller_id;

  if v_caller_role is null or v_caller_role <> 'rider' then
    raise exception 'only_riders_can_request_rides';
  end if;

  -- Check no active ride exists
  if exists (
    select 1 from public.rides
    where rider_id = v_caller_id
      and status in ('requested', 'accepted', 'arrived', 'in_progress')
  ) then
    raise exception 'active_ride_exists';
  end if;

  -- 2. Validate Rafik Girl eligibility
  if tier = 'rafik_girl' then
    if v_caller_gender <> 'female' or not v_caller_verified then
      raise exception 'rafik_girl_unauthorized';
    end if;
  end if;

  -- 3. Calculate distance and fare
  v_pickup := ST_SetSRID(ST_MakePoint(pickup_lng, pickup_lat), 4326)::geography;
  v_dropoff := ST_SetSRID(ST_MakePoint(dropoff_lng, dropoff_lat), 4326)::geography;

  -- Road routing approximation factor: straight-line distance * 1.25
  v_dist_km := round(((ST_Distance(v_pickup, v_dropoff) / 1000.0) * 1.25)::numeric, 2);

  if v_dist_km < 0.20 then
    raise exception 'trip_distance_too_short';
  end if;

  v_fare := public.compute_fare(v_dist_km);
  v_earnings := v_fare; -- 0% commission: driver earns 100% of the fare

  -- 4. Create the ride row
  insert into public.rides (
    rider_id,
    tier,
    status,
    pickup_address,
    pickup,
    dropoff_address,
    dropoff,
    distance_km,
    fare_egp,
    driver_earnings_egp,
    payment_method,
    requested_at,
    expires_at
  ) values (
    v_caller_id,
    tier,
    'requested',
    pickup_address,
    v_pickup,
    dropoff_address,
    v_dropoff,
    v_dist_km,
    v_fare,
    v_earnings,
    coalesce(payment, 'cash'),
    now(),
    now() + interval '2 minutes'
  )
  returning id into v_ride_id;

  -- 5. Generate random 4-digit PIN stored in isolated ride_pins table
  v_random_bytes := gen_random_bytes(3);
  v_random_int := (get_byte(v_random_bytes, 0) * 65536 + get_byte(v_random_bytes, 1) * 256 + get_byte(v_random_bytes, 2)) % 10000;
  v_pin := lpad(v_random_int::text, 4, '0');

  insert into public.ride_pins (ride_id, pin, attempts)
  values (v_ride_id, v_pin, 0);

  -- 6. Ranked dispatch to up to 10 nearby eligible captains within 5 km
  insert into public.ride_offers (ride_id, driver_id, status, offered_at, expires_at)
  select
    v_ride_id,
    d.user_id,
    'pending',
    now(),
    now() + interval '30 seconds'
  from public.drivers d
  join public.driver_locations dl on dl.driver_id = d.user_id
  join public.profiles p on p.id = d.user_id
  where d.status = 'approved'
    and d.is_online = true
    and d.is_busy = false
    and dl.updated_at >= now() - interval '60 seconds'
    and ST_DWithin(dl.location, v_pickup, 5000)
    and (
      tier <> 'rafik_girl'
      or (p.gender = 'female' and p.gender_verified = true)
    )
  order by ST_Distance(dl.location, v_pickup) asc
  limit 10;

  return v_ride_id;
end;
$$;

-- 3. accept_ride: Atomic acceptance with concurrency locking
create or replace function public.accept_ride(p_ride_id uuid)
returns boolean language plpgsql security definer
set search_path = public as $$
declare
  v_caller_id uuid := auth.uid();
  v_rows_updated int;
begin
  if v_caller_id is null then
    raise exception 'unauthorized';
  end if;

  -- Ensure caller has a pending, unexpired offer for this ride
  if not exists (
    select 1 from public.ride_offers
    where ride_id = p_ride_id
      and driver_id = v_caller_id
      and status = 'pending'
      and expires_at > now()
  ) then
    raise exception 'ride_unavailable';
  end if;

  -- Atomic update on ride row with lock
  update public.rides
  set
    status = 'accepted',
    driver_id = v_caller_id,
    accepted_at = now()
  where id = p_ride_id
    and status = 'requested'
    and expires_at > now();

  get diagnostics v_rows_updated = row_count;

  if v_rows_updated = 0 then
    raise exception 'ride_unavailable';
  end if;

  -- Mark driver as busy
  update public.drivers
  set is_busy = true
  where user_id = v_caller_id;

  -- Mark this driver's offer as accepted
  update public.ride_offers
  set status = 'accepted'
  where ride_id = p_ride_id
    and driver_id = v_caller_id;

  -- Expire all other offers for this ride
  update public.ride_offers
  set status = 'expired'
  where ride_id = p_ride_id
    and driver_id <> v_caller_id
    and status = 'pending';

  return true;
end;
$$;

-- 4. decline_offer: Driver declines an offered trip
create or replace function public.decline_offer(p_ride_id uuid)
returns boolean language plpgsql security definer
set search_path = public as $$
declare
  v_caller_id uuid := auth.uid();
begin
  if v_caller_id is null then
    raise exception 'unauthorized';
  end if;

  update public.ride_offers
  set status = 'declined'
  where ride_id = p_ride_id
    and driver_id = v_caller_id
    and status = 'pending';

  return true;
end;
$$;

-- 5. mark_arrived: Driver arrives at pickup
create or replace function public.mark_arrived(p_ride_id uuid)
returns boolean language plpgsql security definer
set search_path = public as $$
declare
  v_caller_id uuid := auth.uid();
  v_rows int;
begin
  if v_caller_id is null then
    raise exception 'unauthorized';
  end if;

  update public.rides
  set
    status = 'arrived',
    arrived_at = now()
  where id = p_ride_id
    and driver_id = v_caller_id
    and status = 'accepted';

  get diagnostics v_rows = row_count;
  if v_rows = 0 then
    raise exception 'cannot_mark_arrived';
  end if;

  return true;
end;
$$;

-- 6. start_ride: Verification with 3-attempt lock (NO exception on wrong PIN to prevent rollback)
create or replace function public.start_ride(
  p_ride_id uuid,
  p_pin text
)
returns jsonb language plpgsql security definer
set search_path = public as $$
declare
  v_caller_id uuid := auth.uid();
  v_actual_pin text;
  v_attempts int;
  v_attempts_left int;
begin
  if v_caller_id is null then
    return jsonb_build_object('ok', false, 'error', 'unauthorized');
  end if;

  -- Verify ride belongs to caller and is arrived
  if not exists (
    select 1 from public.rides
    where id = p_ride_id
      and driver_id = v_caller_id
      and status = 'arrived'
  ) then
    return jsonb_build_object('ok', false, 'error', 'invalid_ride_state');
  end if;

  -- Lock PIN row for update
  select pin, attempts
  into v_actual_pin, v_attempts
  from public.ride_pins
  where ride_id = p_ride_id
  for update;

  if v_actual_pin is null then
    return jsonb_build_object('ok', false, 'error', 'pin_not_found');
  end if;

  -- Check if already locked
  if v_attempts >= 3 then
    return jsonb_build_object('ok', false, 'error', 'pin_locked', 'attempts_left', 0);
  end if;

  -- Evaluate PIN
  if v_actual_pin = p_pin then
    -- PIN Correct: Start trip
    update public.rides
    set
      status = 'in_progress',
      started_at = now()
    where id = p_ride_id;

    return jsonb_build_object('ok', true, 'status', 'in_progress');
  else
    -- PIN Incorrect: Increment attempts and persist without transaction rollback
    v_attempts := v_attempts + 1;
    update public.ride_pins
    set attempts = v_attempts
    where ride_id = p_ride_id;

    v_attempts_left := greatest(0, 3 - v_attempts);

    if v_attempts_left = 0 then
      return jsonb_build_object('ok', false, 'error', 'pin_locked', 'attempts_left', 0);
    else
      return jsonb_build_object('ok', false, 'error', 'wrong_pin', 'attempts_left', v_attempts_left);
    end if;
  end if;
end;
$$;

-- 7. complete_ride: Driver completes trip, records wallet transaction
create or replace function public.complete_ride(p_ride_id uuid)
returns boolean language plpgsql security definer
set search_path = public as $$
declare
  v_caller_id uuid := auth.uid();
  v_fare numeric(8,2);
  v_method text;
  v_rows int;
begin
  if v_caller_id is null then
    raise exception 'unauthorized';
  end if;

  select fare_egp, payment_method
  into v_fare, v_method
  from public.rides
  where id = p_ride_id
    and driver_id = v_caller_id
    and status = 'in_progress';

  if v_fare is null then
    raise exception 'cannot_complete_ride';
  end if;

  -- 1. Update ride status
  update public.rides
  set
    status = 'completed',
    completed_at = now()
  where id = p_ride_id;

  -- 2. Free the driver & update metrics
  update public.drivers
  set
    is_busy = false,
    total_trips = total_trips + 1,
    wallet_balance_egp = wallet_balance_egp + v_fare
  where user_id = v_caller_id;

  -- 3. Record wallet transaction
  insert into public.wallet_transactions (driver_id, ride_id, kind, amount_egp)
  values (v_caller_id, p_ride_id, 'trip_earnings', v_fare);

  if v_method = 'cash' then
    -- Cash trip collected in hand: offset from digital balance
    update public.drivers
    set wallet_balance_egp = wallet_balance_egp - v_fare
    where user_id = v_caller_id;

    insert into public.wallet_transactions (driver_id, ride_id, kind, amount_egp)
    values (v_caller_id, p_ride_id, 'cash_collected', -v_fare);
  end if;

  return true;
end;
$$;

-- 8. cancel_ride: Rider or driver cancels ride in allowed states
create or replace function public.cancel_ride(
  p_ride_id uuid,
  p_reason text default null
)
returns boolean language plpgsql security definer
set search_path = public as $$
declare
  v_caller_id uuid := auth.uid();
  v_rider_id uuid;
  v_driver_id uuid;
  v_status public.ride_status;
begin
  if v_caller_id is null then
    raise exception 'unauthorized';
  end if;

  select rider_id, driver_id, status
  into v_rider_id, v_driver_id, v_status
  from public.rides
  where id = p_ride_id;

  if v_status is null then
    raise exception 'ride_not_found';
  end if;

  if v_status not in ('requested', 'accepted', 'arrived') then
    raise exception 'cannot_cancel_in_current_state';
  end if;

  if v_caller_id <> v_rider_id and v_caller_id <> coalesce(v_driver_id, '00000000-0000-0000-0000-000000000000'::uuid) then
    raise exception 'unauthorized';
  end if;

  -- Update ride
  update public.rides
  set
    status = 'cancelled',
    cancelled_at = now(),
    cancelled_by = v_caller_id,
    cancellation_reason = p_reason
  where id = p_ride_id;

  -- Free driver if assigned
  if v_driver_id is not null then
    update public.drivers
    set is_busy = false
    where user_id = v_driver_id;
  end if;

  -- Expire pending offers
  update public.ride_offers
  set status = 'expired'
  where ride_id = p_ride_id
    and status = 'pending';

  return true;
end;
$$;

-- 9. rate_ride: Running average rating calculation
create or replace function public.rate_ride(
  p_ride_id uuid,
  p_stars int,
  p_review text default null
)
returns boolean language plpgsql security definer
set search_path = public as $$
declare
  v_caller_id uuid := auth.uid();
  v_rider_id uuid;
  v_driver_id uuid;
  v_status public.ride_status;
  v_target_user uuid;
  v_new_avg numeric(3,2);
begin
  if v_caller_id is null then
    raise exception 'unauthorized';
  end if;

  if p_stars < 1 or p_stars > 5 then
    raise exception 'invalid_rating_value';
  end if;

  select rider_id, driver_id, status
  into v_rider_id, v_driver_id, v_status
  from public.rides
  where id = p_ride_id;

  if v_status <> 'completed' then
    raise exception 'ride_not_completed';
  end if;

  if v_caller_id = v_rider_id then
    -- Rider rates driver
    update public.rides
    set
      driver_rating = p_stars,
      review = coalesce(p_review, review)
    where id = p_ride_id and driver_rating is null;

    v_target_user := v_driver_id;
    select round(avg(driver_rating)::numeric, 2)
    into v_new_avg
    from public.rides
    where driver_id = v_target_user and driver_rating is not null;

  elsif v_caller_id = v_driver_id then
    -- Driver rates rider
    update public.rides
    set rider_rating = p_stars
    where id = p_ride_id and rider_rating is null;

    v_target_user := v_rider_id;
    select round(avg(rider_rating)::numeric, 2)
    into v_new_avg
    from public.rides
    where rider_id = v_target_user and rider_rating is not null;
  else
    raise exception 'unauthorized';
  end if;

  if v_new_avg is not null then
    update public.profiles
    set rating_avg = v_new_avg
    where id = v_target_user;
  end if;

  return true;
end;
$$;

-- 10. submit_driver_application: Register captain details with National ID gender check
create or replace function public.submit_driver_application(
  national_id text,
  license_number text,
  make text,
  model text,
  year int,
  plate text,
  color text
)
returns boolean language plpgsql security definer
set search_path = public as $$
declare
  v_caller_id uuid := auth.uid();
  v_caller_gender text;
  v_nid_gender text;
begin
  if v_caller_id is null then
    raise exception 'unauthorized';
  end if;

  select gender into v_caller_gender
  from public.profiles
  where id = v_caller_id;

  v_nid_gender := public.national_id_gender(national_id);

  if v_nid_gender is null or v_nid_gender <> v_caller_gender then
    raise exception 'gender_mismatch_with_national_id';
  end if;

  if year < 2000 or year > 2100 then
    raise exception 'invalid_vehicle_year';
  end if;

  insert into public.drivers (
    user_id,
    status,
    national_id_number,
    license_number,
    vehicle_make,
    vehicle_model,
    vehicle_year,
    vehicle_plate,
    vehicle_color,
    is_online,
    is_busy
  ) values (
    v_caller_id,
    'pending',
    national_id,
    license_number,
    make,
    model,
    year,
    plate,
    color,
    false,
    false
  )
  on conflict (user_id) do update set
    status = 'pending',
    rejection_reason = null,
    national_id_number = excluded.national_id_number,
    license_number = excluded.license_number,
    vehicle_make = excluded.vehicle_make,
    vehicle_model = excluded.vehicle_model,
    vehicle_year = excluded.vehicle_year,
    vehicle_plate = excluded.vehicle_plate,
    vehicle_color = excluded.vehicle_color;

  return true;
end;
$$;

-- 11. set_driver_online: Toggle availability (only approved captains)
create or replace function public.set_driver_online(p_online boolean)
returns boolean language plpgsql security definer
set search_path = public as $$
declare
  v_caller_id uuid := auth.uid();
  v_status public.review_status;
  v_is_busy boolean;
begin
  if v_caller_id is null then
    raise exception 'unauthorized';
  end if;

  select status, is_busy
  into v_status, v_is_busy
  from public.drivers
  where user_id = v_caller_id;

  if v_status is null or v_status <> 'approved' then
    raise exception 'driver_not_approved';
  end if;

  if not p_online and v_is_busy then
    raise exception 'cannot_go_offline_while_busy';
  end if;

  update public.drivers
  set is_online = p_online
  where user_id = v_caller_id;

  return true;
end;
$$;

-- 12. update_driver_location: Live GPS ingestion
create or replace function public.update_driver_location(
  lat double precision,
  lng double precision,
  heading numeric default 0
)
returns boolean language plpgsql security definer
set search_path = public as $$
declare
  v_caller_id uuid := auth.uid();
  v_is_online boolean;
begin
  if v_caller_id is null then
    raise exception 'unauthorized';
  end if;

  select is_online into v_is_online
  from public.drivers
  where user_id = v_caller_id;

  if not coalesce(v_is_online, false) then
    raise exception 'driver_offline';
  end if;

  insert into public.driver_locations (
    driver_id,
    location,
    heading,
    updated_at
  ) values (
    v_caller_id,
    ST_SetSRID(ST_MakePoint(lng, lat), 4326)::geography,
    heading,
    now()
  )
  on conflict (driver_id) do update set
    location = excluded.location,
    heading = excluded.heading,
    updated_at = excluded.updated_at;

  return true;
end;
$$;

-- 13. trigger_sos: Instant emergency alert
create or replace function public.trigger_sos(
  p_ride_id uuid,
  lat double precision,
  lng double precision
)
returns uuid language plpgsql security definer
set search_path = public as $$
declare
  v_caller_id uuid := auth.uid();
  v_sos_id uuid;
begin
  if v_caller_id is null then
    raise exception 'unauthorized';
  end if;

  insert into public.sos_events (
    user_id,
    ride_id,
    location,
    status,
    created_at
  ) values (
    v_caller_id,
    p_ride_id,
    ST_SetSRID(ST_MakePoint(lng, lat), 4326)::geography,
    'active',
    now()
  )
  returning id into v_sos_id;

  return v_sos_id;
end;
$$;

-- 14. admin_review_driver: Admin KYC review for drivers
create or replace function public.admin_review_driver(
  p_driver_id uuid,
  p_approve boolean,
  p_reason text default null,
  p_confirm_female boolean default false
)
returns boolean language plpgsql security definer
set search_path = public as $$
begin
  if not public.is_admin() then
    raise exception 'unauthorized';
  end if;

  if p_approve then
    update public.drivers
    set
      status = 'approved',
      rejection_reason = null
    where user_id = p_driver_id;

    update public.driver_documents
    set
      status = 'approved',
      rejection_reason = null
    where driver_id = p_driver_id;

    if p_confirm_female then
      update public.profiles
      set gender_verified = true
      where id = p_driver_id and gender = 'female';
    end if;
  else
    if p_reason is null or trim(p_reason) = '' then
      raise exception 'rejection_reason_required';
    end if;

    update public.drivers
    set
      status = 'rejected',
      rejection_reason = p_reason
    where user_id = p_driver_id;

    update public.driver_documents
    set
      status = 'rejected',
      rejection_reason = p_reason
    where driver_id = p_driver_id;
  end if;

  return true;
end;
$$;

-- 15. admin_review_identity: Admin KYC review for Rafik Girl riders
create or replace function public.admin_review_identity(
  p_user_id uuid,
  p_approve boolean,
  p_reason text default null
)
returns boolean language plpgsql security definer
set search_path = public as $$
begin
  if not public.is_admin() then
    raise exception 'unauthorized';
  end if;

  if p_approve then
    update public.identity_verifications
    set
      status = 'approved',
      reviewed_by = auth.uid(),
      reviewed_at = now(),
      rejection_reason = null
    where user_id = p_user_id;

    update public.profiles
    set gender_verified = true
    where id = p_user_id;
  else
    if p_reason is null or trim(p_reason) = '' then
      raise exception 'rejection_reason_required';
    end if;

    update public.identity_verifications
    set
      status = 'rejected',
      reviewed_by = auth.uid(),
      reviewed_at = now(),
      rejection_reason = p_reason
    where user_id = p_user_id;
  end if;

  return true;
end;
$$;

-- 16. expire_stale_rides: Scheduled cleaner for requested rides and pending offers
create or replace function public.expire_stale_rides()
returns int language plpgsql security definer
set search_path = public as $$
declare
  v_count int;
begin
  update public.rides
  set status = 'expired'
  where status = 'requested'
    and expires_at <= now();

  get diagnostics v_count = row_count;

  update public.ride_offers
  set status = 'expired'
  where status = 'pending'
    and expires_at <= now();

  return v_count;
end;
$$;

-- 17. Admin Analytics View
create or replace view public.admin_metrics_view as
select
  (select count(*) from public.drivers where is_online = true and status = 'approved') as active_captains,
  (select count(*) from public.drivers where status = 'pending') as pending_applications,
  (select count(*) from public.identity_verifications where status = 'pending') as pending_identities,
  (select count(*) from public.rides where status = 'completed') as total_completed_trips,
  (select coalesce(sum(fare_egp), 0) from public.rides where status = 'completed') as gross_fares_egp,
  (select count(*) from public.sos_events where status = 'active') as active_sos_count;
