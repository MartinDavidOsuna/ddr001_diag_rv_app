enum RvLocalStatus {
  draft,
  pendingCreate,
  creating,
  created,
  pendingAnswers,
  pendingLocation,
  pendingSignal,
  pendingPhotos,
  readyToSubmit,
  submitPending,
  submitting,
  submitted,
  conflict,
  pendingVersion,
  syncingVersion,
  versionConflict,
  requiresAuthentication,
  syncError,
  inactive,
  cancelled,
}

enum RvEditingMode { capture, technical, validatedComplements, readOnly }

enum RvPartStatus { notCaptured, pending, syncing, synced, error }

enum RvSyncStep {
  create,
  answers,
  location,
  signal,
  photos,
  reconcile,
  submit,
  verify,
}

enum RvPhotoUploadStatus { pending, uploading, verified, error, missingLocal }
