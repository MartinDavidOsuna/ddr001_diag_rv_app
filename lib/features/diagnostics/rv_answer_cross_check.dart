import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../inspections/data/rv_answer_payload_builder.dart';
import '../inspections/domain/rv_draft.dart';

/// Produces value-free evidence that every locally captured answer was checked
/// against the server representation. Raw answers never leave this helper.
Map<String, dynamic> buildRvAnswerCrossCheck(
  RvDraft draft,
  Object? remoteAnswers,
) {
  final captured =
      draft.answers.values
          .map((answer) {
            return Map<String, dynamic>.from(answer.toJson())
              ..remove('updatedAt');
          })
          .toList(growable: false)
        ..sort(
          (left, right) =>
              '${left['questionId']}'.compareTo('${right['questionId']}'),
        );

  List<Map<String, dynamic>>? localContract;
  String? serializationIssue;
  try {
    localContract =
        const RvAnswerPayloadBuilder()
            .build(draft)
            .map(_normalizeContractRow)
            .toList(growable: false)
          ..sort(_byItemId);
  } on RvPayloadException catch (error) {
    serializationIssue = error.questionId;
  } on Object catch (error) {
    serializationIssue = error.runtimeType.toString();
  }

  final remoteContract = remoteAnswers is List
      ? remoteAnswers
            .whereType<Map>()
            .map((row) => _remoteContractRow(Map<String, dynamic>.from(row)))
            .whereType<Map<String, dynamic>>()
            .toList(growable: false)
      : null;
  remoteContract?.sort(_byItemId);

  final localById = {
    for (final row in localContract ?? const <Map<String, dynamic>>[])
      '${row['itemId']}': row,
  };
  final remoteById = {
    for (final row in remoteContract ?? const <Map<String, dynamic>>[])
      '${row['itemId']}': row,
  };
  final missingRemote =
      localById.keys
          .where((id) => !remoteById.containsKey(id))
          .toList(growable: false)
        ..sort();
  final unexpectedRemote =
      remoteById.keys
          .where((id) => !localById.containsKey(id))
          .toList(growable: false)
        ..sort();
  final divergent =
      localById.keys
          .where(
            (id) =>
                remoteById.containsKey(id) &&
                _canonicalJson(localById[id]) != _canonicalJson(remoteById[id]),
          )
          .toList(growable: false)
        ..sort();
  final comparable = localContract != null && remoteContract != null;

  return {
    'localCapturedCount': captured.length,
    'localCapturedSha256': _hash(captured),
    'localContractCount': localContract?.length,
    'localContractSha256': localContract == null ? null : _hash(localContract),
    'remoteContractCount': remoteContract?.length,
    'remoteContractSha256': remoteContract == null
        ? null
        : _hash(remoteContract),
    'comparable': comparable,
    'match':
        comparable &&
        missingRemote.isEmpty &&
        unexpectedRemote.isEmpty &&
        divergent.isEmpty,
    'missingRemoteItemIds': missingRemote,
    'unexpectedRemoteItemIds': unexpectedRemote,
    'divergentItemIds': divergent,
    'localSerializationIssue': serializationIssue,
  };
}

Map<String, dynamic> _normalizeContractRow(Map<String, dynamic> input) =>
    Map<String, dynamic>.from(_normalize(input) as Map);

Map<String, dynamic>? _remoteContractRow(Map<String, dynamic> source) {
  final rawId = source['item_id'] ?? source['itemId'];
  if (rawId == null || '$rawId'.trim().isEmpty) return null;
  final notApplicable =
      source['is_not_applicable'] == true ||
      source['is_not_applicable'] == 1 ||
      source['notApplicable'] == true;
  final row = <String, dynamic>{
    'itemId': '$rawId',
    'notApplicable': notApplicable,
  };
  if (notApplicable) return _normalizeContractRow(row);

  row['value'] = _remoteValue(source);
  final filterState =
      source['filter_element_state'] ?? source['filterElementState'];
  if (filterState != null) {
    row['value'] = '$filterState';
    row['filterElement'] = {
      'state': '$filterState',
      'reason':
          source['filter_element_undefined_reason'] ??
          source['filterElementUndefinedReason'],
    };
  }

  final brandReadability =
      source['brand_readability'] ?? source['brandReadability'];
  final brandId = source['brand_id'] ?? source['brandId'];
  final display =
      source['catalog_display_value'] ?? source['catalogDisplayValue'];
  if (brandReadability != null) {
    final readable = '$brandReadability' == 'readable';
    if (readable && brandId != null) row['brandId'] = brandId;
    row['brandSelection'] = {
      'mode': '$brandReadability',
      'brandId': readable ? brandId : null,
      'displayName': readable ? display : 'Ilegible',
      'reason': readable
          ? null
          : source['brand_illegible_reason'] ?? source['brandIllegibleReason'],
      'evidencePhotoId':
          source['brand_evidence_photo_id'] ?? source['brandEvidencePhotoId'],
    };
  }
  final diameter = source['diameter_id'] ?? source['diameterId'];
  if (diameter != null) row['diameterId'] = diameter;
  final pressure = source['pressure_range_id'] ?? source['pressureRangeId'];
  if (pressure != null) {
    row['pressureRangeId'] = pressure;
    row['pressureRangeMinimum'] =
        source['pressure_range_minimum'] ?? source['pressureRangeMinimum'];
    row['pressureRangeMaximum'] =
        source['pressure_range_maximum'] ?? source['pressureRangeMaximum'];
    row['pressureRangeUnit'] =
        source['pressure_range_unit'] ?? source['pressureRangeUnit'];
    row['pressureRangeDisplay'] =
        source['pressure_range_display'] ?? source['pressureRangeDisplay'];
  }
  if (display != null) row['catalogDisplayValue'] = display;
  return _normalizeContractRow(row);
}

Object? _remoteValue(Map<String, dynamic> source) {
  final boolean = source['value_boolean'] ?? source['valueBoolean'];
  if (boolean != null) return boolean == true || boolean == 1;
  final number = source['value_number'] ?? source['valueNumber'];
  if (number != null) {
    final parsed = number is num ? number : num.tryParse('$number');
    if (parsed != null && parsed == parsed.toInt()) return parsed.toInt();
    return parsed;
  }
  final encoded = source['value_json'] ?? source['valueJson'];
  if (encoded != null) {
    if (encoded is String) {
      try {
        return jsonDecode(encoded);
      } on FormatException {
        return encoded;
      }
    }
    return encoded;
  }
  return source['value_text'] ?? source['valueText'] ?? source['value'];
}

int _byItemId(Map<String, dynamic> left, Map<String, dynamic> right) =>
    '${left['itemId']}'.compareTo('${right['itemId']}');

String _hash(Object? value) =>
    sha256.convert(utf8.encode(_canonicalJson(value))).toString();

String _canonicalJson(Object? value) => jsonEncode(_normalize(value));

Object? _normalize(Object? value, {String? key}) {
  if (value is Map) {
    final keys = value.keys.map((item) => '$item').toList()..sort();
    return <String, dynamic>{
      for (final item in keys) item: _normalize(value[item], key: item),
    };
  }
  if (value is List) return value.map((item) => _normalize(item)).toList();
  if (value is num && value == value.toInt()) return value.toInt();
  if (value is String && key != null && key.toLowerCase().endsWith('id')) {
    return value.trim().toLowerCase();
  }
  return value;
}
