import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'persistent_storage.dart';

/// Centralized, Production-Grade Supabase Service for Rafik
/// Strictly communicates through Row-Level Security and `SECURITY DEFINER` RPCs.
class SupabaseService {
  static final SupabaseService _instance = SupabaseService._internal();
  factory SupabaseService() => _instance;
  SupabaseService._internal();

  SupabaseClient get client => Supabase.instance.client;
  User? get currentUser => client.auth.currentUser;

  // ================= 1. PROFILE & ROLE =================
  Future<Map<String, dynamic>?> fetchProfile() async {
    final user = currentUser;
    if (user == null) return null;

    final response = await client
        .from('profiles')
        .select('*')
        .eq('id', user.id)
        .maybeSingle();

    return response;
  }

  Future<void> updateProfileLanguage(String lang) async {
    final user = currentUser;
    if (user == null) return;
    await client.from('profiles').update({'language': lang}).eq('id', user.id);
    await PersistentStorage.setLanguage(lang);
  }

  // ================= 2. FARE CALCULATION =================
  /// Client-side preview matching PostgreSQL `compute_fare` (server is authoritative)
  static double computeFarePreview(double km) {
    final calculated = 15.0 + (km * 10.0);
    return calculated < 25.0 ? 25.0 : double.parse(calculated.toStringAsFixed(2));
  }

  // ================= 3. RIDER BOOKING & RPCS =================
  Future<String> requestRide({
    required String tier, // 'standard' or 'rafik_girl'
    required String pickupAddress,
    required double pickupLat,
    required double pickupLng,
    required String dropoffAddress,
    required double dropoffLat,
    required double dropoffLng,
    String paymentMethod = 'cash',
  }) async {
    final result = await client.rpc('request_ride', params: {
      'tier': tier,
      'pickup_address': pickupAddress,
      'pickup_lat': pickupLat,
      'pickup_lng': pickupLng,
      'dropoff_address': dropoffAddress,
      'dropoff_lat': dropoffLat,
      'dropoff_lng': dropoffLng,
      'payment': paymentMethod,
    });

    return result.toString();
  }

  /// Rider-only query to fetch the generated 4-digit security PIN
  Future<String?> fetchRidePin(String rideId) async {
    try {
      final res = await client
          .from('ride_pins')
          .select('pin')
          .eq('ride_id', rideId)
          .maybeSingle();
      return res?['pin']?.toString();
    } catch (e) {
      debugPrint('[SupabaseService] fetchRidePin notice: $e');
      return null;
    }
  }

  Future<bool> cancelRide({
    required String rideId,
    String? reason,
  }) async {
    final result = await client.rpc('cancel_ride', params: {
      'p_ride_id': rideId,
      'p_reason': reason ?? 'Cancelled by user',
    });
    return result == true;
  }

  Future<bool> rateRide({
    required String rideId,
    required int stars,
    String? review,
  }) async {
    final result = await client.rpc('rate_ride', params: {
      'p_ride_id': rideId,
      'p_stars': stars,
      'p_review': review,
    });
    return result == true;
  }

  Future<bool> submitDriverRating({
    required String rideId,
    required double rating,
    List<String>? badges,
    String? comment,
  }) async {
    return rateRide(
      rideId: rideId,
      stars: rating.round().clamp(1, 5),
      review: comment,
    );
  }

  // ================= 4. CAPTAIN / DRIVER RPCS =================
  Future<bool> acceptRide(String rideId) async {
    final result = await client.rpc('accept_ride', params: {
      'p_ride_id': rideId,
    });
    return result == true;
  }

  Future<bool> declineOffer(String rideId) async {
    final result = await client.rpc('decline_offer', params: {
      'p_ride_id': rideId,
    });
    return result == true;
  }

  Future<bool> markArrived(String rideId) async {
    final result = await client.rpc('mark_arrived', params: {
      'p_ride_id': rideId,
    });
    return result == true;
  }

  Future<Map<String, dynamic>> startRide({
    required String rideId,
    required String pin,
  }) async {
    final result = await client.rpc('start_ride', params: {
      'p_ride_id': rideId,
      'p_pin': pin,
    });

    return Map<String, dynamic>.from(result as Map);
  }

  Future<bool> completeRide(String rideId) async {
    final result = await client.rpc('complete_ride', params: {
      'p_ride_id': rideId,
    });
    return result == true;
  }

  Future<bool> setDriverOnline(bool isOnline) async {
    final result = await client.rpc('set_driver_online', params: {
      'p_online': isOnline,
    });
    return result == true;
  }

  Future<void> updateDriverLocation({
    required double lat,
    required double lng,
    double heading = 0.0,
  }) async {
    try {
      await client.rpc('update_driver_location', params: {
        'lat': lat,
        'lng': lng,
        'heading': heading,
      });
    } catch (e) {
      // Driver might be offline; silent ignore
    }
  }

  Future<bool> submitDriverApplication({
    required String nationalId,
    required String licenseNumber,
    required String make,
    required String model,
    required int year,
    required String plate,
    required String color,
  }) async {
    final result = await client.rpc('submit_driver_application', params: {
      'national_id': nationalId,
      'license_number': licenseNumber,
      'make': make,
      'model': model,
      'year': year,
      'plate': plate,
      'color': color,
    });
    return result == true;
  }

  Future<Map<String, dynamic>?> fetchDriverStatus() async {
    final user = currentUser;
    if (user == null) return null;

    final response = await client
        .from('drivers')
        .select('*')
        .eq('user_id', user.id)
        .maybeSingle();

    return response;
  }

  // ================= 5. STORAGE & KYC DOCUMENTS =================
  Future<String> uploadDriverDocument({
    required String kind,
    required File file,
  }) async {
    final user = currentUser;
    if (user == null) throw Exception('unauthorized');

    final storagePath = '${user.id}/$kind.jpg';
    await client.storage.from('driver-documents').upload(
          storagePath,
          file,
          fileOptions: const FileOptions(upsert: true, contentType: 'image/jpeg'),
        );

    // Record document in driver_documents table
    await client.from('driver_documents').upsert({
      'driver_id': user.id,
      'kind': kind,
      'storage_path': storagePath,
      'status': 'pending',
    });

    return storagePath;
  }

  Future<void> submitIdentityVerification({
    required File idFront,
    required File selfie,
  }) async {
    final user = currentUser;
    if (user == null) throw Exception('unauthorized');

    final frontPath = '${user.id}/id_front.jpg';
    final selfiePath = '${user.id}/selfie.jpg';

    await client.storage.from('identity-documents').upload(
          frontPath,
          idFront,
          fileOptions: const FileOptions(upsert: true, contentType: 'image/jpeg'),
        );

    await client.storage.from('identity-documents').upload(
          selfiePath,
          selfie,
          fileOptions: const FileOptions(upsert: true, contentType: 'image/jpeg'),
        );

    await client.from('identity_verifications').upsert({
      'user_id': user.id,
      'id_front_path': frontPath,
      'selfie_path': selfiePath,
      'status': 'pending',
    });
  }

  // ================= 6. SOS & EMERGENCY =================
  Future<String> triggerSos({
    required String rideId,
    required double lat,
    required double lng,
  }) async {
    final result = await client.rpc('trigger_sos', params: {
      'p_ride_id': rideId,
      'lat': lat,
      'lng': lng,
    });
    return result.toString();
  }

  Future<List<Map<String, dynamic>>> getEmergencyContacts() async {
    final user = currentUser;
    if (user == null) return [];

    final response = await client
        .from('emergency_contacts')
        .select('*')
        .eq('user_id', user.id)
        .order('created_at', ascending: true);

    return List<Map<String, dynamic>>.from(response);
  }

  Future<bool> addEmergencyContact({
    required String name,
    required String phone,
    String? relationship,
  }) async {
    final user = currentUser;
    if (user == null) return false;

    await client.from('emergency_contacts').insert({
      'user_id': user.id,
      'contact_name': name,
      'phone_number': phone,
      'relationship': relationship ?? 'Family',
    });

    return true;
  }

  // ================= 7. TRIP HISTORY =================
  Future<List<Map<String, dynamic>>> fetchUserTrips() async {
    final user = currentUser;
    if (user == null) {
      return PersistentStorage.getCachedTrips();
    }

    try {
      final response = await client
          .from('rides')
          .select('*')
          .or('rider_id.eq.${user.id},driver_id.eq.${user.id}')
          .eq('status', 'completed')
          .order('completed_at', ascending: false)
          .limit(20);

      if (response.isNotEmpty) {
        return List<Map<String, dynamic>>.from(response);
      }
    } catch (e) {
      debugPrint('[SupabaseService] fetchUserTrips notice: $e');
    }

    return PersistentStorage.getCachedTrips();
  }
}
