import 'dart:typed_data';

import 'package:ddr001diag/features/auth/data/field_session_models.dart';
import 'package:ddr001diag/features/auth/data/session_secure_storage.dart';
import 'package:dio/dio.dart';
import 'package:uuid/uuid.dart';

class MemorySessionStorage implements SessionStorage, PendingLogoutStorage {
  FieldSession? value;
  FieldSession? pendingLogout;
  String? installation;
  int saveCount = 0;
  int clearCalls = 0;

  @override
  Future<void> clear() async {
    clearCalls++;
    value = null;
  }

  @override
  Future<String> installationId() async => installation ??= const Uuid().v4();

  @override
  Future<FieldSession?> read() async => value;

  @override
  Future<void> save(FieldSession session) async {
    value = session;
    installation = session.installationId;
    saveCount++;
  }

  @override
  Future<void> clearPendingLogout() async => pendingLogout = null;

  @override
  Future<FieldSession?> readPendingLogout() async => pendingLogout;

  @override
  Future<void> savePendingLogout(FieldSession session) async {
    pendingLogout = session;
  }
}

typedef AdapterHandler = Future<ResponseBody> Function(RequestOptions options);

class FakeHttpAdapter implements HttpClientAdapter {
  FakeHttpAdapter(this.handler);
  final AdapterHandler handler;
  final List<RequestOptions> requests = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    return handler(options);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody jsonResponse(
  String body,
  int status, {
  Map<String, List<String>> headers = const {},
}) => ResponseBody.fromString(
  body,
  status,
  headers: {
    Headers.contentTypeHeader: ['application/json'],
    ...headers,
  },
);
