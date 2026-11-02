import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'core/services/firebase_service.dart';
import 'core/theme/app_theme.dart';
import 'features/auth/auth_screen.dart';
import 'features/driver/driver_onboarding_screen.dart';
import 'features/driver/driver_pending_screen.dart';
import 'features/driver/driver_radar_screen.dart';
import 'features/driver/driver_rejected_screen.dart';
import 'features/splash/splash_screen.dart';

/// Rafik Captain Entrypoint — كابتن رَفِيق
///
/// Enforces:
/// 1. Strict Driver Role Guard: Rider accounts cannot enter the captain application.
/// 2. Verification Gating:
///    - Pending drivers routed strictly to DriverPendingScreen.
///    - Rejected drivers routed strictly to DriverRejectedScreen.
///    - Only verified 'approved' drivers can enter DriverRadarScreen.
/// 3. Disabled accounts are signed out and barred from driver telemetry/radar.
void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Firebase Platform Services
  await FirebaseService().initialize();

  runApp(const RafikDriverApp());
}

class RafikDriverApp extends StatefulWidget {
  const RafikDriverApp({super.key});

  @override
  State<RafikDriverApp> createState() => _RafikDriverAppState();
}

class _RafikDriverAppState extends State<RafikDriverApp> {
  bool _showSplash = true;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Rafik Captain - كابتن رَفِيق',
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
                if (user == null) {
                  return const AuthScreen(initialRole: 'driver', initialIsDriver: true);
                }

                // Restore session and enforce Driver role and approval status
                return FutureBuilder<Map<String, dynamic>?>(
                  future: FirebaseService().getUserProfile(user.uid),
                  builder: (context, profileSnap) {
                    if (profileSnap.connectionState == ConnectionState.waiting) {
                      return const _DriverSessionLoadingView();
                    }

                    final profile = profileSnap.data;

                    // If profile document does not exist, sign out
                    if (profile == null) {
                      FirebaseService().signOut();
                      return const AuthScreen(initialRole: 'driver', initialIsDriver: true);
                    }

                    // Enforce role separation: Block rider accounts from entering driver app
                    final role = profile['role']?.toString().toLowerCase();
                    if (role != 'driver') {
                      debugPrint('[DriverApp] Unauthorized rider attempt on captain app. Signing out.');
                      FirebaseService().signOut();
                      return const AuthScreen(initialRole: 'driver', initialIsDriver: true);
                    }

                    // Check active account status
                    if (profile['is_active'] == false) {
                      debugPrint('[DriverApp] Driver account is deactivated. Signing out.');
                      FirebaseService().signOut();
                      return const AuthScreen(initialRole: 'driver', initialIsDriver: true);
                    }

                    // Enforce Driver Approval State Gating
                    final status = profile['status']?.toString().toLowerCase() ?? 'pending';

                    switch (status) {
                      case 'approved':
                        return const DriverRadarScreen();
                      case 'rejected':
                        return DriverRejectedScreen(
                          rejectionReason: profile['rejection_reason']?.toString(),
                        );
                      case 'pending':
                        return const DriverPendingScreen();
                      default:
                        // Document intake incomplete
                        return DriverOnboardingScreen(
                          driverId: user.uid,
                          driverGender: profile['gender']?.toString() ?? 'female',
                          isUperGirlEnrolled: profile['gender'] == 'female',
                        );
                    }
                  },
                );
              },
            ),
    );
  }
}

class _DriverSessionLoadingView extends StatelessWidget {
  const _DriverSessionLoadingView();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Color(0xFF0F080D),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 36,
              height: 36,
              child: CircularProgressIndicator(
                color: AppTheme.roseGold,
                strokeWidth: 2.5,
              ),
            ),
            SizedBox(height: 16),
            Text(
              'جاري التحقق من ترخيص واعتماد الكابتن...',
              style: TextStyle(
                color: Colors.white70,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
