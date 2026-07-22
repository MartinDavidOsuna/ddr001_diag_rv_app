import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:uuid/uuid.dart';

import 'field_session_models.dart';

abstract interface class SessionStorage {
  Future<FieldSession?> read();
  Future<void> save(FieldSession session);
  Future<void> clear();
  Future<String> installationId();
}

class SessionSecureStorage implements SessionStorage {
  SessionSecureStorage([FlutterSecureStorage? storage])
    : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;
  static const _access = 'field_access_token';
  static const _refresh = 'field_refresh_token';
  static const _session = 'field_session_id';
  static const _installation = 'installation_id';
  static const _name = 'field_name';
  static const _email = 'field_email';
  static const _phone = 'field_phone';
  static const _crew = 'field_crew';
  static const _started = 'field_started_at';

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
      accessToken: access!,
      refreshToken: refresh!,
      installationId: installation!,
      name: values[_name] ?? '',
      email: values[_email] ?? '',
      phone: values[_phone] ?? '',
      crew: values[_crew] ?? '',
      startedAt: DateTime.tryParse(values[_started] ?? ''),
    );
  }

  @override
  Future<void> save(FieldSession session) async {
    final values = {
      _access: session.accessToken,
      _refresh: session.refreshToken,
      _session: session.sessionId,
      _installation: session.installationId,
      _name: session.name,
      _email: session.email,
      _phone: session.phone,
      _crew: session.crew,
      _started: (session.startedAt ?? DateTime.now().toUtc()).toIso8601String(),
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
      _name,
      _email,
      _phone,
      _crew,
      _started,
    ]) {
      await _storage.delete(key: key);
    }
  }
}
