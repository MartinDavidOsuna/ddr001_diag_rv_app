enum PhotoIntegrityStatus {
  serverConfirmationPending,
  verifying,
  confirmed,
  missingOriginal,
  missingThumbnail,
  hashMismatch,
  missingMapping,
  mappingConflict,
  deleted,
  notVerified,
  notFound,
  capabilityUnavailable,
  retryRequired;

  bool get isConfirmed => this == PhotoIntegrityStatus.confirmed;
  bool get requiresReview => const {
    PhotoIntegrityStatus.mappingConflict,
    PhotoIntegrityStatus.deleted,
  }.contains(this);

  static PhotoIntegrityStatus fromPersisted(Object? value) {
    final wire = value?.toString();
    return PhotoIntegrityStatus.values.firstWhere(
      (item) => item.name == wire,
      orElse: () => PhotoIntegrityStatus.serverConfirmationPending,
    );
  }
}

enum PhotoMappingStatus { mapped, missing, conflict, notApplicable, unknown }

PhotoMappingStatus photoMappingStatusFromWire(Object? value) =>
    switch (value?.toString()) {
      'mapped' => PhotoMappingStatus.mapped,
      'missing' => PhotoMappingStatus.missing,
      'conflict' => PhotoMappingStatus.conflict,
      'not_applicable' => PhotoMappingStatus.notApplicable,
      _ => PhotoMappingStatus.unknown,
    };

bool isEvidenceFullyConfirmed(Iterable<PhotoIntegrityStatus> statuses) {
  final values = statuses.toList(growable: false);
  return values.isNotEmpty && values.every((status) => status.isConfirmed);
}
