import '../../checklist/data/checklist_models.dart';
import 'rv_draft.dart';
import 'rv_sync_state.dart';

class RvValidationIssue {
  const RvValidationIssue({
    required this.code,
    required this.message,
    this.sectionId,
    this.questionId,
    this.slotCode,
  });
  final String code, message;
  final String? sectionId, questionId, slotCode;
}

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
    final checklist = draft.checklist;
    for (final section in checklist.sections) {
      for (final item in section.items) {
        if (!isVisible(item, checklist, draft.answers) ||
            const {
              'photo',
              'coordinates',
              'signal',
              'readonly',
            }.contains(item.type))
          continue;
        final answer = draft.answers[item.id];
        if (item.required &&
            (answer == null || (!answer.notApplicable && _empty(answer)))) {
          issues.add(
            RvValidationIssue(
              code: 'required_answer_missing',
              message: 'Falta responder ${item.label}.',
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
        ),
      );
    if (draft.signal == null)
      issues.add(
        const RvValidationIssue(
          code: 'signal_missing',
          message: 'Falta capturar la conectividad.',
        ),
      );
    for (final slot in requiredRvPhotoSlots) {
      final photo = draft.photos[slot];
      if (photo == null) {
        issues.add(
          RvValidationIssue(
            code: 'required_photo_missing',
            message: 'Falta ${rvPhotoSlotLabels[slot]}.',
            slotCode: slot,
          ),
        );
      } else if (requireSynced &&
          photo.status != RvPhotoUploadStatus.verified) {
        issues.add(
          RvValidationIssue(
            code: 'photo_pending',
            message: '${rvPhotoSlotLabels[slot]} no está subida.',
            slotCode: slot,
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

  bool _empty(RvAnswer answer) =>
      answer.value == null && answer.selectedOptions.isEmpty;

  bool _validType(ChecklistItemDefinition item, RvAnswer answer) {
    final value = answer.value;
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
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}

// ignore_for_file: curly_braces_in_flow_control_structures
