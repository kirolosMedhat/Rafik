import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'core/services/firebase_service.dart';
import 'core/theme/app_theme.dart';
import 'features/auth/auth_screen.dart';
import 'features/driver/driver_onboarding_screen.dart';
import 'features/driver/driver_pending_screen.dart';
import 'features/driver/driver_radar_screen.dart';
import 'features/driver/driver_rejected_screen.dart';
import 'features/rider/rider_home_screen.dart';
import 'features/splash/splash_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Firebase Cloud Engine
  await FirebaseService().initialize();

  runApp(const GoSafeApp());
}

class GoSafeApp extends StatefulWidget {
  const GoSafeApp({super.key});

  @override
  State<GoSafeApp> createState() => _GoSafeAppState();
}

class _GoSafeAppState extends State<GoSafeApp> {
  bool _showSplash = true;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Rafik Go Safe - رَفِيق',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      home: _showSplash
          ? GoSafeSplashScreen(
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
                    future: FirebaseService().getUserProfile(user.uid),
                    builder: (context, profSnap) {
                      if (profSnap.connectionState == ConnectionState.waiting) {
                        return const Scaffold(
                          backgroundColor: Color(0xFF12080C),
                          body: Center(
                            child: CircularProgressIndicator(color: AppTheme.roseGold),
                          ),
                        );
                      }

                      final profile = profSnap.data;
                      if (profile == null) {
                        FirebaseService().signOut();
                        return const AuthScreen();
                      }

                      if (profile['is_active'] == false) {
                        FirebaseService().signOut();
                        return const AuthScreen();
                      }

                      final role = profile['role']?.toString().toLowerCase();
                      if (role == 'driver') {
                        final status = profile['status']?.toString().toLowerCase() ?? 'pending';
                        if (status == 'approved') {
                          return const DriverRadarScreen();
                        } else if (status == 'rejected') {
                          return DriverRejectedScreen(
                            rejectionReason: profile['rejection_reason']?.toString(),
                          );
                        } else if (status == 'pending') {
                          return const DriverPendingScreen();
                        } else {
                          return DriverOnboardingScreen(
                            driverId: user.uid,
                            driverGender: profile['gender']?.toString() ?? 'female',
                            isUperGirlEnrolled: profile['gender'] == 'female',
                          );
                        }
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
