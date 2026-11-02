import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Rafik Local Storage Service
/// Caches UI preferences (language, theme, last used tier) and a read-through trip history cache.
/// Cloud Firestore and Firebase Auth serve as the authoritative backend services.
class PersistentStorage {
  static const String keyLanguage = 'rafik_language'; // 'en' or 'ar'
  static const String keyThemeMode = 'rafik_theme_mode'; // 'dark', 'black', 'light'
  static const String keySelectedTier = 'rafik_selected_tier'; // 'standard' or 'rafik_girl'
  static const String keyCachedTrips = 'rafik_cached_trips';
  static const String keyDriverEarningsCache = 'rafik_driver_earnings_cache';

  // ================= UI PREFERENCES =================
  static Future<String> getLanguage() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(keyLanguage) ?? 'en';
  }

  static Future<void> setLanguage(String lang) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(keyLanguage, lang);
  }

  static Future<String> getThemeMode() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(keyThemeMode) ?? 'dark';
  }

  static Future<void> setThemeMode(String mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(keyThemeMode, mode);
  }

  static Future<String> getSelectedTier() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(keySelectedTier) ?? 'standard';
  }

  static Future<void> setSelectedTier(String tier) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(keySelectedTier, tier);
  }

  static Future<bool> isUperGirlEnabled() async {
    final tier = await getSelectedTier();
    return tier == 'rafik_girl';
  }

  static Future<String> getUserGender() async {
    return 'female';
  }

  static Future<Map<String, dynamic>?> getUserSession() async {
    final fbUser = FirebaseAuth.instance.currentUser;
    if (fbUser != null) {
      return {
        'id': fbUser.uid,
        'name': fbUser.displayName ?? 'Rafik User',
        'phone': fbUser.phoneNumber ?? '',
        'role': 'rider',
        'gender': 'female',
      };
    }
    return null;
  }

  static Future<void> clearSession() async {
    try {
      await FirebaseAuth.instance.signOut();
    } catch (_) {}
    await clearCache();
  }

  // ================= READ-THROUGH TRIP CACHE =================
  static Future<void> cacheCompletedTrip(Map<String, dynamic> trip) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final tripsList = await getCachedTrips();
      tripsList.insert(0, trip);
      if (tripsList.length > 30) {
        tripsList.removeLast();
      }
      await prefs.setString(keyCachedTrips, jsonEncode(tripsList));
    } catch (_) {}
  }

  static Future<List<Map<String, dynamic>>> getCachedTrips() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(keyCachedTrips);
      if (raw == null || raw.isEmpty) return [];
      final decoded = jsonDecode(raw) as List;
      return decoded.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> cacheDriverEarnings(double amount) async {
    final prefs = await SharedPreferences.getInstance();
    final current = prefs.getDouble(keyDriverEarningsCache) ?? 0.0;
    await prefs.setDouble(keyDriverEarningsCache, current + amount);
  }

  static Future<double> getCachedDriverEarnings() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getDouble(keyDriverEarningsCache) ?? 0.0;
  }

  static Future<double> getDriverEarnings() async {
    return getCachedDriverEarnings();
  }

  static Future<void> updateDriverEarnings(double amount) async {
    await cacheDriverEarnings(amount);
  }

  static Future<void> clearCache() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(keyCachedTrips);
    await prefs.remove(keyDriverEarningsCache);
  }
}
