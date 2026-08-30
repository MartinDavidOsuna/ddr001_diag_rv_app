/// Canonicalizes one persisted F02A scoped-key segment.
///
/// Blank values are absent. Non-blank values are trimmed, lower-cased and
/// URI-component encoded in that order so every recovery subsystem derives
/// the same stable key across processes.
String? canonicalScopeSegment(String? value) {
  final normalized = value?.trim();
  if (normalized == null || normalized.isEmpty) return null;
  return Uri.encodeComponent(normalized.toLowerCase());
}

/// Returns the first meaningful persisted owner identity for F02A.
String? resolveF02AOwnerUserId({
  String? ownerUserId,
  String? createdBy,
  String? inspectorId,
}) {
  for (final candidate in [ownerUserId, createdBy, inspectorId]) {
    final normalized = candidate?.trim();
    if (normalized != null && normalized.isNotEmpty) return normalized;
  }
  return null;
}

/// Builds the canonical scoped active-index key used exclusively by F02A/RV.
///
/// Returns null when the persisted identity is incomplete. Callers then keep
/// the existing conservative legacy/manual-review behavior; no identity is
/// invented and no foreign scoped key is adopted.
String? buildF02AScopedKey({
  required String? environment,
  required String? accountId,
  required String? ownerUserId,
  required String? createdBy,
  required String? inspectorId,
  required String? hydrantId,
}) {
  final environmentPart = canonicalScopeSegment(environment);
  final accountPart = canonicalScopeSegment(accountId);
  final ownerPart = canonicalScopeSegment(
    resolveF02AOwnerUserId(
      ownerUserId: ownerUserId,
      createdBy: createdBy,
      inspectorId: inspectorId,
    ),
  );
  final hydrantPart = canonicalScopeSegment(hydrantId);
  if (environmentPart == null ||
      accountPart == null ||
      ownerPart == null ||
      hydrantPart == null) {
    return null;
  }
  return '$environmentPart/$accountPart/$ownerPart/$hydrantPart/f02A';
}
