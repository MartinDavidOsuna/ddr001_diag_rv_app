import 'package:ddr001diag/core/network/api_exception.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('429 conserva Retry-After y contexto HTTP', () {
    final options = RequestOptions(
      path: '/inspections/id/photos',
      method: 'POST',
    );
    final exception = ApiException.fromDio(
      DioException(
        requestOptions: options,
        type: DioExceptionType.badResponse,
        response: Response<dynamic>(
          requestOptions: options,
          statusCode: 429,
          data: {'requestId': 'req-429'},
          headers: Headers.fromMap({
            'retry-after': ['120'],
          }),
        ),
      ),
    );

    expect(exception.kind, ApiErrorKind.rateLimited);
    expect(exception.retryAfter, const Duration(seconds: 120));
    expect(exception.requestId, 'req-429');
    expect(exception.httpMethod, 'POST');
    expect(exception.logicalEndpoint, '/inspections/id/photos');
  });

  for (final entry in const {
    'HYDRANT_NOT_FOUND': 'hidrante',
    'INSPECTION_NOT_FOUND': 'revisión',
    'PHOTO_NOT_FOUND': 'fotografía',
  }.entries) {
    test('404 ${entry.key} conserva semántica y contexto', () {
      final options = RequestOptions(path: '/resource', method: 'GET');
      final exception = ApiException.fromDio(
        DioException(
          requestOptions: options,
          type: DioExceptionType.badResponse,
          response: Response<dynamic>(
            requestOptions: options,
            statusCode: 404,
            data: {
              'code': entry.key,
              'detail': 'server detail',
              'requestId': 'req-404',
            },
          ),
        ),
      );

      expect(exception.kind, ApiErrorKind.invalidData);
      expect(exception.domainCode, entry.key);
      expect(exception.message.toLowerCase(), contains(entry.value));
      expect(exception.requestId, 'req-404');
      expect(exception.logicalEndpoint, '/resource');
      expect(exception.originalMessage, 'server detail');
    });
  }
}
