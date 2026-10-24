import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'core/services/persistent_storage.dart';
import 'core/theme/app_theme.dart';
import 'features/splash/splash_screen.dart';
import 'features/auth/auth_screen.dart';
import 'features/rider/rider_home_screen.dart';

/// Rafik Rider App (تطبيق رَفِيق للركاب)
/// Dedicated passenger experience: OpenStreetMap, Instant Booking, PIN Handshake, 1-Tap SOS.
/// All rights reserved to Rafik 2026.
void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await Supabase.initialize(
      url: 'https://xertkpwuovmfwwwmdjbe.supabase.co',
      publishableKey: 'sb_publishable_4HE2NkOBjDAz5ickKabSbA_RijeYGeJ',
    );
  } catch (e) {
    debugPrint('[Rafik Rider] Supabase init skipped — local mode: $e');
  }

  runApp(const RafikRiderApp());
}

class RafikRiderApp extends StatefulWidget {
  const RafikRiderApp({super.key});

  @override
  State<RafikRiderApp> createState() => _RafikRiderAppState();
}

class _RafikRiderAppState extends State<RafikRiderApp> {
  bool _showSplash = true;
  bool _isLoggedIn = false;

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
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Rafik Rider (رفيق)',
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
          : (_isLoggedIn ? const RiderHomeScreen() : const AuthScreen()),
    );
  }
}
