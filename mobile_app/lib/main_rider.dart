import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'core/services/firebase_service.dart';
import 'core/theme/app_theme.dart';
import 'features/auth/auth_screen.dart';
import 'features/rider/rider_home_screen.dart';
import 'features/splash/splash_screen.dart';

/// Rafik Rider Entrypoint — رفيق للركاب
///
/// Enforces:
/// 1. Strict Rider Role Guard: Driver accounts cannot enter the rider application.
/// 2. Session Restoration: Validates profile exists and is_active in Firestore.
/// 3. Disabled accounts are signed out and prevented from accessing protected features.
void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Firebase Platform Services
  await FirebaseService().initialize();

  runApp(const RafikRiderApp());
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
          : StreamBuilder<User?>(
              stream: FirebaseService().authStateChanges,
              builder: (context, snapshot) {
                final user = snapshot.data ?? FirebaseService().currentUser;
                if (user == null) {
                  return const AuthScreen(initialRole: 'rider');
                }

                // Restore session and enforce Rider role authorization
                return FutureBuilder<Map<String, dynamic>?>(
                  future: FirebaseService().getUserProfile(user.uid),
                  builder: (context, profileSnap) {
                    if (profileSnap.connectionState == ConnectionState.waiting) {
                      return const _RiderSessionLoadingView();
                    }

                    final profile = profileSnap.data;

                    // If profile document does not exist, sign out
                    if (profile == null) {
                      FirebaseService().signOut();
                      return const AuthScreen(initialRole: 'rider');
                    }

                    // Enforce role separation: Block driver accounts from entering rider app
                    final role = profile['role']?.toString().toLowerCase();
                    if (role != 'rider') {
                      debugPrint('[RiderApp] Unauthorized role attempt ($role). Signing out.');
                      FirebaseService().signOut();
                      return const AuthScreen(initialRole: 'rider');
                    }

                    // Check active account status
                    if (profile['is_active'] == false) {
                      debugPrint('[RiderApp] Account is deactivated. Signing out.');
                      FirebaseService().signOut();
                      return const AuthScreen(initialRole: 'rider');
                    }

                    return const RiderHomeScreen();
                  },
                );
              },
            ),
    );
  }
}

class _RiderSessionLoadingView extends StatelessWidget {
  const _RiderSessionLoadingView();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Color(0xFF12080C),
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
              'جاري استعادة الجلسة الآمنة...',
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
