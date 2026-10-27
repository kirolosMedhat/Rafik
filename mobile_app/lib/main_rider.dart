import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'core/services/firebase_service.dart';
import 'core/theme/app_theme.dart';
import 'features/splash/splash_screen.dart';
import 'features/auth/auth_screen.dart';
import 'features/rider/rider_home_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Firebase Cloud Engine
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
                if (user != null) {
                  return const RiderHomeScreen();
                }
                return const AuthScreen(initialRole: 'rider');
              },
            ),
    );
  }
}
