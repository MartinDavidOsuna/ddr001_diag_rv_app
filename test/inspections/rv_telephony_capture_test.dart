import 'package:ddr001diag/features/inspections/domain/rv_draft.dart';
import 'package:ddr001diag/features/inspections/presentation/rv_steps_one_two.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> nativeSample({
  String? carrier = 'Operador de prueba',
  String? technology = 'LTE',
  String raw = 'LTE',
  String override = 'NONE',
  int? level = 3,
  int? dbm = -104,
  int? asu = 36,
  String? reason,
  String transport = 'mobile',
  int slot = 0,
  int subscriptions = 1,
}) => {
  'carrierName': carrier,
  'networkTechnology': technology,
  'networkTypeRaw': raw,
  'overrideNetworkTypeRaw': override,
  'signalLevel': level,
  'signalPercent': level == null ? null : level * 25,
  'signalDbm': dbm,
  'signalAsu': asu,
  'signalSource': 'CellSignalStrengthLte',
  'transportType': transport,
  'subscriptionSlot': slot,
  'subscriptionCount': subscriptions,
  'isDefaultDataSubscription': true,
  'isRoaming': false,
  'availabilityReason': reason,
  'capturedAt': '2026-07-24T22:00:00.000Z',
};

RvSignalSample decode(Map<String, dynamic> value) => RvSignalSample.fromNative(
  value,
  fallbackTransport: 'none',
  connected: true,
);

void main() {
  group('mapeo de telefonía Android', () {
    test('LTE conserva valores nativos', () {
      final sample = decode(nativeSample());
      expect(sample.generation, '4G');
      expect(sample.networkTechnology, 'LTE');
      expect(sample.networkTypeRaw, 'LTE');
      expect(sample.level, 3);
      expect(sample.signalPercent, 75);
      expect(sample.dbm, -104);
      expect(sample.asu, 36);
    });

    for (final entry in const {
      '5G SA': '5G',
      '5G NSA': '5G',
      '3G': '3G',
      '2G': '2G',
    }.entries) {
      test('${entry.key} se clasifica como ${entry.value}', () {
        final sample = decode(
          nativeSample(
            technology: entry.key,
            raw: entry.key == '5G SA' ? 'NR' : entry.key,
            override: entry.key == '5G NSA' ? 'NR_NSA' : 'NONE',
          ),
        );
        expect(sample.generation, entry.value);
        expect(sample.networkTechnology, entry.key);
      });
    }

    test('operador vacío no se inventa', () {
      expect(decode(nativeSample(carrier: null)).operatorName, isNull);
    });

    test('doble SIM conserva slot y cantidad de suscripciones', () {
      final sample = decode(nativeSample(slot: 1, subscriptions: 2));
      expect(sample.subscriptionSlot, 1);
      expect(sample.subscriptionCount, 2);
      expect(sample.isDefaultDataSubscription, isTrue);
    });

    test('Wi-Fi conserva por separado la red móvil registrada', () {
      final sample = decode(nativeSample(transport: 'wifi'));
      expect(transportTypeLabel(sample.transportType), 'Wi-Fi');
      expect(networkTechnologyLabel(sample), 'LTE');
      expect(sample.operatorName, 'Operador de prueba');
    });

    for (final entry in const {
      'permission_denied':
          'No se autorizó el acceso a la información de red móvil.',
      'no_sim': 'No hay una SIM activa.',
      'no_service': 'La red móvil está sin servicio.',
      'timeout': 'La red móvil no respondió dentro del tiempo esperado.',
      'not_reported': 'Android no proporcionó el nivel de señal.',
    }.entries) {
      test('${entry.key} tiene explicación específica', () {
        final sample = decode(
          nativeSample(
            reason: entry.key,
            technology: null,
            carrier: null,
            level: null,
            dbm: null,
            asu: null,
          ),
        );
        expect(signalAvailabilityMessage(sample), entry.value);
      });
    }

    test('normaliza niveles Android de 0 a 4', () {
      for (var level = 0; level <= 4; level++) {
        expect(
          normalizedSignalPercent(decode(nativeSample(level: level))),
          level * 25,
        );
      }
    });

    test('nivel cero sin servicio no afirma cero por ciento', () {
      final sample = RvSignalSample(
        generation: 'NONE',
        connected: false,
        capturedAt: DateTime.utc(2026),
        level: 0,
        availabilityReason: 'no_service',
      );
      expect(normalizedSignalPercent(sample), isNull);
    });

    test('señal no reportada permanece nula', () {
      expect(
        normalizedSignalPercent(
          decode(nativeSample(level: null, dbm: null, asu: null)),
        ),
        isNull,
      );
    });
  });

  test('persistencia y reapertura conserva diagnóstico técnico', () {
    final original = decode(
      nativeSample(
        technology: '5G NSA',
        override: 'NR_NSA',
        slot: 1,
        subscriptions: 2,
      ),
    );
    final restored = RvSignalSample.fromJson(original.toJson());
    expect(restored.networkTechnology, '5G NSA');
    expect(restored.overrideNetworkTypeRaw, 'NR_NSA');
    expect(restored.signalSource, 'CellSignalStrengthLte');
    expect(restored.subscriptionSlot, 1);
    expect(restored.dbm, -104);
  });

  test('compatibilidad con borradores anteriores', () {
    final restored = RvSignalSample.fromJson({
      'generation': 'UNKNOWN',
      'connected': true,
      'capturedAt': '2026-01-01T00:00:00.000Z',
      'networkType': 'mobile',
    });
    expect(restored.networkTechnology, isNull);
    expect(restored.availabilityReason, isNull);
    expect(restored.networkType, 'mobile');
  });
}
