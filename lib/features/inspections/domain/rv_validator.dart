import '../../checklist/data/checklist_models.dart';
import 'rv_draft.dart';
import 'rv_sync_state.dart';

enum PendingIssueSeverity { warning, blocking }

class RvPendingIssue {
  const RvPendingIssue({
    required this.code,
    required this.message,
    this.sectionId,
    this.questionId,
    this.subItemId,
    this.fieldId,
    this.slotCode,
    this.stepIndex,
    this.componentType,
    this.instanceId,
    this.instanceIndex,
    this.focusKey,
    this.severity = PendingIssueSeverity.blocking,
  });
  final String code, message;
  final String? sectionId, questionId, subItemId, fieldId, slotCode;
  final int? stepIndex, instanceIndex;
  final String? componentType, instanceId, focusKey;
  final PendingIssueSeverity severity;
}

typedef RvValidationIssue = RvPendingIssue;

class RvValidationResult {
  const RvValidationResult(this.issues);
  final List<RvValidationIssue> issues;
  bool get isValid => issues.isEmpty;
}

class RvValidator {
  const RvValidator();

  bool isVisible(
    ChecklistItemDefinition item,
    DynamicChecklist checklist,
    Map<String, RvAnswer> answers,
  ) {
    var current = item;
    while (current.dependency != null) {
      final dependency = current.dependency!;
      final parent = checklist.sections
          .expand((e) => e.items)
          .where((e) => e.code == dependency.parentCode)
          .firstOrNull;
      if (parent == null) return false;
      final answer = answers[parent.id];
      final actual = answer?.notApplicable == true
          ? null
          : (answer?.value ??
                (answer?.selectedOptions.isNotEmpty == true
                    ? answer!.selectedOptions
                    : null));
      if (!_compare(actual, dependency.operator, dependency.value))
        return false;
      current = parent;
    }
    return true;
  }

  RvValidationResult validate(RvDraft draft, {bool requireSynced = false}) {
    final issues = <RvValidationIssue>[];
    if (!draft.isInactive &&
        (draft.inactiveClosureDraft != null ||
            draft.photosFor(noHydrantAtLocationPhotoSlot).isNotEmpty)) {
      issues.add(
        const RvValidationIssue(
          code: 'inactive_evidence_requires_closure',
          message:
              'Existe evidencia de que no hay hidrante en la ubicación. '
              'Vuelve al paso 1 para continuar el reporte o descartarlo.',
          slotCode: noHydrantAtLocationPhotoSlot,
          stepIndex: 0,
          focusKey: 'photo:no_hydrant_at_location',
        ),
      );
    }
    final checklist = draft.checklist;
    for (final section in checklist.sections) {
      if (section.code == 'valvulas_parcelarias') {
        _validateParcelValves(draft, section, issues);
        continue;
      }
      for (final item in section.items) {
        if (!isVisible(item, checklist, draft.answers)) continue;
        if (item.type == 'photo') {
          final slot = item.photoSlot ?? item.code;
          final photos = draft.photosFor(slot);
          if (item.required && photos.isEmpty) {
            issues.add(
              RvValidationIssue(
                code: 'required_photo_missing',
                message: 'Falta ${item.label}.',
                sectionId: section.id,
                questionId: item.id,
                slotCode: slot,
                focusKey: 'photo:$slot',
              ),
            );
          } else if (item.required &&
              requireSynced &&
              !photos.any(
                (photo) => photo.status == RvPhotoUploadStatus.verified,
              )) {
            issues.add(
              RvValidationIssue(
                code: 'photo_pending',
                message: '${item.label} no está subida.',
                sectionId: section.id,
                questionId: item.id,
                slotCode: slot,
                focusKey: 'photo:$slot',
              ),
            );
          }
          continue;
        }
        if (const {'coordinates', 'signal', 'readonly'}.contains(item.type))
          continue;
        final answer = draft.answers[item.id];
        if (answer?.value case final Map value
            when item.code.contains('brand') &&
                value['mode'] == 'illegible' &&
                (value['reason']?.toString().trim().length ?? 0) < 10) {
          issues.add(
            RvValidationIssue(
              code: 'illegible_brand_reason_missing',
              message:
                  'Describe por qué la marca es ilegible (mínimo 10 caracteres).',
              sectionId: section.id,
              questionId: item.id,
              focusKey: 'question:${item.id}',
            ),
          );
          continue;
        }
        if (item.code == 'filter_element' &&
            answer != null &&
            !answer.notApplicable) {
          final value = answer.value;
          if (value is Map &&
              value['state'] == 'undefined' &&
              (value['reason']?.toString().trim().length ?? 0) < 10) {
            issues.add(
              RvValidationIssue(
                code: 'filter_element_reason_missing',
                message:
                    'Explica por qué no puede determinarse si existe elemento filtrante.',
                sectionId: section.id,
                questionId: item.id,
              ),
            );
            continue;
          }
          if (value is Map &&
              const {'present', 'absent', 'undefined'}.contains(value['state']))
            continue;
        }
        if (item.required &&
            (answer == null ||
                (!answer.notApplicable && _empty(item, answer)))) {
          issues.add(
            RvValidationIssue(
              code: item.code.endsWith('_pilot_connected')
                  ? 'pilot_connection_missing'
                  : 'required_answer_missing',
              message: item.code.endsWith('_pilot_connected')
                  ? 'Falta indicar si el piloto está conectado.'
                  : 'Falta responder ${item.label}.',
              sectionId: section.id,
              questionId: item.id,
            ),
          );
          continue;
        }
        if (answer != null && !answer.notApplicable) {
          final valid = _validType(item, answer);
          if (!valid)
            issues.add(
              RvValidationIssue(
                code: 'invalid_answer',
                message: 'La respuesta de ${item.label} no es válida.',
                sectionId: section.id,
                questionId: item.id,
              ),
            );
        }
      }
    }
    if (draft.location == null)
      issues.add(
        const RvValidationIssue(
          code: 'location_missing',
          message: 'Falta capturar la ubicación.',
          stepIndex: 1,
          focusKey: 'location',
        ),
      );
    if (draft.signal == null)
      issues.add(
        const RvValidationIssue(
          code: 'signal_missing',
          message: 'Falta capturar la conectividad.',
          stepIndex: 1,
          focusKey: 'signal',
        ),
      );
    for (final slot in requiredRvPhotoSlots) {
      final photos = draft.photosFor(slot);
      if (photos.isEmpty) {
        issues.add(
          RvValidationIssue(
            code: 'required_photo_missing',
            message: 'Falta ${rvPhotoSlotLabels[slot]}.',
            slotCode: slot,
            stepIndex: 1,
            focusKey: 'photo:$slot',
          ),
        );
      } else if (requireSynced &&
          !photos.any(
            (photo) => photo.status == RvPhotoUploadStatus.verified,
          )) {
        issues.add(
          RvValidationIssue(
            code: 'photo_pending',
            message: '${rvPhotoSlotLabels[slot]} no está subida.',
            slotCode: slot,
            stepIndex: 1,
            focusKey: 'photo:$slot',
          ),
        );
      }
    }
    if (requireSynced) {
      if (draft.serverInspectionId == null)
        issues.add(
          const RvValidationIssue(
            code: 'inspection_not_created',
            message: 'La inspección no se ha creado en el servidor.',
          ),
        );
      if (draft.answersStatus != RvPartStatus.synced)
        issues.add(
          const RvValidationIssue(
            code: 'answers_pending',
            message: 'Hay respuestas pendientes de sincronización.',
          ),
        );
      if (draft.locationStatus != RvPartStatus.synced)
        issues.add(
          const RvValidationIssue(
            code: 'location_pending',
            message: 'La ubicación está pendiente de sincronización.',
          ),
        );
      if (draft.signalStatus != RvPartStatus.synced)
        issues.add(
          const RvValidationIssue(
            code: 'signal_pending',
            message: 'La conectividad está pendiente de sincronización.',
          ),
        );
    }
    return RvValidationResult(issues);
  }

  void _validateParcelValves(
    RvDraft draft,
    ChecklistSectionDefinition section,
    List<RvValidationIssue> issues,
  ) {
    final configuration = draft.parcelValveConfiguration;
    if (configuration == null) {
      issues.add(
        RvValidationIssue(
          code: 'parcel_configuration_missing',
          message: 'Falta seleccionar la configuración de válvulas.',
          sectionId: section.id,
          fieldId: 'configuration',
          componentType: 'parcel_valves',
          focusKey: 'parcel:configuration',
        ),
      );
      return;
    }
    if (configuration.valveCount < 1 ||
        configuration.valveCount > 5 ||
        configuration.valves.length != configuration.valveCount) {
      issues.add(
        RvValidationIssue(
          code: 'parcel_valve_count_invalid',
          message: 'La cantidad de válvulas no coincide con la configuración.',
          sectionId: section.id,
          fieldId: 'valveCount',
          componentType: 'parcel_valves',
          focusKey: 'parcel:valveCount',
        ),
      );
      return;
    }
    for (final valve in configuration.valves) {
      final subItem = 'valve-${valve.index}';
      void missing(String field, String label) => issues.add(
        RvValidationIssue(
          code: 'parcel_valve_field_missing',
          message: 'Falta $label de la válvula ${valve.index}.',
          sectionId: section.id,
          subItemId: subItem,
          fieldId: field,
          componentType: 'parcel_valve',
          instanceIndex: valve.index,
          focusKey: 'parcel:$subItem:$field',
        ),
      );
      if (!_catalogSelectionValid(valve.valveBrand)) {
        missing('valveBrand', 'marca');
      }
      if (!_catalogSelectionValid(valve.diameter, diameter: true)) {
        missing('diameter', 'diámetro');
      }
      if (valve.hasSolenoid && !_catalogSelectionValid(valve.solenoidBrand)) {
        missing('solenoidBrand', 'marca del solenoide');
      }
      if (valve.hasPilot && !_catalogSelectionValid(valve.pilotBrand)) {
        missing('pilotBrand', 'marca del piloto');
      }
      if (valve.hasPilot && valve.pilotConnected == null) {
        issues.add(
          RvValidationIssue(
            code: 'pilot_connection_missing',
            message:
                'Falta indicar si el piloto de la válvula ${valve.index} está conectado.',
            sectionId: section.id,
            subItemId: subItem,
            fieldId: 'pilotConnected',
            componentType: 'parcel_valve',
            instanceIndex: valve.index,
            focusKey: 'parcel:$subItem:pilotConnected',
          ),
        );
      }
      if (valve.hasPressureGauge &&
          !_catalogSelectionValid(valve.pressureGaugeBrand)) {
        missing('pressureGaugeBrand', 'marca del manómetro');
      }
    }
  }

  bool _catalogSelectionValid(
    Map<String, dynamic>? value, {
    bool diameter = false,
  }) {
    if (value == null) return false;
    if (!diameter && value['mode'] == 'illegible') {
      return value['brandId'] == null &&
          (value['reason']?.toString().trim().length ?? 0) >= 10;
    }
    final display = value['displayValue']?.toString().trim() ?? '';
    final remote = value['catalogId']?.toString().trim() ?? '';
    final local = value['localCatalogId']?.toString().trim() ?? '';
    if (display.isEmpty || (remote.isEmpty && local.isEmpty)) return false;
    if (!diameter) return true;
    final numeric = value['nominalValue'];
    return numeric is num && numeric > 0 && value['unit'] == 'in';
  }

  bool _empty(ChecklistItemDefinition item, RvAnswer answer) {
    final value = answer.value;
    if (value is Map) {
      if (item.code.contains('brand') && value['mode'] == 'illegible') {
        return (value['reason']?.toString().trim().length ?? 0) < 10;
      }
      final display = value['displayValue']?.toString().trim() ?? '';
      final remote = value['catalogId']?.toString().trim() ?? '';
      final local = value['localCatalogId']?.toString().trim() ?? '';
      return display.isEmpty || (remote.isEmpty && local.isEmpty);
    }
    return value == null && answer.selectedOptions.isEmpty;
  }

  bool _validType(ChecklistItemDefinition item, RvAnswer answer) {
    final value = answer.value;
    if (value is Map && _isPressureGaugeRange(item.code)) {
      final display = value['displayValue']?.toString().trim() ?? '';
      final remote = value['catalogId']?.toString().trim() ?? '';
      final local = value['localCatalogId']?.toString().trim() ?? '';
      final minimum = value['minimum'];
      final maximum = value['maximum'];
      final unit = value['unit']?.toString().trim().toLowerCase();
      return display.isNotEmpty &&
          (remote.isNotEmpty || local.isNotEmpty) &&
          minimum is num &&
          maximum is num &&
          minimum.isFinite &&
          maximum.isFinite &&
          minimum >= 0 &&
          maximum > minimum &&
          const {'psi', 'bar'}.contains(unit);
    }
    if (value is Map && item.code.contains('brand')) {
      if (value['mode'] == 'illegible') {
        return value['brandId'] == null &&
            (value['reason']?.toString().trim().length ?? 0) >= 10;
      }
      final display = value['displayValue']?.toString().trim() ?? '';
      final remote = value['catalogId']?.toString().trim() ?? '';
      final local = value['localCatalogId']?.toString().trim() ?? '';
      final type = value['elementType']?.toString().trim() ?? '';
      return display.isNotEmpty &&
          (remote.isNotEmpty || local.isNotEmpty) &&
          type.isNotEmpty;
    }
    if (value is Map && item.code.contains('diameter')) {
      final display = value['displayValue']?.toString().trim() ?? '';
      final remote = value['catalogId']?.toString().trim() ?? '';
      final local = value['localCatalogId']?.toString().trim() ?? '';
      final numeric = value['nominalValue'];
      return display.isNotEmpty &&
          (remote.isNotEmpty || local.isNotEmpty) &&
          numeric is num &&
          numeric > 0 &&
          value['unit'] == 'in';
    }
    return switch (item.type) {
      'boolean' => value is bool,
      'integer' => value is int,
      'decimal' => value is num,
      'text' || 'date' || 'select' =>
        value is String &&
            (item.type != 'select' || item.options.contains(value)),
      'multiselect' => answer.selectedOptions.every(item.options.contains),
      _ => true,
    };
  }

  bool _compare(Object? actual, String operator, Object? expected) {
    if (actual is Map && actual['state'] != null) {
      actual = actual['state'] == 'present'
          ? true
          : actual['state'] == 'absent'
          ? false
          : null;
    }
    if (operator == 'in') {
      final list = expected is List ? expected : [expected];
      return actual is List ? actual.any(list.contains) : list.contains(actual);
    }
    if (operator == 'eq') return actual == expected;
    if (operator == 'neq') return actual != expected;
    final a = num.tryParse('$actual'), b = num.tryParse('$expected');
    if (a == null || b == null) return false;
    return switch (operator) {
      'gt' => a > b,
      'gte' => a >= b,
      'lt' => a < b,
      'lte' => a <= b,
      _ => false,
    };
  }

  bool _isPressureGaugeRange(String code) => const {
    'sustaining_gauge_range',
    'regulating_gauge_range',
    'filter_gauge_before_range',
    'filter_gauge_after_range',
    'parcel_gauge_range',
  }.contains(code);
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}

// ignore_for_file: curly_braces_in_flow_control_structures
