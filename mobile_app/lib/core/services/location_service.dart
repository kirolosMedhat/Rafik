import 'dart:async';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

/// Detailed location permission status
enum DetailedLocationStatus {
  granted,
  serviceDisabled,
  denied,
  deniedForever,
}

/// Rafik Location & GPS Tracking Service
/// Handles real device GPS, permission requests, and localized guidance.
class LocationService {
  static final LocationService _instance = LocationService._internal();
  factory LocationService() => _instance;
  LocationService._internal();

  StreamSubscription<Position>? _positionStream;

  /// Default Cairo Center Location (Tahrir / Downtown)
  static const LatLng defaultCairoCenter = LatLng(30.0444, 31.2357);

  /// Checks detailed location status with granular failure classification
  Future<DetailedLocationStatus> checkDetailedStatus() async {
    final bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      return DetailedLocationStatus.serviceDisabled;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        return DetailedLocationStatus.denied;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      return DetailedLocationStatus.deniedForever;
    }

    return DetailedLocationStatus.granted;
  }

  /// Requests location permissions from the user
  Future<bool> checkAndRequestPermission() async {
    final status = await checkDetailedStatus();
    return status == DetailedLocationStatus.granted;
  }

  /// Displays localized permission guidance dialog
  Future<void> showPermissionDialog({
    required BuildContext context,
    required DetailedLocationStatus status,
    bool isArabic = false,
  }) async {
    String title;
    String message;
    String buttonText;
    VoidCallback? onAction;

    switch (status) {
      case DetailedLocationStatus.serviceDisabled:
        title = isArabic ? 'خدمة الموقع معطلة' : 'Location Service Disabled';
        message = isArabic
            ? 'يرجى تفعيل نظام تحديد المواقع (GPS) على هاتفك للمتابعة مع رفيق.'
            : 'Please enable GPS location services on your device to continue using Rafik.';
        buttonText = isArabic ? 'تفعيل الموقع' : 'Open Location Settings';
        onAction = () => Geolocator.openLocationSettings();
        break;
      case DetailedLocationStatus.deniedForever:
        title = isArabic ? 'إذن الموقع مرفوض دائماً' : 'Location Permission Required';
        message = isArabic
            ? 'تم رفض إذن الموقع بشكل دائم. يرجى فتح إعدادات التطبيق وتفعيل إذن الموقع للمتابعة.'
            : 'Location permission is permanently denied. Please grant permission in application settings to proceed.';
        buttonText = isArabic ? 'فتح الإعدادات' : 'Open Settings';
        onAction = () => Geolocator.openAppSettings();
        break;
      case DetailedLocationStatus.denied:
        title = isArabic ? 'مطلوب إذن الموقع' : 'Location Permission Required';
        message = isArabic
            ? 'يحتاج رفيق إلى إذن الموقع لتحديد نقطة الركوب والوجهة وتتبع الرحلة.'
            : 'Rafik requires location permissions to pinpoint pickup, destination, and live tracking.';
        buttonText = isArabic ? 'حسناً' : 'Got it';
        onAction = null;
        break;
      case DetailedLocationStatus.granted:
        return;
    }

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          title,
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          textDirection: isArabic ? TextDirection.rtl : TextDirection.ltr,
        ),
        content: Text(
          message,
          style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 14),
          textDirection: isArabic ? TextDirection.rtl : TextDirection.ltr,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              isArabic ? 'إلغاء' : 'Cancel',
              style: const TextStyle(color: Color(0xFF64748B)),
            ),
          ),
          if (onAction != null)
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF3B82F6),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              onPressed: () {
                Navigator.pop(ctx);
                onAction?.call();
              },
              child: Text(buttonText),
            ),
        ],
      ),
    );
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
