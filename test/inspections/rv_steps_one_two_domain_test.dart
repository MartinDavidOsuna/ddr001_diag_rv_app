import 'package:ddr001diag/features/inspections/domain/rv_draft.dart';
import 'package:ddr001diag/features/inspections/domain/rv_sync_state.dart';
import 'package:ddr001diag/features/inspections/presentation/rv_steps_one_two.dart';
import 'package:ddr001diag/features/checklist/data/checklist_models.dart';
import 'package:ddr001diag/features/checklist/presentation/dynamic_checklist_renderer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  ChecklistItemDefinition item({
    required String code,
    String type = 'text',
    bool required = false,
  }) => ChecklistItemDefinition(
    id: code,
    code: code,
    label: code,
    type: type,
    required: required,
    order: 1,
  );

  group('paso 2 sin controles duplicados', () {
    test('comentarios generales no ofrece No aplica', () {
      expect(
        showNotApplicableForChecklistItem(item(code: 'cabinet_comments')),
        isFalse,
      );
      expect(
        showNotApplicableForChecklistItem(item(code: 'optional_note')),
        isTrue,
      );
    });

    test('oculta la primera captura fotográfica y conserva preguntas', () {
      expect(
        renderChecklistItemInSection(
          item(code: 'cabinet_front', type: 'photo'),
          hidePhotoQuestions: true,
        ),
        isFalse,
      );
      expect(
        renderChecklistItemInSection(
          item(code: 'locks_open', type: 'boolean', required: true),
          hidePhotoQuestions: true,
        ),
        isTrue,
      );
    });
  });

  RvSignalSample signal({
    bool connected = true,
    String generation = 'UNKNOWN',
    String? networkType,
    String? operatorName,
    int? level,
  }) => RvSignalSample(
    generation: generation,
    connected: connected,
    capturedAt: DateTime.utc(2026, 7, 24),
    networkType: networkType,
    operatorName: operatorName,
    level: level,
  );

  group('captura manual validada', () {
    test('acepta latitud decimal válida', () {
      expect(manualCoordinateError('29.123456', isLatitude: true), isNull);
    });
    test('acepta coma decimal', () {
      expect(manualCoordinateError('-110,9', isLatitude: false), isNull);
    });
    test('rechaza latitud vacía', () {
      expect(manualCoordinateError('', isLatitude: true), isNotNull);
    });
    test('rechaza longitud vacía', () {
      expect(manualCoordinateError(' ', isLatitude: false), isNotNull);
    });
    test('rechaza texto', () {
      expect(manualCoordinateError('norte', isLatitude: true), isNotNull);
    });
    test('rechaza latitud menor que -90', () {
      expect(manualCoordinateError('-90.1', isLatitude: true), contains('-90'));
    });
    test('rechaza latitud mayor que 90', () {
      expect(manualCoordinateError('90.1', isLatitude: true), contains('90'));
    });
    test('rechaza longitud menor que -180', () {
      expect(
        manualCoordinateError('-180.1', isLatitude: false),
        contains('-180'),
      );
    });
    test('rechaza longitud mayor que 180', () {
      expect(
        manualCoordinateError('180.1', isLatitude: false),
        contains('180'),
      );
    });
  });

  group('conectividad accesible y honesta', () {
    test('reconoce Wi-Fi sin inventar operador', () {
      final value = signal(networkType: 'wifi');
      expect(networkTechnologyLabel(value), 'Wi-Fi');
      expect(value.operatorName, isNull);
    });
    test('reconoce LTE', () {
      expect(networkTechnologyLabel(signal(networkType: 'LTE')), 'LTE');
    });
    test('reconoce 5G', () {
      expect(networkTechnologyLabel(signal(generation: '5G')), '5G');
    });
    test('muestra sin servicio', () {
      expect(networkTechnologyLabel(signal(connected: false)), 'Sin servicio');
    });
    test('conserva operador abierto', () {
      expect(
        signal(operatorName: 'Operador de prueba').operatorName,
        isNotNull,
      );
    });
    test('normaliza límite inferior', () {
      expect(normalizedSignalPercent(signal(level: 0)), 0);
      expect(signalQualityLabel(0), 'Muy baja');
    });
    test('normaliza límite superior', () {
      expect(normalizedSignalPercent(signal(level: 4)), 100);
      expect(signalQualityLabel(100), 'Excelente');
    });
    test('no inventa señal ausente', () {
      expect(normalizedSignalPercent(signal()), isNull);
      expect(signalQualityLabel(null), 'No disponible');
    });
    test('clasifica señal media y buena con texto', () {
      expect(signalQualityLabel(50), 'Media');
      expect(signalQualityLabel(75), 'Buena');
    });
  });

  group('múltiples fotografías y compatibilidad', () {
    RvPhotoReference photo(String id, String slot) => RvPhotoReference(
      photoId: id,
      slotCode: slot,
      status: RvPhotoUploadStatus.pending,
    );

    test('contador usa singular', () {
      expect(rvPhotoCountLabel(1), '1 foto capturada');
    });
    test('contador usa plural incluso en cero', () {
      expect(rvPhotoCountLabel(0), '0 fotos capturadas');
      expect(rvPhotoCountLabel(3), '3 fotos capturadas');
    });
    test('lee borrador heredado con objeto único por slot', () {
      final restored = RvDraft.fromJson({
        'clientInspectionId': 'c',
        'hydrantId': 'h',
        'accountNumber': '1',
        'fieldSessionId': 's',
        'checklistId': 'rv',
        'checklistVersion': 2,
        'checklistSnapshot': {
          'id': 'rv',
          'code': 'RV',
          'version': 2,
          'title': 'RV',
          'etag': 'e',
          'cachedAt': DateTime.utc(2026).toIso8601String(),
          'sections': <Object>[],
        },
        'createdAt': DateTime.utc(2026).toIso8601String(),
        'updatedAt': DateTime.utc(2026).toIso8601String(),
        'photos': {'front_closed': photo('old', 'front_closed').toJson()},
      });
      expect(restored.photosFor('front_closed').single.photoId, 'old');
    });
    test('serializa y reabre varias fotos manteniendo orden', () {
      final base = RvDraft.fromJson({
        'clientInspectionId': 'c',
        'hydrantId': 'h',
        'accountNumber': '1',
        'fieldSessionId': 's',
        'checklistId': 'rv',
        'checklistVersion': 2,
        'checklistSnapshot': {
          'id': 'rv',
          'code': 'RV',
          'version': 2,
          'title': 'RV',
          'etag': 'e',
          'cachedAt': DateTime.utc(2026).toIso8601String(),
          'sections': <Object>[],
        },
        'createdAt': DateTime.utc(2026).toIso8601String(),
        'updatedAt': DateTime.utc(2026).toIso8601String(),
      });
      final value = base.copyWith(
        photos: {
          'front_closed': [
            photo('first', 'front_closed'),
            photo('second', 'front_closed'),
          ],
        },
      );
      expect(
        RvDraft.fromJson(
          value.toJson(),
        ).photosFor('front_closed').map((item) => item.photoId),
        ['first', 'second'],
      );
      expect(value.photoCount, 2);
    });
  });
}
