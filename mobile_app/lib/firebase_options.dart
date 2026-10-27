import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

/// Default [FirebaseOptions] for use with your Firebase apps.
///
/// Pre-configured with your active Firebase project `rafik-98844`.
class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      return web;
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions are not supported for this platform.',
        );
    }
  }

  // Active Firebase Credentials for Project: rafik-98844
  static const String projectId = 'rafik-98844';
  static const String apiKey = 'AIzaSyDBU-B8IydIt4XhFZehus0kcJQIGffLya0';
  static const String appIdAndroid = '1:933541427773:android:008c2d2e4c76d9d3fdc854';
  static const String messagingSenderId = '933541427773';
  static const String storageBucket = 'rafik-98844.firebasestorage.app';

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: apiKey,
    appId: appIdAndroid,
    messagingSenderId: messagingSenderId,
    projectId: projectId,
    storageBucket: storageBucket,
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: apiKey,
    appId: appIdAndroid,
    messagingSenderId: messagingSenderId,
    projectId: projectId,
    storageBucket: storageBucket,
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: apiKey,
    appId: appIdAndroid,
    messagingSenderId: messagingSenderId,
    projectId: projectId,
    storageBucket: storageBucket,
    iosBundleId: 'com.rafik.rider',
  );
}
