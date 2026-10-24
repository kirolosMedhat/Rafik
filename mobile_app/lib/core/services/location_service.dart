import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

/// Rafik Location & GPS Tracking Service
/// Handles real device GPS, permission requests, and route interpolation.
class LocationService {
  static final LocationService _instance = LocationService._internal();
  factory LocationService() => _instance;
  LocationService._internal();

  StreamSubscription<Position>? _positionStream;

  /// Default Cairo Center Location (Tahrir / Downtown)
  static const LatLng defaultCairoCenter = LatLng(30.0444, 31.2357);

  /// Requests location permissions from the user
  Future<bool> checkAndRequestPermission() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      return false;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        return false;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      return false;
    }

    return true;
  }

  /// Gets the current location or falls back to Zamalek / Downtown Cairo
  Future<LatLng> getCurrentLocation() async {
    try {
      final hasPermission = await checkAndRequestPermission();
      if (!hasPermission) return defaultCairoCenter;

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 5),
        ),
      );
      return LatLng(position.latitude, position.longitude);
    } catch (e) {
      debugPrint('Location error, using fallback: $e');
      return defaultCairoCenter;
    }
  }

  /// Calculates straight-line distance in kilometers
  static double calculateDistanceKm(LatLng start, LatLng end) {
    const distance = Distance();
    final meters = distance.as(LengthUnit.Meter, start, end);
    return meters / 1000.0;
  }

  /// Generates intermediate points between start and end for smooth GPS simulation
  static List<LatLng> interpolatePoints(LatLng start, LatLng end, int steps) {
    final points = <LatLng>[];
    for (int i = 0; i <= steps; i++) {
      final t = i / steps.toDouble();
      final lat = start.latitude + (end.latitude - start.latitude) * t;
      final lng = start.longitude + (end.longitude - start.longitude) * t;
      points.add(LatLng(lat, lng));
    }
    return points;
  }

  /// Calculates compass heading bearing between two coordinates
  static double calculateBearing(LatLng start, LatLng end) {
    const distance = Distance();
    return distance.bearing(start, end);
  }

  void dispose() {
    _positionStream?.cancel();
  }
}
