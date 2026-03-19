import '../branding/app_branding.dart';
import 'forge_firebase_config.dart';

class FirebaseBootstrap {
  const FirebaseBootstrap({required this.config, required this.reviewNotes});

  factory FirebaseBootstrap.production() {
    return FirebaseBootstrap(
      config: ForgeFirebaseConfig.production(),
      reviewNotes:
          '$kAppDisplayName uses Firebase as a backend service layer only. No terminal, shell, or remote desktop behavior is exposed in the app surface.',
    );
  }

  final ForgeFirebaseConfig config;
  final String reviewNotes;

  Map<String, dynamic> toDiagnostics() {
    return {'config': config.toMap(), 'reviewNotes': reviewNotes};
  }
}
