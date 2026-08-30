import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:ddr001diag/core/config/app_config.dart';
import 'package:ddr001diag/core/network/api_client.dart';
import 'package:ddr001diag/core/network/api_exception.dart';
import 'package:ddr001diag/domain/media/inspection_photo.dart';
import 'package:ddr001diag/domain/media/photo_integrity_status.dart';
import 'package:ddr001diag/features/inspections/data/inspection_remote_repository.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/foundation_fakes.dart';

void main() {
  late Directory temporaryDirectory;

  setUp(() async {
    temporaryDirectory = await Directory.systemTemp.createTemp('photo-upload-');
  });

  tearDown(() async {
    await temporaryDirectory.delete(recursive: true);
  });

  test('materializa y termina el multipart de una foto íntegra', () async {
    final bytes = List<int>.generate(1024 * 1024, (index) => index % 251);
    final file = File('${temporaryDirectory.path}/photo.jpg');
    await file.writeAsBytes(bytes, flush: true);
    var uploadedBytes = 0;
    final adapter = FakeHttpAdapter((options) async {
      expect(options.sendTimeout, const Duration(minutes: 2));
      expect(options.receiveTimeout, const Duration(minutes: 2));
      return jsonResponse(
        '{"photoId":"photo-1","slotCode":"top","status":"verified"}',
        200,
      );
    });
    final dio = Dio()
      ..httpClientAdapter = _ReadingAdapter(adapter, (count) {
        uploadedBytes += count;
      });

    final result = await _repository(
      dio,
    ).uploadPhoto('inspection-1', 'top', _photo(file, bytes));

    expect(result.status, 'verified');
    expect(uploadedBytes, greaterThan(bytes.length));
  });

  test('rechaza una foto alterada sin iniciar la solicitud', () async {
    final bytes = <int>[1, 2, 3, 4];
    final file = File('${temporaryDirectory.path}/photo.jpg');
    await file.writeAsBytes(bytes);
    final adapter = FakeHttpAdapter((_) async => jsonResponse('{}', 500));

    await expectLater(
      _repository(Dio()..httpClientAdapter = adapter).uploadPhoto(
        'inspection-1',
        'top',
        _photo(file, bytes, sha: 'not-the-real-hash'),
      ),
      throwsA(
        isA<ApiException>().having(
          (error) => error.kind,
          'kind',
          ApiErrorKind.invalidData,
        ),
      ),
    );
    expect(adapter.requests, isEmpty);
  });

  test(
    'verify-batch interpreta confirmación y reparación server-side',
    () async {
      final adapter = FakeHttpAdapter((options) async {
        expect(options.path, endsWith('/photos/verify-batch'));
        return jsonResponse(
          '{"items":['
          '{"photoId":"a","status":"confirmed","originalPresent":true,'
          '"thumbnailPresent":true,"storageVerified":true,"mapped":true,'
          '"mappingStatus":"mapped","retryable":false,"repairable":false},'
          '{"photoId":"b","status":"mapping_conflict","originalPresent":true,'
          '"thumbnailPresent":true,"storageVerified":true,"mapped":false,'
          '"mappingStatus":"conflict","retryable":false,"repairable":false}'
          ']}',
          200,
        );
      });

      final result = await _repository(
        Dio()..httpClientAdapter = adapter,
      ).verifyPhotosBatch(['a', 'b']);

      expect(result.first.status, PhotoIntegrityStatus.confirmed);
      expect(result.first.mappingStatus, PhotoMappingStatus.mapped);
      expect(result.last.status, PhotoIntegrityStatus.mappingConflict);
      expect(result.last.retryable, isFalse);
    },
  );

  test('verify-batch limita cada lote a cien identificadores', () async {
    final repository = _repository(Dio());
    await expectLater(
      repository.verifyPhotosBatch(List.generate(101, (index) => '$index')),
      throwsA(isA<ApiException>()),
    );
  });

  test('verify-batch legacy 404 conserva señal de capability', () async {
    final adapter = FakeHttpAdapter(
      (_) async => jsonResponse(
        '{"title":"Not found","detail":"route unavailable"}',
        404,
      ),
    );
    await expectLater(
      _repository(
        Dio()..httpClientAdapter = adapter,
      ).verifyPhotosBatch(['photo-1']),
      throwsA(
        isA<ApiException>().having(
          (error) => error.statusCode,
          'statusCode',
          404,
        ),
      ),
    );
  });
}

InspectionRemoteRepository _repository(Dio dio) => InspectionRemoteRepository(
  ApiClient(
    config: AppConfig.fromEnvironment(
      environmentOverride: 'development',
      apiBaseUrlOverride: 'https://example.test/api/v1',
    ),
    sessionStorage: MemorySessionStorage(),
    dio: dio,
  ),
);

InspectionPhoto _photo(File file, List<int> bytes, {String? sha}) {
  final now = DateTime.utc(2026, 8, 23);
  return InspectionPhoto(
    id: 'photo-1',
    hydrantId: 'hydrant-1',
    inspectionId: 'inspection-1',
    category: 'general',
    source: PhotoSource.camera,
    originalFilename: 'photo.jpg',
    normalizedFilename: 'photo.jpg',
    localPath: file.path,
    thumbnailPath: file.path,
    mimeType: 'image/jpeg',
    fileSize: bytes.length,
    width: 100,
    height: 100,
    sha256: sha ?? sha256.convert(bytes).toString(),
    capturedAt: now,
    capturedByUserId: 'user-1',
    capturedByName: 'User',
    brigadeId: 'brigade-1',
    deviceId: 'device-1',
    createdAt: now,
    updatedAt: now,
  );
}

class _ReadingAdapter implements HttpClientAdapter {
  _ReadingAdapter(this.delegate, this.onBytes);

  final HttpClientAdapter delegate;
  final void Function(int count) onBytes;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    if (requestStream != null) {
      await for (final chunk in requestStream) {
        onBytes(chunk.length);
      }
    }
    return delegate.fetch(options, null, cancelFuture);
  }

  @override
  void close({bool force = false}) => delegate.close(force: force);
}
