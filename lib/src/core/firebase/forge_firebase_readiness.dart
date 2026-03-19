import 'package:firebase_core/firebase_core.dart';

bool forgeHasInitializedFirebaseApp() {
  try {
    Firebase.app();
    return true;
  } on FirebaseException {
    return false;
  } catch (_) {
    return false;
  }
}
