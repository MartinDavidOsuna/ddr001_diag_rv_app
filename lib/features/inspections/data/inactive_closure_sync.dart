// ignore_for_file: curly_braces_in_flow_control_structures
part of 'inspection_sync_coordinator.dart';

extension InactiveClosureSynchronization on InspectionSyncCoordinator {
  Future<RvDraft> synchronizeInactive(
    RvDraft initial, {
    bool forceRetry = false,
  }) async {
    var draft = drafts.find(initial.clientInspectionId) ?? initial;
    final owner = drafts.visualRepository.accessScopeUserId;
    final closure = draft.inactiveClosure;
    bool owns() =>
        owner != null &&
        owner.isNotEmpty &&
        drafts.visualRepository.accessScopeUserId == owner &&
        closure?.closedByUserId.toLowerCase() == owner.toLowerCase() &&
        drafts.find(draft.clientInspectionId) != null;
    if (!draft.isInactive || closure == null || !owns()) return draft;
    if (isInactiveRemoteVerified(draft)) return draft;
    if (!forceRetry &&
        (closure.syncStatus == RvInactiveClosureSyncStatus.conflict ||
            closure.syncStatus == RvInactiveClosureSyncStatus.requiresReview ||
            (draft.nextRetryAt?.isAfter(DateTime.now().toUtc()) ?? false)))
      return draft;
    final lock = draft.clientInspectionId.toLowerCase();
    if (!InspectionSyncCoordinator._running.add(lock)) return draft;
    void guard() {
      if (!owns())
        throw const ApiException(
          ApiErrorKind.authenticationRequired,
          'La sesión cambió; la ausencia permanece guardada.',
          statusCode: 401,
        );
    }

    try {
      // A flushed receipt survives an interrupted final metadata write.
      if (closure.remoteReceipt != null &&
          draft.serverInspectionId != null &&
          inactiveReceiptMatches(
            closure.remoteReceipt!,
            draft.serverInspectionId!,
            closure,
          )) {
        return await _confirmInactive(draft, closure.remoteReceipt!, guard);
      }
      if (!await remote.supportsInactiveClosure()) {
        guard();
        return await _inactiveState(
          draft,
          RvInactiveClosureSyncStatus.pendingApiContract,
          message:
              'Ausente · pendiente de sincronizar. La API todavía no anuncia soporte para este cierre.',
          code: 'INACTIVE_CAPABILITY_UNAVAILABLE',
          retryAt: DateTime.now().toUtc().add(const Duration(minutes: 5)),
        );
      }
      guard();
      // Read before validation/upload: lost responses must not require local files.
      var inspection = await remote.findByClientInspectionId(
        draft.clientInspectionId,
      );
      guard();
      if (inspection == null && draft.serverInspectionId != null) {
        inspection = await remote.get(draft.serverInspectionId!);
        guard();
      }
      if (inspection == null) {
        if (!validInactiveCommand(closure))
          throw const ApiException(
            ApiErrorKind.validation,
            'El cierre guardado no cumple el contrato de ausencia; requiere revisión sin modificar sus originales.',
            statusCode: 422,
            domainCode: 'INACTIVE_LOCAL_CONTRACT_INVALID',
          );
        inspection = await remote.create(draft);
        guard();
      }
      if ((inspection.clientInspectionId != null &&
              inspection.clientInspectionId!.toLowerCase() !=
                  draft.clientInspectionId.toLowerCase()) ||
          (draft.serverInspectionId != null &&
              draft.serverInspectionId!.toLowerCase() !=
                  inspection.id.toLowerCase())) {
        throw const ApiException(
          ApiErrorKind.validation,
          'La identidad remota difiere del cierre local.',
          statusCode: 409,
          domainCode: 'INACTIVE_IDENTITY_CONFLICT',
        );
      }
      draft = await _save(
        draft.copyWith(
          serverInspectionId: inspection.id,
          remoteStatus: inspection.status,
        ),
      );
      if (inspection.status == 'inactive' ||
          inspection.inactiveClosure != null) {
        return await _confirmInactive(
          draft,
          inspection.inactiveClosure ?? const {},
          guard,
        );
      }
      if (!validInactiveCommand(closure))
        throw const ApiException(
          ApiErrorKind.validation,
          'El cierre guardado no cumple el contrato de ausencia; requiere revisión sin modificar sus originales.',
          statusCode: 422,
          domainCode: 'INACTIVE_LOCAL_CONTRACT_INVALID',
        );
      draft = await _inactiveState(draft, RvInactiveClosureSyncStatus.syncing);
      final existing = await remote.photos(inspection.id);
      guard();
      for (final id in closure.photoIds) {
        guard();
        final photo = _photo(id);
        if (photo == null ||
            photo.isDeleted ||
            photo.inspectionId.toLowerCase() !=
                draft.clientInspectionId.toLowerCase() ||
            photo.capturedByUserId.toLowerCase() != owner!.toLowerCase() ||
            photo.category != noHydrantAtLocationPhotoSlot ||
            closure.normalizedPhotoHashes[id]?.toLowerCase() !=
                photo.sha256.toLowerCase() ||
            closure.receivedPhotoHashes[id]?.toLowerCase() !=
                photo.receivedSha256.toLowerCase()) {
          throw const ApiException(
            ApiErrorKind.validation,
            'La evidencia local de ausencia requiere revisión; sus archivos se conservan.',
            statusCode: 422,
            domainCode: 'INACTIVE_LOCAL_EVIDENCE_INVALID',
          );
        }
        final matches = existing
            .where((p) => p.id.toLowerCase() == id.toLowerCase())
            .toList();
        if (matches.any((p) => p.slotCode != noHydrantAtLocationPhotoSlot)) {
          throw const ApiException(
            ApiErrorKind.validation,
            'La fotografía remota pertenece a otro slot.',
            statusCode: 409,
            domainCode: 'INACTIVE_EVIDENCE_IDENTITY_CONFLICT',
          );
        }
        RemotePhotoIntegrity? integrity;
        if (matches.isNotEmpty) {
          final results = await remote.verifyPhotosBatch([id]);
          guard();
          integrity = results
              .where((p) => p.photoId.toLowerCase() == id.toLowerCase())
              .firstOrNull;
        }
        if (integrity == null || !integrity.status.isConfirmed) {
          if (integrity != null && integrity.status.requiresReview)
            throw const ApiException(
              ApiErrorKind.validation,
              'La evidencia remota presenta un conflicto de identidad.',
              statusCode: 409,
              domainCode: 'INACTIVE_EVIDENCE_IDENTITY_CONFLICT',
            );
          final uploaded = await remote.uploadPhoto(
            inspection.id,
            noHydrantAtLocationPhotoSlot,
            photo,
          );
          guard();
          if (uploaded.id.toLowerCase() != id.toLowerCase() ||
              uploaded.slotCode != noHydrantAtLocationPhotoSlot) {
            throw const ApiException(
              ApiErrorKind.validation,
              'El recibo fotográfico no coincide con la evidencia.',
              statusCode: 409,
              domainCode: 'INACTIVE_EVIDENCE_IDENTITY_CONFLICT',
            );
          }
          await _markPhotoUploadedUnverified(
            photo,
            uploaded.sha256,
            serverPhotoId: id,
          );
          final results = await remote.verifyPhotosBatch([id]);
          guard();
          integrity = results
              .where((p) => p.photoId.toLowerCase() == id.toLowerCase())
              .firstOrNull;
        }
        if (integrity == null ||
            !integrity.status.isConfirmed ||
            !integrity.originalPresent ||
            !integrity.storageVerified ||
            !integrity.mapped) {
          throw const ApiException(
            ApiErrorKind.validation,
            'El servidor no confirmó la evidencia de ausencia. Requiere revisión de evidencia.',
            statusCode: 422,
            domainCode: 'INACTIVE_EVIDENCE_REQUIRED',
          );
        }
        await _applyIntegrityResult(id, integrity);
      }
      guard();
      final receipt = await remote.closeInactive(
        inspection.id,
        inactiveClosureCommand(closure),
      );
      guard();
      return await _confirmInactive(draft, receipt, guard);
    } on ApiException catch (error) {
      draft = drafts.find(initial.clientInspectionId) ?? draft;
      if (!owns()) return drafts.find(initial.clientInspectionId) ?? draft;
      if (error.statusCode == 409) {
        try {
          final found = draft.serverInspectionId != null
              ? await remote.get(draft.serverInspectionId!)
              : await remote.findByClientInspectionId(draft.clientInspectionId);
          guard();
          if (found != null &&
              found.status == 'inactive' &&
              (found.clientInspectionId == null ||
                  found.clientInspectionId!.toLowerCase() ==
                      draft.clientInspectionId.toLowerCase()) &&
              found.inactiveClosure != null &&
              inactiveReceiptMatches(
                found.inactiveClosure!,
                draft.serverInspectionId ?? found.id,
                closure,
              )) {
            draft = await _save(draft.copyWith(serverInspectionId: found.id));
            return await _confirmInactive(draft, found.inactiveClosure!, guard);
          }
          if (found?.inactiveClosure != null)
            draft = await _inactiveState(
              draft,
              RvInactiveClosureSyncStatus.conflict,
              receipt: found!.inactiveClosure,
            );
        } on Object {
          /* Preserve the original conflict if its read fails. */
        }
      }
      final blocked =
          error.statusCode == 400 ||
          error.statusCode == 404 ||
          error.statusCode == 415 ||
          error.statusCode == 422 ||
          error.kind == ApiErrorKind.invalidData ||
          error.kind == ApiErrorKind.validation;
      return await _inactiveState(
        draft,
        error.statusCode == 409
            ? RvInactiveClosureSyncStatus.conflict
            : blocked
            ? RvInactiveClosureSyncStatus.requiresReview
            : RvInactiveClosureSyncStatus.pendingSync,
        message: switch (error.domainCode) {
          'INACTIVE_EVIDENCE_REQUIRED' =>
            'El servidor no dispone de toda la evidencia de ausencia verificada. Revisa las fotografías y reintenta.',
          'INACTIVE_EVIDENCE_INVALID' =>
            'La evidencia del servidor está ausente o no supera la verificación de integridad. Los originales locales se conservan.',
          'INACTIVE_CLOSURE_CONFLICT' || 'INACTIVE_KEY_REUSED' =>
            'La identidad o contenido del cierre remoto difiere. Requiere resolución explícita; se conserva el cierre local.',
          'INACTIVE_CLOSURE_BLOCKED' || 'INSPECTION_LOCKED' =>
            'Esta revisión remota está bloqueada. Requiere revisión explícita; la ausencia local se conserva.',
          _ => error.message,
        },
        code: error.domainCode ?? 'HTTP_${error.statusCode ?? 0}',
        retryAt: blocked || error.statusCode == 409
            ? null
            : DateTime.now().toUtc().add(_backoff(draft.retryCount + 1)),
      );
    } on Object catch (error) {
      draft = drafts.find(initial.clientInspectionId) ?? draft;
      if (!owns()) return draft;
      return await _inactiveState(
        draft,
        RvInactiveClosureSyncStatus.pendingSync,
        message: 'Ausente · pendiente de sincronizar: $error',
        code: 'INACTIVE_TRANSIENT_ERROR',
        retryAt: DateTime.now().toUtc().add(_backoff(draft.retryCount + 1)),
      );
    } finally {
      InspectionSyncCoordinator._running.remove(lock);
    }
  }

  /// Restore the terminal API result without completing a normal checklist or
  /// projecting a change onto the master hydrant.
  Future<RvDraft> restoreRemoteInactive(
    RvDraft draft,
    RemoteInspection inspection,
  ) async {
    final receipt = inspection.inactiveClosure;
    final document = drafts.visualRepository.findById(draft.clientInspectionId);
    final owner = drafts.visualRepository.accessScopeUserId;
    if (document == null ||
        owner == null ||
        document.createdBy.toLowerCase() != owner.toLowerCase())
      return draft;
    if (receipt == null ||
        receipt['closure'] is! Map ||
        (inspection.clientInspectionId != null &&
            inspection.clientInspectionId!.toLowerCase() !=
                draft.clientInspectionId.toLowerCase())) {
      return _save(
        draft.copyWith(
          localStatus: RvLocalStatus.conflict,
          remoteStatus: 'inactive',
          lastSyncError:
              'Ausente en el servidor, pero falta un recibo válido para restaurar. Requiere revisión.',
        ),
      );
    }
    final command = Map<String, dynamic>.from(receipt['closure'] as Map);
    final localRefs = draft.photosFor(noHydrantAtLocationPhotoSlot);
    final ids = (command['photoIds'] as List? ?? [])
        .map(
          (id) =>
              localRefs
                  .where(
                    (ref) => ref.photoId.toLowerCase() == '$id'.toLowerCase(),
                  )
                  .firstOrNull
                  ?.photoId ??
              '$id',
        )
        .toList();
    final closure =
        draft.inactiveClosure ??
        RvInactiveClosure.fromJson({
          ...command,
          'photoIds': ids,
          'closedByUserId': document.createdBy,
          'closedByName': document.inspectorName,
          'brigadeId': document.brigadeId,
          'deviceId': document.deviceId,
          'normalizedPhotoHashes': {
            for (final id in ids)
              if (_photo(id) != null) id: _photo(id)!.sha256,
          },
          'receivedPhotoHashes': {
            for (final id in ids)
              if (_photo(id) != null) id: _photo(id)!.receivedSha256,
          },
        });
    if (!inactiveReceiptMatches(receipt, inspection.id, closure)) {
      return _save(
        draft.copyWith(
          localStatus: RvLocalStatus.conflict,
          remoteStatus: 'inactive',
          lastSyncError:
              'El recibo de ausencia no coincide con la revisión local. Requiere resolución explícita.',
        ),
      );
    }
    draft = await _save(
      draft.copyWith(
        localStatus: RvLocalStatus.inactive,
        serverInspectionId: inspection.id,
        remoteStatus: 'inactive',
        inactiveClosure: closure,
      ),
    );
    return _confirmInactive(draft, receipt, () {
      if (drafts.visualRepository.accessScopeUserId != owner)
        throw const ApiException(
          ApiErrorKind.authenticationRequired,
          'La sesión cambió.',
          statusCode: 401,
        );
    });
  }

  Future<RvDraft> _inactiveState(
    RvDraft draft,
    RvInactiveClosureSyncStatus status, {
    String? message,
    String? code,
    DateTime? retryAt,
    Map<String, dynamic>? receipt,
  }) => _save(
    draft.copyWith(
      inactiveClosure: RvInactiveClosure.fromJson({
        ...draft.inactiveClosure!.toJson(),
        'syncStatus': status.name,
        'remoteDomainCode': code,
        'remoteReceipt': ?receipt,
      }),
      lastSyncError: message,
      clearError: message == null,
      nextRetryAt: retryAt,
      clearNextRetryAt: retryAt == null,
      lastAttemptAt: DateTime.now().toUtc(),
      retryCount: status == RvInactiveClosureSyncStatus.remoteVerified
          ? 0
          : message == null
          ? draft.retryCount
          : min(draft.retryCount + 1, 8),
    ),
  );

  Future<RvDraft> _confirmInactive(
    RvDraft draft,
    Map<String, dynamic> receipt,
    void Function() guard,
  ) async {
    guard();
    if (!inactiveReceiptMatches(
      receipt,
      draft.serverInspectionId!,
      draft.inactiveClosure!,
    )) {
      return _inactiveState(
        draft,
        RvInactiveClosureSyncStatus.conflict,
        receipt: receipt,
        message:
            'El recibo remoto no coincide con el cierre local. Se requiere resolución explícita.',
        code: 'INACTIVE_RECEIPT_CONFLICT',
      );
    }
    // A remote receipt never authorizes changing another local capture that
    // happens to share an ID. Missing files/documents do not prevent recovering
    // a committed closure, but conflicting local ownership must remain visible.
    for (final id in draft.inactiveClosure!.photoIds) {
      final photo = _photo(id);
      if (photo != null &&
          (photo.inspectionId.toLowerCase() !=
                  draft.clientInspectionId.toLowerCase() ||
              photo.capturedByUserId.toLowerCase() !=
                  draft.inactiveClosure!.closedByUserId.toLowerCase() ||
              photo.category != noHydrantAtLocationPhotoSlot)) {
        return _inactiveState(
          draft,
          RvInactiveClosureSyncStatus.conflict,
          receipt: receipt,
          message:
              'La identidad de una fotografía local no corresponde a este cierre. Se conserva sin cambios para revisión.',
          code: 'INACTIVE_LOCAL_EVIDENCE_IDENTITY_CONFLICT',
        );
      }
    }
    // Two durable writes: never publish remoteVerified without the full receipt.
    draft = await _inactiveState(
      draft,
      RvInactiveClosureSyncStatus.syncing,
      receipt: receipt,
    );
    await drafts.visualRepository.documents.flush();
    guard();
    final refs = {...draft.photos};
    refs[noHydrantAtLocationPhotoSlot] = [
      for (final id in draft.inactiveClosure!.photoIds)
        RvPhotoReference.fromJson({
          ...?draft
              .photosFor(noHydrantAtLocationPhotoSlot)
              .where((p) => p.photoId == id)
              .firstOrNull
              ?.toJson(),
          'photoId': id,
          'serverPhotoId': id,
          'slotCode': noHydrantAtLocationPhotoSlot,
          'status': RvPhotoUploadStatus.verified.name,
        }),
    ];
    // The transactional receipt is authoritative, including after a lost response.
    for (final id in draft.inactiveClosure!.photoIds) {
      await _applyIntegrityResult(
        id,
        RemotePhotoIntegrity(
          photoId: id,
          status: PhotoIntegrityStatus.confirmed,
          originalPresent: true,
          thumbnailPresent: _photo(id)?.thumbnailPresent ?? false,
          storageVerified: true,
          mapped: true,
          mappingStatus: PhotoMappingStatus.mapped,
          retryable: false,
          repairable: false,
        ),
      );
    }
    guard();
    draft = await _inactiveState(
      draft.copyWith(photos: refs, remoteStatus: 'inactive'),
      RvInactiveClosureSyncStatus.remoteVerified,
    );
    await drafts.visualRepository.documents.flush();
    return draft;
  }
}
