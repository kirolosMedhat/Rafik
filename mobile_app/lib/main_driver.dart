import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'core/services/persistent_storage.dart';
import 'core/theme/app_theme.dart';
import 'features/splash/splash_screen.dart';
import 'features/auth/auth_screen.dart';
import 'features/driver/driver_radar_screen.dart';

/// Rafik Driver / Captain App (تطبيق كابتن رَفِيق للسائقين والسائقات)
/// Dedicated driver experience: Go Online/Offline, 15s Dispatch Radar, PIN Verification, 6-Sided Vault.
/// All rights reserved to Rafik 2026.
void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await Supabase.initialize(
      url: 'https://xertkpwuovmfwwwmdjbe.supabase.co',
      publishableKey: 'sb_publishable_4HE2NkOBjDAz5ickKabSbA_RijeYGeJ',
    );
  } catch (e) {
    debugPrint('[Rafik Driver] Supabase init skipped — local mode: $e');
  }

  runApp(const RafikDriverApp());
}

class RafikDriverApp extends StatefulWidget {
  const RafikDriverApp({super.key});

  @override
  State<RafikDriverApp> createState() => _RafikDriverAppState();
}

class _RafikDriverAppState extends State<RafikDriverApp> {
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
      title: 'Rafik Captain (كابتن رفيق)',
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
          : (_isLoggedIn ? const DriverRadarScreen() : const AuthScreen(initialIsDriver: true)),
    );
  }
}
