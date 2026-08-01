import 'package:ddr001diag/features/checklist/data/checklist_models.dart';
import 'package:ddr001diag/features/inspections/domain/rv_draft.dart';
import 'package:ddr001diag/features/inspections/domain/rv_sync_state.dart';
import 'package:ddr001diag/features/inspections/domain/rv_validator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime.utc(2026, 7, 22);
  DynamicChecklist checklist() => DynamicChecklist(
    id: 'checklist-1',
    code: 'RV',
    version: 3,
    title: 'Revisión visual',
    etag: 'etag-3',
    cachedAt: now,
    sections: const [
      ChecklistSectionDefinition(
        id: 'section-1',
        code: 'GENERAL',
        title: 'General',
        order: 1,
        items: [
          ChecklistItemDefinition(
            id: 'q1',
            code: 'VISIBLE',
            label: 'Visible',
            type: 'boolean',
            required: true,
            order: 1,
          ),
          ChecklistItemDefinition(
            id: 'q2',
            code: 'DETAIL',
            label: 'Detalle',
            type: 'text',
            required: true,
            order: 2,
            dependency: ChecklistDependency(
              parentCode: 'VISIBLE',
              operator: 'eq',
              value: true,
            ),
          ),
          ChecklistItemDefinition(
            id: 'q3',
            code: 'STATE',
            label: 'Estado',
            type: 'select',
            required: true,
            order: 3,
            options: ['BUENO', 'MALO'],
          ),
        ],
      ),
    ],
  );

  RvDraft draft({
    Map<String, RvAnswer> answers = const {},
    Map<String, List<RvPhotoReference>> photos = const {},
  }) {
    final definition = checklist();
    return RvDraft(
      clientInspectionId: 'client-1',
      hydrantId: 'hydrant-1',
      accountNumber: '1001',
      fieldSessionId: 'session-1',
      checklistId: definition.id,
      checklistVersion: definition.version,
      checklistSnapshot: definition.toJson(),
      createdAt: now,
      updatedAt: now,
      answers: answers,
      photos: photos,
    );
  }

  RvAnswer answer(String id, Object? value, {String type = 'text'}) => RvAnswer(
    questionId: id,
    sectionId: 'section-1',
    answerType: type,
    value: value,
    updatedAt: now,
  );

  group('borrador RV persistente', () {
    test('conflicto es terminal y conserva referencias al serializar', () {
      final conflicted = draft().copyWith(
        localStatus: RvLocalStatus.conflict,
        remoteStatus: 'conflict',
        officialInspectionId: 'official-id',
        conflictId: 'conflict-id',
        lastStatusChangedAt: DateTime.utc(2026, 8, 1),
      );
      final restored = RvDraft.fromJson(conflicted.toJson());
      expect(restored.isReadOnly, isTrue);
      expect(restored.officialInspectionId, 'official-id');
      expect(restored.conflictId, 'conflict-id');
      expect(restored.photos.keys, conflicted.photos.keys);
      expect(restored.answers.keys, conflicted.answers.keys);
    });
    test('conserva clientInspectionId en serialización', () {
      expect(RvDraft.fromJson(draft().toJson()).clientInspectionId, 'client-1');
    });
    test('migra borrador legacy con defaults seguros de versión', () {
      final json = draft().toJson()
        ..remove('editingMode')
        ..remove('hasPendingChanges')
        ..remove('serverValidationStatus');
      final restored = RvDraft.fromJson(json);
      expect(restored.editingMode, RvEditingMode.capture);
      expect(restored.hasPendingChanges, isFalse);
      expect(restored.canEditTechnical, isTrue);
    });
    test('persiste base y conflicto de edición sin perder evidencia', () {
      final value = draft(answers: {'q1': answer('q1', true, type: 'boolean')})
          .copyWith(
            visualReportId: 'report-1',
            currentVersionId: 'version-2',
            baseVersionId: 'version-1',
            baseVersionNumber: 1,
            pendingVersionClientId: 'client-version-1',
            hasPendingChanges: true,
            localStatus: RvLocalStatus.versionConflict,
            versionConflictId: 'conflict-1',
            proposedVersionId: 'version-3',
          );
      final restored = RvDraft.fromJson(value.toJson());
      expect(restored.baseVersionId, 'version-1');
      expect(restored.versionConflictId, 'conflict-1');
      expect(restored.answers['q1']?.value, true);
      expect(restored.hasPendingChanges, isTrue);
      expect(restored.isReadOnly, isTrue);
    });
    test('validación bloquea técnica y permite complementos', () {
      final validated = draft().copyWith(
        editingMode: RvEditingMode.validatedComplements,
        serverValidationStatus: 'validated',
      );
      expect(validated.canEditTechnical, isFalse);
      expect(validated.canAddComplements, isTrue);
    });
    test('conserva snapshot y versión de checklist', () {
      final restored = RvDraft.fromJson(draft().toJson());
      expect(restored.checklistVersion, 3);
      expect(restored.checklist.sections.single.items, hasLength(3));
    });
    test('migra el paso general legacy con defaults opcionales seguros', () {
      final json = draft().toJson()..remove('generalObservations');
      final restored = RvDraft.fromJson(json);
      expect(restored.generalObservations, isNull);
      expect(restored.generalPhotos, isEmpty);
    });
    test(
      'persiste orden, descripción y observaciones de fotografías generales',
      () {
        final value = draft(
          photos: {
            'general:00000000-0000-4000-8000-000000000001': const [
              RvPhotoReference(
                photoId: '00000000-0000-4000-8000-000000000001',
                slotCode: 'general:00000000-0000-4000-8000-000000000001',
                status: RvPhotoUploadStatus.pending,
                order: 1,
                description: 'Vista lateral',
              ),
            ],
          },
        ).copyWith(generalObservations: 'Corrosión superficial.');
        final restored = RvDraft.fromJson(value.toJson());
        expect(restored.generalPhotos, hasLength(1));
        expect(restored.generalPhotos.single.order, 1);
        expect(restored.generalPhotos.single.description, 'Vista lateral');
        expect(restored.generalObservations, 'Corrosión superficial.');
      },
    );
    test('conserva respuesta y fecha', () {
      final restored = RvDraft.fromJson(
        draft(answers: {'q1': answer('q1', true, type: 'boolean')}).toJson(),
      );
      expect(restored.answers['q1']!.value, true);
      expect(restored.answers['q1']!.updatedAt, now);
    });
    test('conserva muestra GPS', () {
      final value = draft().copyWith(
        location: RvLocationSample(
          latitude: 29.1,
          longitude: -110.9,
          source: 'gps',
          capturedAt: now,
        ),
      );
      expect(RvDraft.fromJson(value.toJson()).location!.latitude, 29.1);
    });
    test('conserva muestra de señal sin inventar intensidad', () {
      final value = draft().copyWith(
        signal: RvSignalSample(
          generation: 'UNKNOWN',
          connected: true,
          networkType: 'wifi',
          capturedAt: now,
        ),
      );
      expect(RvDraft.fromJson(value.toJson()).signal!.dbm, isNull);
    });
    test('bloquea edición al enviar o cancelar', () {
      expect(
        draft().copyWith(localStatus: RvLocalStatus.submitted).isReadOnly,
        isTrue,
      );
      expect(
        draft().copyWith(localStatus: RvLocalStatus.cancelled).isReadOnly,
        isTrue,
      );
    });
    test('401 conserva reporte y evidencia como requiere autenticación', () {
      final local =
          draft(
            answers: {'q1': answer('q1', true, type: 'boolean')},
            photos: {
              'overview': [
                RvPhotoReference(
                  photoId: 'photo-local-1',
                  slotCode: 'overview',
                  status: RvPhotoUploadStatus.pending,
                ),
              ],
            },
          ).copyWith(
            localStatus: RvLocalStatus.requiresAuthentication,
            lastSyncError:
                'El reporte está guardado de forma segura. Inicia sesión nuevamente para continuar el envío.',
          );

      final reopened = RvDraft.fromJson(local.toJson());
      expect(reopened.clientInspectionId, 'client-1');
      expect(reopened.localStatus, RvLocalStatus.requiresAuthentication);
      expect(reopened.answers['q1']?.value, true);
      expect(reopened.photosFor('overview').single.photoId, 'photo-local-1');
      expect(reopened.isReadOnly, isFalse);
    });
  });

  group('reglas y validación', () {
    const validator = RvValidator();
    test('detecta pregunta obligatoria visible', () {
      expect(
        validator.validate(draft()).issues.any((e) => e.questionId == 'q1'),
        isTrue,
      );
    });
    test('oculta dependencia cuando padre es falso', () {
      final value = draft(
        answers: {'q1': answer('q1', false, type: 'boolean')},
      );
      expect(
        validator.isVisible(
          checklist().sections.single.items[1],
          checklist(),
          value.answers,
        ),
        isFalse,
      );
    });
    test('muestra dependencia cuando padre coincide', () {
      final value = draft(answers: {'q1': answer('q1', true, type: 'boolean')});
      expect(
        validator.isVisible(
          checklist().sections.single.items[1],
          checklist(),
          value.answers,
        ),
        isTrue,
      );
    });
    test('rechaza opción ajena al contrato', () {
      final value = draft(
        answers: {
          'q1': answer('q1', false, type: 'boolean'),
          'q3': answer('q3', 'DESCONOCIDO', type: 'select'),
        },
      );
      expect(
        validator.validate(value).issues.any((e) => e.code == 'invalid_answer'),
        isTrue,
      );
    });
    test('requiere GPS y señal', () {
      final issues = validator.validate(draft()).issues;
      expect(issues.any((e) => e.code == 'location_missing'), isTrue);
      expect(issues.any((e) => e.code == 'signal_missing'), isTrue);
    });
    test('confirma los siete slots fijos', () {
      expect(requiredRvPhotoSlots, [
        'front_closed',
        'left_side',
        'right_side',
        'back',
        'top',
        'front_open',
        'serial_plate',
      ]);
    });
    test('detecta cada slot fotográfico faltante', () {
      final issues = validator
          .validate(draft())
          .issues
          .where((e) => e.code == 'required_photo_missing');
      expect(issues, hasLength(7));
    });
    test('acepta siete referencias verificadas', () {
      final photos = {
        for (final slot in requiredRvPhotoSlots)
          slot: [
            RvPhotoReference(
              photoId: 'photo-$slot',
              slotCode: slot,
              status: RvPhotoUploadStatus.verified,
            ),
          ],
      };
      expect(draft(photos: photos).photosVerified, isTrue);
    });
    test('validación sincronizada detecta respuestas pendientes', () {
      final value = draft(
        answers: {
          'q1': answer('q1', false, type: 'boolean'),
          'q3': answer('q3', 'BUENO', type: 'select'),
        },
      );
      expect(
        validator
            .validate(value, requireSynced: true)
            .issues
            .any((e) => e.code == 'answers_pending'),
        isTrue,
      );
    });
  });
}
