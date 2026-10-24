import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// Rafik Local Persistent Storage Service
/// Manages user authentication session, active role, language, theme, and cached trips.
class PersistentStorage {
  static const String keyIsLoggedIn = 'rafik_is_logged_in';
  static const String keyUserRole = 'rafik_user_role'; // 'rider' or 'driver'
  static const String keyUserName = 'rafik_user_name';
  static const String keyUserPhone = 'rafik_user_phone';
  static const String keyUserId = 'rafik_user_id';
  static const String keyGender = 'rafik_user_gender'; // 'female' or 'male'
  static const String keyUperGirlEnabled = 'rafik_uper_girl_enabled'; // bool
  static const String keyCachedTrips = 'rafik_cached_trips';
  static const String keyDriverEarnings = 'rafik_driver_earnings';
  static const String keyLanguage = 'rafik_language'; // 'en' or 'ar'
  static const String keyThemeMode = 'rafik_theme_mode'; // 'dark', 'black', 'light'

  static Future<void> saveUserSession({
    required String id,
    required String name,
    required String phone,
    required String role,
    String gender = 'female',
    bool uperGirlEnabled = true,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(keyIsLoggedIn, true);
    await prefs.setString(keyUserId, id);
    await prefs.setString(keyUserName, name);
    await prefs.setString(keyUserPhone, phone);
    await prefs.setString(keyUserRole, role);
    await prefs.setString(keyGender, gender);
    await prefs.setBool(keyUperGirlEnabled, uperGirlEnabled);
  }

  static Future<Map<String, dynamic>?> getUserSession() async {
    final prefs = await SharedPreferences.getInstance();
    final isLoggedIn = prefs.getBool(keyIsLoggedIn) ?? false;
    if (!isLoggedIn) return null;

    return {
      'id': prefs.getString(keyUserId) ?? '',
      'name': prefs.getString(keyUserName) ?? 'Rafik User',
      'phone': prefs.getString(keyUserPhone) ?? '',
      'role': prefs.getString(keyUserRole) ?? 'rider',
      'gender': prefs.getString(keyGender) ?? 'female',
      'uperGirlEnabled': prefs.getBool(keyUperGirlEnabled) ?? true,
    };
  }

  static Future<bool> isLoggedIn() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(keyIsLoggedIn) ?? false;
  }

  static Future<bool> isUperGirlEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(keyUperGirlEnabled) ?? true;
  }

  static Future<void> setUperGirlEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(keyUperGirlEnabled, value);
  }

  static Future<String> getUserGender() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(keyGender) ?? 'female';
  }

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

  static Future<void> clearSession() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(keyIsLoggedIn);
    await prefs.remove(keyUserId);
    await prefs.remove(keyUserName);
    await prefs.remove(keyUserPhone);
    await prefs.remove(keyUserRole);
    await prefs.remove(keyGender);
    await prefs.remove(keyUperGirlEnabled);
  }

  /// Appends a completed ride to local trip history cache
  static Future<void> cacheCompletedTrip(Map<String, dynamic> trip) async {
    final prefs = await SharedPreferences.getInstance();
    final rawList = prefs.getStringList(keyCachedTrips) ?? [];
    rawList.insert(0, jsonEncode(trip));
    if (rawList.length > 50) rawList.removeLast();
    await prefs.setStringList(keyCachedTrips, rawList);
  }

  /// Retrieves list of cached trips
  static Future<List<Map<String, dynamic>>> getCachedTrips() async {
    final prefs = await SharedPreferences.getInstance();
    final rawList = prefs.getStringList(keyCachedTrips) ?? [];
    return rawList.map((str) {
      try {
        return jsonDecode(str) as Map<String, dynamic>;
      } catch (_) {
        return <String, dynamic>{};
      }
    }).where((m) => m.isNotEmpty).toList();
  }

  /// Saves driver total earnings
  static Future<void> updateDriverEarnings(double amount) async {
    final prefs = await SharedPreferences.getInstance();
    final current = prefs.getDouble(keyDriverEarnings) ?? 0.0;
    await prefs.setDouble(keyDriverEarnings, current + amount);
  }

  static Future<double> getDriverEarnings() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getDouble(keyDriverEarnings) ?? 680.0;
  }
}
