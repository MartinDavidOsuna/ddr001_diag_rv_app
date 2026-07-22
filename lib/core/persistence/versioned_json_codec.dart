import 'dart:convert';

class VersionedJsonDocument {
  const VersionedJsonDocument({
    required this.schemaVersion,
    required this.payload,
  });
  final int schemaVersion;
  final Map<String, dynamic> payload;
}

abstract final class VersionedJsonCodec {
  static String encode({
    required int schemaVersion,
    required Map<String, dynamic> payload,
  }) => jsonEncode({
    'schemaVersion': schemaVersion,
    'writtenAt': DateTime.now().toUtc().toIso8601String(),
    'payload': payload,
  });

  static VersionedJsonDocument decode(String source) {
    final root = Map<String, dynamic>.from(jsonDecode(source) as Map);
    return VersionedJsonDocument(
      schemaVersion: root['schemaVersion'] as int? ?? 1,
      payload: Map<String, dynamic>.from(root['payload'] as Map? ?? root),
    );
  }
}

DateTime? dateFromJson(Object? value) =>
    value is String ? DateTime.tryParse(value)?.toUtc() : null;
String? dateToJson(DateTime? value) => value?.toUtc().toIso8601String();
T enumByName<T extends Enum>(List<T> values, Object? name, T fallback) {
  for (final value in values) {
    if (value.name == name) return value;
  }
  return fallback;
}
