import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'core/services/persistent_storage.dart';
import 'core/theme/app_theme.dart';
import 'features/splash/splash_screen.dart';
import 'features/auth/auth_screen.dart';
import 'features/rider/rider_home_screen.dart';
import 'features/driver/driver_radar_screen.dart';

/// Rafik — رَفِيق | Modern Egyptian Safe Ride-Hailing Platform
/// All rights reserved to Rafik 2026.
void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await Supabase.initialize(
      url: 'https://xertkpwuovmfwwwmdjbe.supabase.co',
      publishableKey: 'sb_publishable_4HE2NkOBjDAz5ickKabSbA_RijeYGeJ',
    );
  } catch (e) {
    debugPrint('[Rafik] Supabase init skipped — running in local mode: $e');
  }

  runApp(const RafikApp());
}

class RafikApp extends StatefulWidget {
  const RafikApp({super.key});

  @override
  State<RafikApp> createState() => _RafikAppState();
}

class _RafikAppState extends State<RafikApp> {
  bool _showSplash = true;
  bool _isLoggedIn = false;
  String _userRole = 'rider';

  @override
  void initState() {
    super.initState();
    _checkSession();
  }

  Future<void> _checkSession() async {
    final session = await PersistentStorage.getUserSession();
    if (mounted) {
      setState(() {
        _isLoggedIn = (session != null && (session['id']?.toString().isNotEmpty ?? false));
        _userRole = session?['role'] ?? 'rider';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Rafik (رفيق)',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: ThemeMode.dark,
      home: _showSplash
          ? RafikSplashScreen(
              onAnimationComplete: () {
                setState(() => _showSplash = false);
              },
            )
          : (_isLoggedIn
              ? (_userRole == 'driver' ? const DriverRadarScreen() : const RiderHomeScreen())
              : const AuthScreen()),
    );
  }
}
