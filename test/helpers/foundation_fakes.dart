import 'dart:typed_data';

import 'package:ddr001diag/features/auth/data/field_session_models.dart';
import 'package:ddr001diag/features/auth/data/session_secure_storage.dart';
import 'package:dio/dio.dart';
import 'package:uuid/uuid.dart';

class MemorySessionStorage implements SessionStorage {
  FieldSession? value;
  String? installation;
  int saveCount = 0;

  @override
  Future<void> clear() async => value = null;

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
