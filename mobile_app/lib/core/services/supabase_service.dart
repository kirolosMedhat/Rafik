import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'persistent_storage.dart';

/// Centralized Supabase Database & Realtime Service for Rafik
class SupabaseService {
  static final SupabaseService _instance = SupabaseService._internal();
  factory SupabaseService() => _instance;
  SupabaseService._internal();

  SupabaseClient get client => Supabase.instance.client;

  /// Inserts a new ride request record in PostgreSQL `rides` table
  Future<bool> createRideRecord({
    required String rideId,
    required String pickupAddress,
    required String dropoffAddress,
    required double pickupLat,
    required double pickupLng,
    required double dropoffLat,
    required double dropoffLng,
    required double fareAmount,
    required double distanceKm,
    required String handshakePin,
    String paymentMethod = 'cash',
  }) async {
    try {
      final user = client.auth.currentUser;
      final riderId = user?.id ?? 'demo-rider-${DateTime.now().millisecondsSinceEpoch}';

      // Insert record
      await client.from('rides').insert({
        'id': rideId,
        'rider_id': riderId,
        'pickup_address': pickupAddress,
        'dropoff_address': dropoffAddress,
        'fare_amount': fareAmount,
        'status': 'requested',
        'handshake_pin': handshakePin,
      });

      debugPrint('Supabase: Ride record $rideId inserted successfully');
      return true;
    } catch (e) {
      debugPrint('Supabase insert ride notice (continuing with realtime): $e');
      return false;
    }
  }

  /// Updates ride status when accepted by a driver
  Future<void> updateRideAccepted({
    required String rideId,
    required String driverId,
    required String driverName,
  }) async {
    try {
      await client.from('rides').update({
        'driver_id': driverId,
        'status': 'accepted',
      }).eq('id', rideId);
    } catch (e) {
      debugPrint('Supabase update accepted notice: $e');
    }
  }

  /// Updates ride status when PIN is verified (trip started)
  Future<void> updateTripStarted(String rideId) async {
    try {
      await client.from('rides').update({
        'status': 'in_progress',
        'started_at': DateTime.now().toIso8601String(),
      }).eq('id', rideId);
    } catch (e) {
      debugPrint('Supabase update started notice: $e');
    }
  }

  /// Updates ride status when trip is completed
  Future<void> updateTripCompleted({
    required String rideId,
    required double finalFare,
    required Map<String, dynamic> tripData,
  }) async {
    try {
      await client.from('rides').update({
        'status': 'completed',
        'completed_at': DateTime.now().toIso8601String(),
        'fare_amount': finalFare,
      }).eq('id', rideId);
    } catch (e) {
      debugPrint('Supabase update completed notice: $e');
    }

    // Always cache locally for instant access in "My Trips" screen
    await PersistentStorage.cacheCompletedTrip(tripData);
    await PersistentStorage.updateDriverEarnings(finalFare);
  }

  /// Fetches past completed trips for the current user
  Future<List<Map<String, dynamic>>> fetchUserTrips() async {
    try {
      final user = client.auth.currentUser;
      if (user != null) {
        final response = await client
            .from('rides')
            .select('*')
            .eq('rider_id', user.id)
            .order('created_at', ascending: false)
            .limit(20);

        if (response.isNotEmpty) {
          return List<Map<String, dynamic>>.from(response);
        }
      }
    } catch (e) {
      debugPrint('Error fetching trips from Supabase: $e');
    }

    // Fallback to local persistent cache
    return PersistentStorage.getCachedTrips();
  }

  /// Fetches emergency contacts for the user
  Future<List<Map<String, dynamic>>> getEmergencyContacts() async {
    try {
      final user = client.auth.currentUser;
      if (user != null) {
        final response = await client
            .from('emergency_contacts')
            .select('*')
            .eq('user_id', user.id);
        return List<Map<String, dynamic>>.from(response);
      }
    } catch (e) {
      debugPrint('Notice fetching emergency contacts: $e');
    }
    return [];
  }

  /// Saves an emergency contact
  Future<bool> addEmergencyContact({
    required String name,
    required String phone,
    required String relationship,
  }) async {
    try {
      final user = client.auth.currentUser;
      final userId = user?.id ?? 'demo-user';
      await client.from('emergency_contacts').insert({
        'user_id': userId,
        'contact_name': name,
        'contact_phone': phone,
        'relationship': relationship,
      });
      return true;
    } catch (e) {
      debugPrint('Error adding emergency contact: $e');
      return false;
    }
  }

  /// Saves driver rating and review
  Future<void> submitDriverRating({
    required String rideId,
    required double rating,
    required List<String> badges,
    String? comment,
  }) async {
    try {
      await client.from('rides').update({
        'rating': rating,
        'notes': badges.join(', ') + (comment != null && comment.isNotEmpty ? ' | $comment' : ''),
      }).eq('id', rideId);
    } catch (e) {
      debugPrint('Notice submitting rating: $e');
    }
  }
}
