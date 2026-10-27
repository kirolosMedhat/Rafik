import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

/// Default [FirebaseOptions] for use with your Firebase apps.
///
/// Configure your Firebase project details in this file or pass them
/// via environment variables / google-services.json.
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

  // Configurable Firebase Project Credentials
  // Replace these with your actual Firebase project settings from the Firebase Console
  static const String projectId = String.fromEnvironment(
    'FIREBASE_PROJECT_ID',
    defaultValue: 'rafik-app-2026',
  );

  static const String apiKey = String.fromEnvironment(
    'FIREBASE_API_KEY',
    defaultValue: 'AIzaSyDemoDummyApiKeyForRafikEcosystem2026',
  );

  static const String appIdAndroid = String.fromEnvironment(
    'FIREBASE_APP_ID_ANDROID',
    defaultValue: '1:100000000000:android:abcdef1234567890abcdef',
  );

  static const String appIdIos = String.fromEnvironment(
    'FIREBASE_APP_ID_IOS',
    defaultValue: '1:100000000000:ios:abcdef1234567890abcdef',
  );

  static const String messagingSenderId = String.fromEnvironment(
    'FIREBASE_MESSAGING_SENDER_ID',
    defaultValue: '100000000000',
  );

  static const String storageBucket = String.fromEnvironment(
    'FIREBASE_STORAGE_BUCKET',
    defaultValue: 'rafik-app-2026.appspot.com',
  );

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: apiKey,
    appId: '1:100000000000:web:abcdef1234567890abcdef',
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
    appId: appIdIos,
    messagingSenderId: messagingSenderId,
    projectId: projectId,
    storageBucket: storageBucket,
    iosBundleId: 'com.rafik.app',
  );
}
