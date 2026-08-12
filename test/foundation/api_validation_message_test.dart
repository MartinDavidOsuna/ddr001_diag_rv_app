import 'package:ddr001diag/core/network/api_exception.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

ApiException translate(Map<String, dynamic> data) {
  final request = RequestOptions(path: '/inspections/id/parcel-valves');
  return ApiException.fromDio(
    DioException(
      requestOptions: request,
      response: Response(requestOptions: request, statusCode: 422, data: data),
    ),
  );
}

void main() {
  test('traduce el campo de una válvula sin mostrar el error inglés', () {
    final error = translate({
      'title': 'Validation error',
      'detail': 'One or more fields are invalid.',
      'errors': [
        {
          'code': 'custom',
          'path': ['valves', 3, 'pilotBrandId'],
          'message': 'Invalid input',
        },
      ],
    });

    expect(error.message, contains('marca del piloto de la válvula 4'));
    expect(error.message, isNot(contains('Invalid')));
  });

  test('traduce el rechazo de catálogo de válvulas', () {
    final error = translate({
      'title': 'Invalid parcel valve catalogs',
      'detail': 'Valve 2 contains a catalog from another element type.',
    });

    expect(error.message, contains('válvula 2'));
    expect(error.message, contains('no coincide con su catálogo'));
    expect(error.message, isNot(contains('catalog from another')));
  });

  test('traduce un slot fotográfico rechazado por contrato', () {
    final error = translate({
      'title': 'Validation error',
      'errors': [
        {
          'code': 'invalid_string',
          'path': ['slotCode'],
          'message': 'Invalid',
        },
      ],
    });

    expect(error.message, contains('tipo de fotografía'));
    expect(error.message, isNot(contains('slotCode')));
  });
}
