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
  requiresAuthentication,
  syncError,
  cancelled,
}

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
