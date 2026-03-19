import 'dart:async';
import 'dart:convert';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../branding/app_branding.dart';

import '../../../firebase_options.dart';
import '../../shared/forge_models.dart';

const AndroidNotificationChannel _forgeNotificationChannel =
    AndroidNotificationChannel(
      'forgeai_default',
      '$kAppDisplayName Notifications',
      description: 'Status updates for repositories, checks, AI, and account events.',
      importance: Importance.high,
    );

@pragma('vm:entry-point')
Future<void> forgeFirebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
}

class ForgePushRegistration {
  const ForgePushRegistration({
    required this.permissionStatus,
    required this.platform,
    this.token,
  });

  final ForgePushPermissionStatus permissionStatus;
  final String platform;
  final String? token;

  bool get canReceivePush =>
      token != null &&
      (permissionStatus == ForgePushPermissionStatus.authorized ||
          permissionStatus == ForgePushPermissionStatus.provisional);
}

class ForgePushService {
  ForgePushService({
    FirebaseMessaging? messaging,
    FlutterLocalNotificationsPlugin? localNotifications,
  }) : _messaging = messaging ?? FirebaseMessaging.instance,
       _localNotifications =
           localNotifications ?? FlutterLocalNotificationsPlugin();

  final FirebaseMessaging _messaging;
  final FlutterLocalNotificationsPlugin _localNotifications;
  final StreamController<ForgePushRoute> _routeController =
      StreamController<ForgePushRoute>.broadcast();
  final StreamController<ForgePushRegistration> _registrationController =
      StreamController<ForgePushRegistration>.broadcast();

  StreamSubscription<RemoteMessage>? _foregroundSubscription;
  StreamSubscription<RemoteMessage>? _openedAppSubscription;
  StreamSubscription<String>? _tokenRefreshSubscription;
  bool _initialized = false;

  Stream<ForgePushRoute> get routes => _routeController.stream;
  Stream<ForgePushRegistration> get registrations =>
      _registrationController.stream;

  Future<void> initialize() async {
    if (_initialized) {
      return;
    }
    _initialized = true;

    await _initializeLocalNotifications();
    await _messaging.setForegroundNotificationPresentationOptions(
      alert: true,
      badge: true,
      sound: true,
    );

    _foregroundSubscription = FirebaseMessaging.onMessage.listen(
      _handleForegroundMessage,
    );
    _openedAppSubscription = FirebaseMessaging.onMessageOpenedApp.listen(
      _handleOpenedAppMessage,
    );
    _tokenRefreshSubscription = _messaging.onTokenRefresh.listen((token) async {
      final registration = await _buildRegistration(tokenOverride: token);
      _registrationController.add(registration);
    });

    final initialMessage = await _messaging.getInitialMessage();
    if (initialMessage != null) {
      _emitRouteFromData(initialMessage.data);
    }

    final registration = await _buildRegistration();
    _registrationController.add(registration);
  }

  Future<ForgePushRegistration> refreshRegistration({
    bool requestPermission = false,
  }) async {
    final registration = await _buildRegistration(
      requestPermission: requestPermission,
    );
    _registrationController.add(registration);
    return registration;
  }

  Future<void> _initializeLocalNotifications() async {
    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings();
    await _localNotifications.initialize(
      settings: const InitializationSettings(
        android: androidSettings,
        iOS: iosSettings,
      ),
      onDidReceiveNotificationResponse: (details) {
        if ((details.payload ?? '').isEmpty) {
          return;
        }
        final decoded = jsonDecode(details.payload!);
        if (decoded is Map<String, dynamic>) {
          _emitRouteFromData(decoded);
        } else if (decoded is Map) {
          _emitRouteFromData(decoded.map((key, value) => MapEntry('$key', value)));
        }
      },
    );

    final androidImplementation = _localNotifications
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    await androidImplementation?.createNotificationChannel(
      _forgeNotificationChannel,
    );
  }

  Future<ForgePushRegistration> _buildRegistration({
    bool requestPermission = false,
    String? tokenOverride,
  }) async {
    NotificationSettings settings = await _messaging.getNotificationSettings();
    if (requestPermission &&
        settings.authorizationStatus == AuthorizationStatus.notDetermined) {
      settings = await _messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
        provisional: true,
      );
    }

    final permissionStatus = _mapPermissionStatus(settings.authorizationStatus);
    final token =
        permissionStatus == ForgePushPermissionStatus.authorized ||
                permissionStatus == ForgePushPermissionStatus.provisional
            ? (tokenOverride ?? await _messaging.getToken())
            : null;
    return ForgePushRegistration(
      permissionStatus: permissionStatus,
      platform: _platformName(),
      token: token,
    );
  }

  Future<void> _handleForegroundMessage(RemoteMessage message) async {
    final notification = message.notification;
    if (notification != null) {
      await _localNotifications.show(
        id: notification.hashCode,
        title: notification.title ?? _fallbackTitle(message.data),
        body: notification.body ?? _fallbackBody(message.data),
        notificationDetails: NotificationDetails(
          android: AndroidNotificationDetails(
            _forgeNotificationChannel.id,
            _forgeNotificationChannel.name,
            channelDescription: _forgeNotificationChannel.description,
            importance: Importance.high,
            priority: Priority.high,
          ),
          iOS: const DarwinNotificationDetails(),
        ),
        payload: jsonEncode(message.data),
      );
    }
  }

  void _handleOpenedAppMessage(RemoteMessage message) {
    _emitRouteFromData(message.data);
  }

  void _emitRouteFromData(Map<String, dynamic> data) {
    _routeController.add(_routeFromData(data));
  }

  ForgePushRoute _routeFromData(Map<String, dynamic> data) {
    final type = data['type'] as String?;
    final destinationRaw = data['destination'] as String?;
    final destination = switch (destinationRaw) {
      'prompt' => ForgeNotificationDestination.prompt,
      'repo' => ForgeNotificationDestination.repo,
      'settings' => ForgeNotificationDestination.settings,
      'wallet' => ForgeNotificationDestination.wallet,
      'activity' => ForgeNotificationDestination.activity,
      'checks' => ForgeNotificationDestination.checks,
      _ => _destinationForType(type),
    };
    return ForgePushRoute(
      destination: destination,
      type: type,
      repoId: data['repoId'] as String?,
      threadId: data['threadId'] as String?,
      changeRequestId: data['changeRequestId'] as String?,
      title: data['title'] as String?,
      body: data['body'] as String?,
    );
  }

  ForgeNotificationDestination _destinationForType(String? type) {
    switch (type) {
      case 'check_failed':
      case 'check_passed':
      case 'workflow_finished':
        return ForgeNotificationDestination.checks;
      case 'git_action_completed':
      case 'git_action_failed':
      case 'repo_connected':
      case 'repo_sync_completed':
      case 'repo_sync_failed':
        return ForgeNotificationDestination.repo;
      case 'ai_ready':
        return ForgeNotificationDestination.prompt;
      case 'provider_issue':
      case 'security_event':
        return ForgeNotificationDestination.settings;
      case 'wallet_alert':
        return ForgeNotificationDestination.wallet;
      case 'digest':
        return ForgeNotificationDestination.activity;
      default:
        return ForgeNotificationDestination.home;
    }
  }

  ForgePushPermissionStatus _mapPermissionStatus(
    AuthorizationStatus status,
  ) {
    return switch (status) {
      AuthorizationStatus.authorized => ForgePushPermissionStatus.authorized,
      AuthorizationStatus.provisional =>
        ForgePushPermissionStatus.provisional,
      AuthorizationStatus.denied => ForgePushPermissionStatus.denied,
      AuthorizationStatus.notDetermined =>
        ForgePushPermissionStatus.notDetermined,
    };
  }

  String _platformName() {
    switch (defaultTargetPlatform) {
      case TargetPlatform.iOS:
        return 'ios';
      case TargetPlatform.android:
        return 'android';
      case TargetPlatform.macOS:
        return 'macos';
      case TargetPlatform.windows:
        return 'windows';
      case TargetPlatform.linux:
        return 'linux';
      case TargetPlatform.fuchsia:
        return 'fuchsia';
    }
  }

  String? _fallbackTitle(Map<String, dynamic> data) {
    final title = data['title'];
    return title is String && title.trim().isNotEmpty ? title : kAppDisplayName;
  }

  String? _fallbackBody(Map<String, dynamic> data) {
    final body = data['body'];
    return body is String && body.trim().isNotEmpty
        ? body
        : 'Workspace activity updated.';
  }

  Future<void> dispose() async {
    await _foregroundSubscription?.cancel();
    await _openedAppSubscription?.cancel();
    await _tokenRefreshSubscription?.cancel();
    await _routeController.close();
    await _registrationController.close();
  }
}
