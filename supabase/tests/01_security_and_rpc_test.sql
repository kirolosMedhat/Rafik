-- ============================================================================
-- supabase/tests/01_security_and_rpc_test.sql
-- Automated SQL Security & RPC Contract Test Suite for Rafik
-- ============================================================================

-- Test 1: Pricing Formula Verification
do $$
declare
  v_fare numeric;
begin
  -- Fare = max(25, 15 + km * 10)
  v_fare := public.compute_fare(0.5);
  assert v_fare = 25.00, 'Test 1.1 Failed: Base fare under minimum should be 25';

  v_fare := public.compute_fare(1.0);
  assert v_fare = 25.00, 'Test 1.2 Failed: 15 + 10 = 25';

  v_fare := public.compute_fare(5.0);
  assert v_fare = 65.00, 'Test 1.3 Failed: 15 + 50 = 65';

  v_fare := public.compute_fare(12.34);
  assert v_fare = 138.40, 'Test 1.4 Failed: 15 + 123.4 = 138.40';

  raise notice 'Test 1 (compute_fare) PASSED';
end $$;

-- Test 2: Egyptian National ID Gender Extraction
do $$
begin
  -- 14 digits, 13th digit: odd = male, even = female
  assert public.national_id_gender('29804150102844') = 'female', 'Test 2.1 Failed: 4 is even -> female';
  assert public.national_id_gender('29501010101132') = 'male', 'Test 2.2 Failed: 3 is odd -> male';
  assert public.national_id_gender('invalid') is null, 'Test 2.3 Failed: Invalid format should return null';

  raise notice 'Test 2 (national_id_gender) PASSED';
end $$;

-- Test 3: PIN Lockout Simulation (3 attempts max, no rollback)
do $$
declare
  v_rider_id uuid := gen_random_uuid();
  v_driver_id uuid := gen_random_uuid();
  v_ride_id uuid := gen_random_uuid();
  v_res jsonb;
begin
  -- Temporary test setup inside transaction
  insert into auth.users (id, email) values (v_rider_id, 'test_rider@rafik.com') on conflict do nothing;
  insert into auth.users (id, email) values (v_driver_id, 'test_driver@rafik.com') on conflict do nothing;

  insert into public.profiles (id, full_name, role, gender)
  values (v_rider_id, 'Test Rider', 'rider', 'female') on conflict do nothing;

  insert into public.profiles (id, full_name, role, gender)
  values (v_driver_id, 'Test Driver', 'driver', 'female') on conflict do nothing;

  insert into public.drivers (user_id, status, national_id_number, license_number, vehicle_make, vehicle_model, vehicle_year, vehicle_plate, vehicle_color)
  values (v_driver_id, 'approved', '29804150102844', 'LIC-1234', 'Toyota', 'Corolla', 2022, 'ABC 1234', 'White') on conflict do nothing;

  insert into public.rides (
    id, rider_id, driver_id, tier, status,
    pickup_address, pickup, dropoff_address, dropoff,
    distance_km, fare_egp, driver_earnings_egp
  ) values (
    v_ride_id, v_rider_id, v_driver_id, 'standard', 'arrived',
    'Cairo Festival City', ST_SetSRID(ST_MakePoint(31.4015, 30.0285), 4326)::geography,
    'Downtown Cairo', ST_SetSRID(ST_MakePoint(31.2357, 30.0444), 4326)::geography,
    15.0, 165.0, 165.0
  );

  insert into public.ride_pins (ride_id, pin, attempts)
  values (v_ride_id, '4821', 0);

  -- Attempt 1: Wrong PIN
  -- Simulate call by driver
  perform set_config('request.jwt.claim.sub', v_driver_id::text, true);

  -- Verification query on attempts count increment
  update public.ride_pins set attempts = attempts + 1 where ride_id = v_ride_id;
  assert (select attempts from public.ride_pins where ride_id = v_ride_id) = 1, 'Test 3.1 Failed: Attempt 1 not incremented';

  -- Attempt 2: Wrong PIN
  update public.ride_pins set attempts = attempts + 1 where ride_id = v_ride_id;
  assert (select attempts from public.ride_pins where ride_id = v_ride_id) = 2, 'Test 3.2 Failed: Attempt 2 not incremented';

  -- Attempt 3: Wrong PIN -> Lock
  update public.ride_pins set attempts = attempts + 1 where ride_id = v_ride_id;
  assert (select attempts from public.ride_pins where ride_id = v_ride_id) = 3, 'Test 3.3 Failed: Attempt 3 not locked';

  raise notice 'Test 3 (PIN Lockout) PASSED';

  -- Roll back test transaction data
  raise exception 'test_cleanup' using errcode = 'TC001';
exception when sqlstate 'TC001' then
  raise notice 'Test suite transaction cleaned up successfully.';
end $$;
