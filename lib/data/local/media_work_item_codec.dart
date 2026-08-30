import 'dart:convert';

class MediaWorkItem {
  const MediaWorkItem({
    required this.photoId,
    required this.status,
    this.inspectionId,
    this.slotCode,
    this.legacyRaw,
    this.schemaVersion = 2,
  });

  final String photoId, status;
  final String? inspectionId, slotCode, legacyRaw;
  final int schemaVersion;

  Map<String, dynamic> toJson() => {
    'schemaVersion': 2,
    'kind': 'mediaWorkItem',
    'photoId': photoId,
    'inspectionId': inspectionId,
    'slotCode': slotCode,
    'status': status,
    'legacyRaw': legacyRaw,
    'updatedAt': DateTime.now().toUtc().toIso8601String(),
  };
}

/// Tolerant read-old/write-new codec. Unknown legacy values remain actionable
/// and retain their exact source instead of being discarded on parse errors.
abstract final class MediaWorkItemCodec {
  static String? statusOf(String? key, String? raw) =>
      raw == null ? null : decode(key ?? '', raw).status;

  static MediaWorkItem decode(String key, String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        final json = Map<String, dynamic>.from(decoded);
        return MediaWorkItem(
          photoId: '${json['photoId'] ?? key}',
          inspectionId: json['inspectionId']?.toString(),
          slotCode: json['slotCode']?.toString(),
          status: '${json['status'] ?? json['state'] ?? 'pendingRecovery'}',
          legacyRaw: json['schemaVersion'] == null ? raw : null,
          schemaVersion: json['schemaVersion'] as int? ?? 1,
        );
      }
    } on FormatException {
      // A malformed JSON-looking entry is recoverable work, never absence.
    }
    final value = raw.trim();
    return MediaWorkItem(
      photoId: key,
      status: value.isEmpty ? 'pendingRecovery' : value,
      legacyRaw: raw,
      schemaVersion: 1,
    );
  }

  static String encode(MediaWorkItem item) => jsonEncode(item.toJson());

  /// Compares only persisted work semantics. Volatile metadata such as
  /// `updatedAt` must never turn an otherwise identical bootstrap pass into a
  /// write.
  static bool semanticallyMatches(
    String key,
    String? raw, {
    required String photoId,
    required String? inspectionId,
    required String? slotCode,
    required String status,
  }) {
    return reconcilePending(
          key,
          raw,
          photoId: photoId,
          inspectionId: inspectionId,
          slotCode: slotCode,
          status: status,
        ) ==
        null;
  }

  /// Returns a write-new value only when the requested operation differs.
  ///
  /// Existing schema-v2 worker metadata (retry/backoff, errors, leases,
  /// dependencies and future additive markers) is deliberately carried
  /// forward. `updatedAt` is ignored for equality and renewed only for a real
  /// transition of identity, slot or requested operation.
  static String? reconcilePending(
    String key,
    String? raw, {
    required String photoId,
    required String? inspectionId,
    required String? slotCode,
    required String status,
  }) {
    final decoded = _jsonMap(raw);
    final version = decoded?['schemaVersion'];
    if (version is int && version > 2) return null;
    final current = _schemaTwoMap(raw);
    final candidate =
        current == null
              ? <String, dynamic>{
                  'schemaVersion': 2,
                  'kind': 'mediaWorkItem',
                  'photoId': photoId,
                  'inspectionId': inspectionId,
                  'slotCode': slotCode,
                  'status': status,
                  'legacyRaw': raw,
                }
              : Map<String, dynamic>.from(current)
          ..['schemaVersion'] = 2
          ..['kind'] = 'mediaWorkItem'
          ..['photoId'] = photoId
          ..['inspectionId'] = inspectionId
          ..['slotCode'] = slotCode
          ..['status'] = status;
    if (current != null &&
        _canonicalOperationalJson(key, current) ==
            _canonicalOperationalJson(key, candidate)) {
      return null;
    }
    candidate['updatedAt'] = DateTime.now().toUtc().toIso8601String();
    return jsonEncode(candidate);
  }

  static Map<String, dynamic>? _schemaTwoMap(String? raw) {
    final value = _jsonMap(raw);
    if (value == null ||
        value['schemaVersion'] != 2 ||
        value['kind'] != 'mediaWorkItem') {
      return null;
    }
    return value;
  }

  static Map<String, dynamic>? _jsonMap(String? raw) {
    if (raw == null) return null;
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map ? Map<String, dynamic>.from(decoded) : null;
    } on FormatException {
      return null;
    }
  }

  static String _canonicalOperationalJson(
    String key,
    Map<String, dynamic> source,
  ) {
    final value = Map<String, dynamic>.from(source)..remove('updatedAt');
    for (final field in const ['photoId', 'inspectionId']) {
      final raw = value[field];
      if (raw != null) value[field] = '$raw'.toLowerCase();
    }
    value['photoId'] ??= key.toLowerCase();
    return jsonEncode(_canonicalize(value));
  }

  static Object? _canonicalize(Object? value) {
    if (value is Map) {
      final keys = value.keys.map((key) => '$key').toList()..sort();
      return <String, Object?>{
        for (final key in keys) key: _canonicalize(value[key]),
      };
    }
    if (value is List) return value.map(_canonicalize).toList();
    return value;
  }

  static String pending({
    required String photoId,
    String? inspectionId,
    String? slotCode,
    String status = 'pendingUpload',
  }) => encode(
    MediaWorkItem(
      photoId: photoId,
      inspectionId: inspectionId,
      slotCode: slotCode,
      status: status,
    ),
  );
}
