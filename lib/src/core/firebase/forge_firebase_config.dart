class ForgeFirebaseConfig {
  const ForgeFirebaseConfig({
    required this.projectId,
    required this.storageBucket,
    required this.androidPackageName,
    required this.iosBundleId,
    required this.androidAppId,
    required this.iosAppId,
    required this.androidApiKey,
    required this.iosApiKey,
  });

  factory ForgeFirebaseConfig.production() {
    return const ForgeFirebaseConfig(
      projectId: 'forgeai-555ee',
      storageBucket: 'forgeai-555ee.firebasestorage.app',
      androidPackageName: 'com.forgeai.app',
      iosBundleId: 'com.angelonartey.forgeai',
      androidAppId: '1:560540704761:android:be77d6236e17a12aa0e728',
      iosAppId: '1:560540704761:ios:b731e8b285335363a0e728',
      androidApiKey: 'AIzaSyCvC3uWo2Iu_RqI_d5t_2OgD7R747Hso_E',
      iosApiKey: 'AIzaSyC7yYVCr3KfgfrjnzTEm5POcUohPcqqrvc',
    );
  }

  final String projectId;
  final String storageBucket;
  final String androidPackageName;
  final String iosBundleId;
  final String androidAppId;
  final String iosAppId;
  final String androidApiKey;
  final String iosApiKey;

  Map<String, String> toMap() {
    return {
      'projectId': projectId,
      'storageBucket': storageBucket,
      'androidPackageName': androidPackageName,
      'iosBundleId': iosBundleId,
      'androidAppId': androidAppId,
      'iosAppId': iosAppId,
      'androidApiKey': androidApiKey,
      'iosApiKey': iosApiKey,
    };
  }
}
