/// Ciclo de vida persistible de una evidencia fotográfica.
///
/// Una transferencia terminada queda [uploadedUnverified]. Únicamente
/// [verified], después de confirmar existencia, tamaño, checksum y asociación
/// remota, puede contabilizarse como sincronizada.
enum MediaSyncStatus {
  captured,
  validating,
  processing,
  storedLocal,
  pendingUpload,
  uploading,
  uploadedUnverified,
  verified,
  failedRetryable,
  failedPermanent,
  missingLocal,
  remoteMissing;

  bool get isSynchronized => this == MediaSyncStatus.verified;
}
