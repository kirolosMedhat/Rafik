import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'core/services/firebase_service.dart';
import 'core/theme/app_theme.dart';
import 'features/splash/splash_screen.dart';
import 'features/auth/auth_screen.dart';
import 'features/driver/driver_radar_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Firebase Cloud Engine
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
                if (user != null) {
                  return const DriverRadarScreen();
                }
                return const AuthScreen(initialRole: 'driver', initialIsDriver: true);
              },
            ),
    );
  }
}
