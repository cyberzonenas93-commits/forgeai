import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

import 'src/core/branding/app_branding.dart';

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      throw UnsupportedError(
        '$kAppDisplayName web support is not configured in this workspace.',
      );
    }

    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions are not configured for this platform.',
        );
    }
  }

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyCvC3uWo2Iu_RqI_d5t_2OgD7R747Hso_E',
    appId: '1:560540704761:android:be77d6236e17a12aa0e728',
    messagingSenderId: '560540704761',
    projectId: 'forgeai-555ee',
    storageBucket: 'forgeai-555ee.firebasestorage.app',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyC7yYVCr3KfgfrjnzTEm5POcUohPcqqrvc',
    appId: '1:560540704761:ios:b731e8b285335363a0e728',
    messagingSenderId: '560540704761',
    projectId: 'forgeai-555ee',
    storageBucket: 'forgeai-555ee.firebasestorage.app',
    iosBundleId: 'com.angelonartey.forgeai',
    iosClientId:
        '560540704761-2l7cj1v94jud4u7kelp9k1qkvgbt0t8v.apps.googleusercontent.com',
  );
}
