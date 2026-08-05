// lib/firebase_options.dart
// File generated manually for Firebase initialization across Web, Android, and iOS.
// Uses project 'taskora-ab918' credentials.

import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

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
      case TargetPlatform.macOS:
        return ios;
      case TargetPlatform.windows:
        throw UnsupportedError(
          'DefaultFirebaseOptions have not been configured for windows - '
          'you can reconfigure this by running the FlutterFire CLI.',
        );
      case TargetPlatform.linux:
        throw UnsupportedError(
          'DefaultFirebaseOptions have not been configured for linux - '
          'you can reconfigure this by running the FlutterFire CLI.',
        );
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions are not supported for this platform.',
        );
    }
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyDZCsd-frVD0GTSHYpMLR3cnhTM7M-t1Ic',
    appId: '1:140024409514:web:fcf60a381852c8929c4fd3',
    messagingSenderId: '140024409514',
    projectId: 'taskora-ab918',
    authDomain: 'taskora-ab918.firebaseapp.com',
    storageBucket: 'taskora-ab918.firebasestorage.app',
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyDZCsd-frVD0GTSHYpMLR3cnhTM7M-t1Ic',
    appId: '1:140024409514:android:fcf60a381852c8929c4fd3',
    messagingSenderId: '140024409514',
    projectId: 'taskora-ab918',
    storageBucket: 'taskora-ab918.firebasestorage.app',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyDZCsd-frVD0GTSHYpMLR3cnhTM7M-t1Ic',
    appId: '1:140024409514:ios:fcf60a381852c8929c4fd3',
    messagingSenderId: '140024409514',
    projectId: 'taskora-ab918',
    storageBucket: 'taskora-ab918.firebasestorage.app',
    iosBundleId: 'com.example.taskOra',
  );
}
