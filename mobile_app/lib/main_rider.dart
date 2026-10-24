import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'core/theme/app_theme.dart';
import 'features/splash/splash_screen.dart';
import 'features/auth/auth_screen.dart';
import 'features/rider/rider_home_screen.dart';

// Environment variables supplied via --dart-define-from-file=env/dev.json
const String kSupabaseUrl = String.fromEnvironment(
  'SUPABASE_URL',
  defaultValue: 'https://xertkpwuovmfwwwmdjbe.supabase.co',
);
const String kSupabaseKey = String.fromEnvironment(
  'SUPABASE_PUBLISHABLE_KEY',
  defaultValue: 'sb_publishable_4HE2NkOBjDAz5ickKabSbA_RijeYGeJ',
);

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (kSupabaseUrl.isEmpty || kSupabaseKey.isEmpty) {
    runApp(const FatalConfigErrorApp());
    return;
  }

  try {
    await Supabase.initialize(
      url: kSupabaseUrl,
      publishableKey: kSupabaseKey,
    );
  } catch (e) {
    debugPrint('[Rafik Rider] Supabase initialization error: $e');
  }

  runApp(const RafikRiderApp());
}

/// Fatal Configuration Error Display (Phase 3 Requirement)
class FatalConfigErrorApp extends StatelessWidget {
  const FatalConfigErrorApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: const Color(0xFF0A0A0C),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error_outline, color: Color(0xFFE11D48), size: 64),
                const SizedBox(height: 20),
                const Text(
                  'Configuration Missing',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Rafik requires Supabase configuration at build time.\nPlease launch using:\nflutter run -t lib/main_rider.dart --dart-define-from-file=env/dev.json',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white70, fontSize: 13, height: 1.5),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class RafikRiderApp extends StatefulWidget {
  const RafikRiderApp({super.key});

  @override
  State<RafikRiderApp> createState() => _RafikRiderAppState();
}

class _RafikRiderAppState extends State<RafikRiderApp> {
  bool _showSplash = true;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Rafik Rider - رَفِيق',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      home: _showSplash
          ? RafikSplashScreen(
              onAnimationComplete: () {
                setState(() => _showSplash = false);
              },
            )
          : StreamBuilder<AuthState>(
              stream: Supabase.instance.client.auth.onAuthStateChange,
              builder: (context, snapshot) {
                final session = Supabase.instance.client.auth.currentSession;
                if (session != null) {
                  return const RiderHomeScreen();
                }
                return const AuthScreen(initialRole: 'rider');
              },
            ),
    );
  }
}
