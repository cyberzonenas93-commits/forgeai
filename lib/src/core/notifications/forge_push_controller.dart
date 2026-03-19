import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../features/auth/application/auth_controller.dart';
import '../../shared/forge_models.dart';
import '../../shared/forge_user_friendly_error.dart';
import '../observability/forge_telemetry.dart';
import 'forge_push_service.dart';

class ForgePushState {
  const ForgePushState({
    this.isInitialized = false,
    this.isRequestingPermission = false,
    this.permissionStatus = ForgePushPermissionStatus.notDetermined,
    this.token,
    this.errorMessage,
  });

  final bool isInitialized;
  final bool isRequestingPermission;
  final ForgePushPermissionStatus permissionStatus;
  final String? token;
  final String? errorMessage;

  bool get canReceivePush =>
      token != null &&
      (permissionStatus == ForgePushPermissionStatus.authorized ||
          permissionStatus == ForgePushPermissionStatus.provisional);

  ForgePushState copyWith({
    bool? isInitialized,
    bool? isRequestingPermission,
    ForgePushPermissionStatus? permissionStatus,
    String? token,
    String? errorMessage,
    bool clearToken = false,
    bool clearError = false,
  }) {
    return ForgePushState(
      isInitialized: isInitialized ?? this.isInitialized,
      isRequestingPermission:
          isRequestingPermission ?? this.isRequestingPermission,
      permissionStatus: permissionStatus ?? this.permissionStatus,
      token: clearToken ? null : (token ?? this.token),
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }
}

class ForgePushController extends ValueNotifier<ForgePushState> {
  ForgePushController({
    required ForgePushService service,
    required AuthController authController,
    required Future<void> Function({
      required String token,
      required String platform,
      required ForgePushPermissionStatus permissionStatus,
    })
    registerToken,
    required Future<void> Function(String token) unregisterToken,
    ForgeTelemetry? telemetry,
  }) : _service = service,
       _authController = authController,
       _registerToken = registerToken,
       _unregisterToken = unregisterToken,
       _telemetry = telemetry ?? ForgeTelemetry.instance,
       super(const ForgePushState()) {
    _authController.addListener(_handleAuthChanged);
    unawaited(_initialize());
  }

  ForgePushController.preview({
    required AuthController authController,
    ForgeTelemetry? telemetry,
  }) : _service = null,
       _authController = authController,
       _registerToken = _noopRegisterToken,
       _unregisterToken = _noopUnregisterToken,
       _telemetry = telemetry ?? ForgeTelemetry.instance,
       super(const ForgePushState(isInitialized: true)) {
    _authController.addListener(_handleAuthChanged);
  }

  final ForgePushService? _service;
  final AuthController _authController;
  final Future<void> Function({
    required String token,
    required String platform,
    required ForgePushPermissionStatus permissionStatus,
  })
  _registerToken;
  final Future<void> Function(String token) _unregisterToken;
  final ForgeTelemetry _telemetry;

  StreamSubscription<ForgePushRoute>? _routeSubscription;
  StreamSubscription<ForgePushRegistration>? _registrationSubscription;
  Future<void> Function(ForgePushRoute route)? _routeHandler;
  ForgePushRoute? _pendingRoute;
  String? _lastRegisteredToken;
  String _lastPlatform = 'unknown';

  static Future<void> _noopRegisterToken({
    required String token,
    required String platform,
    required ForgePushPermissionStatus permissionStatus,
  }) async {}

  static Future<void> _noopUnregisterToken(String token) async {}

  Future<void> _initialize() async {
    final service = _service;
    if (service == null) {
      value = value.copyWith(isInitialized: true, clearError: true);
      return;
    }
    try {
      await service.initialize();
      _routeSubscription = service.routes.listen(_handleRoute);
      _registrationSubscription = service.registrations.listen(
        _handleRegistration,
      );
      // Pull current registration after listeners are attached so launch-time
      // state is consistent even if the initial service event was emitted
      // before this controller subscribed.
      final registration = await service.refreshRegistration();
      await _handleRegistration(registration);
      value = value.copyWith(isInitialized: true, clearError: true);
    } catch (error, stackTrace) {
      value = value.copyWith(errorMessage: forgeUserFriendlyMessage(error));
      unawaited(
        _telemetry.recordError(
          error,
          stackTrace,
          reason: 'push_initialize',
        ),
      );
    }
  }

  Future<void> requestPermission() async {
    final service = _service;
    if (service == null) {
      value = value.copyWith(
        isRequestingPermission: false,
        clearError: true,
      );
      return;
    }
    value = value.copyWith(
      isRequestingPermission: true,
      clearError: true,
    );
    try {
      final registration = await service.refreshRegistration(
        requestPermission: true,
      );
      await _handleRegistration(registration);
      value = value.copyWith(isRequestingPermission: false, clearError: true);
    } catch (error, stackTrace) {
      value = value.copyWith(
        isRequestingPermission: false,
        errorMessage: forgeUserFriendlyMessage(error),
      );
      unawaited(
        _telemetry.recordError(
          error,
          stackTrace,
          reason: 'push_request_permission',
        ),
      );
    }
  }

  void attachRouteHandler(Future<void> Function(ForgePushRoute route) handler) {
    _routeHandler = handler;
    final pendingRoute = _pendingRoute;
    if (pendingRoute != null) {
      _pendingRoute = null;
      unawaited(handler(pendingRoute));
    }
  }

  void detachRouteHandler() {
    _routeHandler = null;
  }

  void _handleRoute(ForgePushRoute route) {
    final handler = _routeHandler;
    if (handler == null) {
      _pendingRoute = route;
      return;
    }
    unawaited(handler(route));
  }

  Future<void> _handleRegistration(ForgePushRegistration registration) async {
    final previousToken = _lastRegisteredToken;
    _lastPlatform = registration.platform;
    value = value.copyWith(
      permissionStatus: registration.permissionStatus,
      token: registration.token,
      clearToken: registration.token == null,
      clearError: true,
    );

    if (registration.token == null) {
      if (previousToken != null) {
        await _unregisterToken(previousToken);
        _lastRegisteredToken = null;
      }
      return;
    }

    if (previousToken != null && previousToken != registration.token) {
      await _unregisterToken(previousToken);
    }

    if (_authController.value.account != null) {
      await _registerToken(
        token: registration.token!,
        platform: registration.platform,
        permissionStatus: registration.permissionStatus,
      );
      _lastRegisteredToken = registration.token;
    }
  }

  void _handleAuthChanged() {
    final account = _authController.value.account;
    if (account == null) {
      final token = _lastRegisteredToken;
      if (token != null) {
        unawaited(_unregisterToken(token));
        _lastRegisteredToken = null;
      }
      return;
    }

    final token = value.token;
    if (token == null) {
      return;
    }
    unawaited(
      _registerToken(
        token: token,
        platform: _lastPlatform,
        permissionStatus: value.permissionStatus,
      ),
    );
    _lastRegisteredToken = token;
  }

  @override
  void dispose() {
    _authController.removeListener(_handleAuthChanged);
    unawaited(_routeSubscription?.cancel());
    unawaited(_registrationSubscription?.cancel());
    final service = _service;
    if (service != null) {
      unawaited(service.dispose());
    }
    super.dispose();
  }
}
