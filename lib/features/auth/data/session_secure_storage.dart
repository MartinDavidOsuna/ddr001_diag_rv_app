import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:uuid/uuid.dart';

import 'field_session_models.dart';

abstract interface class SessionStorage {
  Future<FieldSession?> read();
  Future<void> save(FieldSession session);
  Future<void> clear();
  Future<String> installationId();
}

abstract interface class PendingLogoutStorage {
  Future<FieldSession?> readPendingLogout();
  Future<void> savePendingLogout(FieldSession session);
  Future<void> clearPendingLogout();
}

class SessionSecureStorage implements SessionStorage, PendingLogoutStorage {
  SessionSecureStorage([FlutterSecureStorage? storage])
    : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;
  static const _access = 'field_access_token';
  static const _refresh = 'field_refresh_token';
  static const _session = 'field_session_id';
  static const _user = 'field_user_id';
  static const _installation = 'installation_id';
  static const _name = 'field_name';
  static const _email = 'field_email';
  static const _phone = 'field_phone';
  static const _crew = 'field_crew';
  static const _crewId = 'field_crew_id';
  static const _role = 'field_role';
  static const _started = 'field_started_at';
  static const _persistent = 'field_persistent_session_id';
  static const _binding = 'field_device_binding_id';
  static const _pendingPrefix = 'pending_logout_';

  @override
  Future<String> installationId() async {
    final existing = await _storage.read(key: _installation);
    if (existing != null && existing.isNotEmpty) return existing;
    final created = const Uuid().v4();
    await _storage.write(key: _installation, value: created);
    return created;
  }

  @override
  Future<FieldSession?> read() async {
    final values = await _storage.readAll();
    final sessionId = values[_session];
    final access = values[_access];
    final refresh = values[_refresh];
    final installation = values[_installation];
    if ([
      sessionId,
      access,
      refresh,
      installation,
    ].any((v) => v == null || v.isEmpty)) {
      return null;
    }
    return FieldSession(
      sessionId: sessionId!,
      userId: values[_user] ?? '',
      accessToken: access!,
      refreshToken: refresh!,
      installationId: installation!,
      name: values[_name] ?? '',
      email: values[_email] ?? '',
      phone: values[_phone] ?? '',
      crew: values[_crew] ?? '',
      crewId: values[_crewId] ?? '',
      role: values[_role] ?? 'field',
      startedAt: DateTime.tryParse(values[_started] ?? ''),
      persistentSessionId: values[_persistent] ?? '',
      bindingId: values[_binding] ?? '',
    );
  }

  @override
  Future<void> save(FieldSession session) async {
    final values = {
      _access: session.accessToken,
      _refresh: session.refreshToken,
      _session: session.sessionId,
      _user: session.userId,
      _installation: session.installationId,
      _name: session.name,
      _email: session.email,
      _phone: session.phone,
      _crew: session.crew,
      _crewId: session.crewId,
      _role: session.role,
      _started: (session.startedAt ?? DateTime.now().toUtc()).toIso8601String(),
      _persistent: session.persistentSessionId,
      _binding: session.bindingId,
    };
    await Future.wait(
      values.entries.map(
        (entry) => _storage.write(key: entry.key, value: entry.value),
      ),
    );
  }

  @override
  Future<void> clear() async {
    for (final key in [
      _access,
      _refresh,
      _session,
      _user,
      _name,
      _email,
      _phone,
      _crew,
      _crewId,
      _role,
      _started,
      _persistent,
      _binding,
    ]) {
      await _storage.delete(key: key);
    }
  }

  @override
  Future<void> savePendingLogout(FieldSession session) async {
    await _storage.write(
      key: '${_pendingPrefix}refresh',
      value: session.refreshToken,
    );
    await _storage.write(
      key: '${_pendingPrefix}session',
      value: session.sessionId,
    );
    await _storage.write(
      key: '${_pendingPrefix}installation',
      value: session.installationId,
    );
  }

  @override
  Future<FieldSession?> readPendingLogout() async {
    final refresh = await _storage.read(key: '${_pendingPrefix}refresh');
    final session = await _storage.read(key: '${_pendingPrefix}session');
    final installation = await _storage.read(
      key: '${_pendingPrefix}installation',
    );
    if (refresh == null || session == null || installation == null) return null;
    return FieldSession(
      sessionId: session,
      userId: '',
      accessToken: '',
      refreshToken: refresh,
      installationId: installation,
    );
  }

  @override
  Future<void> clearPendingLogout() async {
    await _storage.delete(key: '${_pendingPrefix}refresh');
    await _storage.delete(key: '${_pendingPrefix}session');
    await _storage.delete(key: '${_pendingPrefix}installation');
  }
}
