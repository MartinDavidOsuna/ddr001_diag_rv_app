import 'package:flutter/foundation.dart';

import '../domain/rv_draft.dart';
import '../domain/rv_validator.dart';

class RvPayloadException implements Exception {
  const RvPayloadException({required this.questionId, required this.message});
  final String questionId, message;
}

class RvAnswerPayloadBuilder {
  const RvAnswerPayloadBuilder({this.validator = const RvValidator()});
  final RvValidator validator;

  List<Map<String, dynamic>> build(RvDraft draft) {
    final payload = <Map<String, dynamic>>[];
    for (final section in draft.checklist.sections) {
      // Step 8 has a normalized, independent endpoint.
      if (section.code == 'valvulas_parcelarias') continue;
      for (final item in section.items) {
        if (const {
          'photo',
          'coordinates',
          'signal',
          'readonly',
        }.contains(item.type)) {
          continue;
        }
        final answer = draft.answers[item.id];
        if (answer == null) continue;
        final visible = validator.isVisible(
          item,
          draft.checklist,
          draft.answers,
        );
        final notApplicable = answer.notApplicable || !visible;
        final catalog = answer.value is Map
            ? Map<String, dynamic>.from(answer.value! as Map)
            : null;
        final value = notApplicable
            ? null
            : item.code == 'filter_element' && catalog != null
            ? catalog['state']
            : _serializedValue(item.type, item.id, answer, catalog);
        final row = <String, dynamic>{
          'itemId': item.id,
          if (!notApplicable) 'value': value,
          'notApplicable': notApplicable,
        };
        if (!notApplicable &&
            item.code == 'filter_element' &&
            catalog != null) {
          row['value'] = catalog['state'];
          row['filterElement'] = {
            'state': catalog['state'],
            'reason': catalog['state'] == 'undefined'
                ? catalog['reason']
                : null,
          };
          payload.add(row);
          continue;
        }
        if (!notApplicable && catalog != null) {
          if (item.code.contains('brand') && catalog['mode'] == 'illegible') {
            final evidence = draft
                .photosFor('brand_illegible:${item.id}')
                .where((photo) => photo.serverPhotoId != null)
                .firstOrNull;
            row['brandSelection'] = {
              'mode': 'illegible',
              'brandId': null,
              'displayName': 'Ilegible',
              'reason': catalog['reason'],
              'evidencePhotoId': evidence?.serverPhotoId,
            };
            row['catalogDisplayValue'] = 'Ilegible';
            payload.add(row);
            continue;
          }
          final remoteId = catalog['catalogId']?.toString().trim() ?? '';
          if (remoteId.isEmpty) {
            throw RvPayloadException(
              questionId: item.id,
              message:
                  'No se pudo reconciliar el catálogo de ${item.label}. '
                  'La revisión permanece guardada.',
            );
          }
          if (item.code.contains('brand')) {
            row['brandId'] = remoteId;
            row['brandSelection'] = {
              'mode': 'readable',
              'brandId': remoteId,
              'displayName': catalog['displayValue'],
              'reason': null,
              'evidencePhotoId': null,
            };
          }
          if (item.code.contains('diameter')) row['diameterId'] = remoteId;
          if (item.code.contains('gauge_range')) {
            row['pressureRangeId'] = remoteId;
            row['pressureRangeMinimum'] = catalog['minimum'];
            row['pressureRangeMaximum'] = catalog['maximum'];
            row['pressureRangeUnit'] = catalog['unit'];
            row['pressureRangeDisplay'] = catalog['displayValue'];
          }
          row['catalogDisplayValue'] = catalog['displayValue']?.toString();
        }
        payload.add(row);
      }
    }
    if (kDebugMode) _debugPayload(draft, payload);
    return payload;
  }

  Object? _serializedValue(
    String answerType,
    String questionId,
    RvAnswer answer,
    Map<String, dynamic>? catalog,
  ) {
    final value = switch (answerType) {
      'multiselect' => answer.selectedOptions,
      'decimal' || 'integer' when catalog != null =>
        catalog['numericValue'] ?? catalog['nominalValue'],
      _ when catalog != null => catalog['displayValue'],
      _ => answer.value,
    };
    final valid = switch (answerType) {
      'boolean' => value is bool,
      'integer' => value is int || (value is num && value % 1 == 0),
      'decimal' => value is num,
      'text' || 'date' || 'select' => value is String,
      'multiselect' => value is List,
      _ => true,
    };
    if (!valid) {
      throw RvPayloadException(
        questionId: questionId,
        message:
            'La respuesta no puede serializarse como $answerType. '
            'La revisión permanece guardada.',
      );
    }
    return answerType == 'integer' && value is num ? value.toInt() : value;
  }

  void _debugPayload(RvDraft draft, List<Map<String, dynamic>> payload) {
    debugPrint(
      '[RV-ANSWERS] inspection=${draft.clientInspectionId.substring(0, 8)} '
      'answerCount=${payload.length}',
    );
    for (final row in payload) {
      final original = draft.answers[row['itemId']];
      final catalog = original?.value is Map
          ? original!.value as Map
          : const {};
      debugPrint(
        '[RV-ANSWER] questionId=${row['itemId']} '
        'answerType=${original?.answerType} '
        'serializedValueType=${row['value']?.runtimeType ?? 'null'} '
        'catalogIdPresent=${catalog['catalogId'] != null} '
        'localCatalogIdPresent=${catalog['localCatalogId'] != null} '
        'elementType=${catalog['elementType'] ?? '-'} '
        'pendingSync=${catalog['isPendingSync'] ?? false}',
      );
    }
  }
}
