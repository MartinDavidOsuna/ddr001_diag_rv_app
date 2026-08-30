import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:dio/dio.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_exception.dart';
import 'field_session_models.dart';
import 'session_secure_storage.dart';

class DeviceDescriptor {
  const DeviceDescriptor({
    required this.platform,
    required this.manufacturer,
    required this.model,
    required this.androidVersion,
    required this.appVersion,
  });
  final String platform, manufacturer, model, androidVersion, appVersion;
}

class FieldSessionRepository {
  FieldSessionRepository({
    required this.client,
    required this.storage,
    required this.packageInfo,
    this.deviceLoader,
  });

  final ApiClient client;
  final SessionStorage storage;
  final PackageInfo packageInfo;
  final Future<DeviceDescriptor> Function()? deviceLoader;
  bool lastRestoreOffline = false;

  void cancelActiveRequests() => client.cancelAuthenticatedRequests();

  Future<DeviceDescriptor> _device() async {
    if (deviceLoader != null) return deviceLoader!();
    final info = DeviceInfoPlugin();
    if (Platform.isAndroid) {
      final value = await info.androidInfo;
      return DeviceDescriptor(
        platform: 'android',
        manufacturer: value.manufacturer,
        model: value.model,
        androidVersion: value.version.release,
        appVersion: '${packageInfo.version}+${packageInfo.buildNumber}',
      );
    }
    if (Platform.isIOS) {
      final value = await info.iosInfo;
      return DeviceDescriptor(
        platform: 'ios',
        manufacturer: 'Apple',
        model: value.utsname.machine,
        androidVersion: value.systemVersion,
        appVersion: '${packageInfo.version}+${packageInfo.buildNumber}',
      );
    }
    return DeviceDescriptor(
      platform: Platform.operatingSystem,
      manufacturer: 'unknown',
      model: 'unknown',
      androidVersion: Platform.operatingSystemVersion,
      appVersion: '${packageInfo.version}+${packageInfo.buildNumber}',
    );
  }

  Future<FieldSession> start(FieldRegistration registration) async {
    final validation = registration.validate();
    if (validation != null) {
      throw ApiException(ApiErrorKind.validation, validation);
    }
    final installationId = await storage.installationId();
    final device = await _device();
    try {
      await completePendingLogout();
      final response = await client.dio.post<Map<String, dynamic>>(
        '/field-sessions/start',
        data: {
          'name': registration.normalizedName,
          'email': registration.normalizedEmail,
          'phone': registration.phone.trim(),
          'crew': registration.normalizedCrew,
          'device': {
            'installationId': installationId,
            'platform': device.platform,
            'manufacturer': device.manufacturer,
            'model': device.model,
            'androidVersion': device.androidVersion,
            'appVersion': device.appVersion,
          },
        },
        options: Options(extra: {'skipAuth': true}),
      );
      final data = response.data ?? const {};
      final session = FieldSession(
        sessionId: _required(data, 'sessionId'),
        userId: _required(data, 'userId'),
        accessToken: _required(data, 'accessToken'),
        refreshToken: _required(data, 'refreshToken'),
        installationId: installationId,
        name: registration.normalizedName,
        email: registration.normalizedEmail,
        phone: registration.phone.trim(),
        crew: registration.normalizedCrew,
        crewId: _required(data, 'crewId'),
        role: data['role']?.toString() ?? 'field',
        startedAt: DateTime.now().toUtc(),
        persistentSessionId: data['persistentSessionId']?.toString() ?? '',
        bindingId: data['bindingId']?.toString() ?? '',
      );
      await storage.save(session);
      return session;
    } on Object catch (error) {
      client.rethrowAsApi(error);
    }
  }

  Future<void> revokeExisting(String takeoverToken) async {
    try {
      await client.dio.post<void>(
        '/field-sessions/revoke-existing',
        data: {'takeoverToken': takeoverToken},
        options: Options(extra: {'skipAuth': true}),
      );
    } on DioException catch (error) {
      final apiError = ApiException.fromDio(error);
      if (error.response?.statusCode == 404 &&
          apiError.domainCode == 'SESSION_NOT_FOUND') {
        return;
      }
      throw apiError;
    }
  }

  Future<FieldSession?> restore() async {
    lastRestoreOffline = false;
    final local = await storage.read();
    if (local == null) return null;
    try {
      final response = await client.dio.get<Map<String, dynamic>>(
        '/field-sessions/current',
      );
      final data = response.data ?? const {};
      final restored = FieldSession(
        sessionId: local.sessionId,
        userId: _required(data, 'user_id'),
        accessToken: local.accessToken,
        refreshToken: local.refreshToken,
        installationId: local.installationId,
        name: local.name,
        email: local.email,
        phone: local.phone,
        crew: local.crew,
        crewId: _required(data, 'crew_id'),
        role: 'field',
        startedAt: local.startedAt,
        persistentSessionId:
            data['persistent_session_id']?.toString() ??
            local.persistentSessionId,
        bindingId: data['binding_id']?.toString() ?? local.bindingId,
      );
      await storage.save(restored);
      return restored;
    } on DioException catch (error) {
      if (error.type == DioExceptionType.connectionError ||
          error.type == DioExceptionType.connectionTimeout ||
          error.type == DioExceptionType.receiveTimeout) {
        lastRestoreOffline = true;
        return local;
      }
      if (error.response?.statusCode == 401) {
        final apiError = ApiException.fromDio(error);
        if (apiError.kind == ApiErrorKind.sessionRevoked) {
          await storage.clear();
          throw apiError;
        }
        lastRestoreOffline = true;
        return local;
      }
      rethrow;
    }
  }

  Future<bool> end() async {
    final session = await storage.read();
    if (session == null) return true;
    final pendingStorage = storage is PendingLogoutStorage
        ? storage as PendingLogoutStorage
        : null;
    await pendingStorage?.savePendingLogout(session);
    try {
      await client.dio.post<void>(
        '/field-sessions/${session.sessionId}/end',
        options: Options(
          extra: {'skipAuth': true},
          headers: {
            'Authorization': 'Bearer ${session.accessToken}',
            'Idempotency-Key': 'end-${session.sessionId}',
          },
        ),
      );
      await pendingStorage?.clearPendingLogout();
      await storage.clear();
      return true;
    } on DioException {
      // El cierre local siempre gana. El sobre cifrado queda pendiente ante
      // cualquier resultado remoto no confirmado, incluidos 5xx/timeout.
      await storage.clear();
      return false;
    }
  }

  Future<bool> completePendingLogout() async {
    if (storage is! PendingLogoutStorage) return true;
    final pendingStorage = storage as PendingLogoutStorage;
    final pending = await pendingStorage.readPendingLogout();
    if (pending == null) return true;
    try {
      await client.dio.post<void>(
        '/field-sessions/${pending.sessionId}/end',
        options: Options(
          extra: {'skipAuth': true},
          headers: {
            'Authorization': 'Bearer ${pending.accessToken}',
            'Idempotency-Key': 'end-${pending.sessionId}',
          },
        ),
      );
      await pendingStorage.clearPendingLogout();
      return true;
    } on DioException {
      return false;
    }
  }

  static String _required(Map<String, dynamic> data, String key) {
    final value = data[key]?.toString();
    if (value == null || value.isEmpty) throw FormatException('Falta $key');
    return value;
  }
}
