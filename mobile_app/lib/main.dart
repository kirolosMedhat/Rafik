import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'core/services/firebase_service.dart';
import 'core/theme/app_theme.dart';
import 'features/splash/splash_screen.dart';
import 'features/auth/auth_screen.dart';
import 'features/rider/rider_home_screen.dart';
import 'features/driver/driver_radar_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Firebase Cloud Engine
  await FirebaseService().initialize();

  runApp(const RafikApp());
}

class RafikApp extends StatefulWidget {
  const RafikApp({super.key});

  @override
  State<RafikApp> createState() => _RafikAppState();
}

class _RafikAppState extends State<RafikApp> {
  bool _showSplash = true;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Rafik - رَفِيق',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      home: _showSplash
          ? RafikSplashScreen(
              onAnimationComplete: () {
                setState(() => _showSplash = false);
              },
            )
          : StreamBuilder<User?>(
              stream: FirebaseService().authStateChanges,
              builder: (context, snapshot) {
                final user = snapshot.data ?? FirebaseService().currentUser;
                if (user != null) {
                  return FutureBuilder<Map<String, dynamic>?>(
                    future: FirebaseService().getCurrentUserProfile(),
                    builder: (context, profSnap) {
                      if (profSnap.connectionState == ConnectionState.waiting) {
                        return const Scaffold(
                          backgroundColor: Color(0xFF12080C),
                          body: Center(
                            child: CircularProgressIndicator(color: AppTheme.roseGold),
                          ),
                        );
                      }
                      final role = profSnap.data?['role']?.toString();
                      if (role == 'driver') {
                        return const DriverRadarScreen();
                      }
                      return const RiderHomeScreen();
                    },
                  );
                }
                return const AuthScreen();
              },
            ),
    );
  }
}
