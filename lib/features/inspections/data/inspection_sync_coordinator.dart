import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:hive_ce/hive.dart';
import 'package:uuid/uuid.dart';

import '../../../core/network/api_exception.dart';
import '../../../domain/media/inspection_photo.dart';
import '../../../domain/media/media_sync_status.dart';
import '../../../domain/media/photo_integrity_status.dart';
import '../../catalogs/dynamic_catalog_repository.dart';
import '../domain/rv_draft.dart';
import '../domain/rv_sync_state.dart';
import '../domain/rv_versioning.dart';
import '../domain/rv_validator.dart';
import '../domain/hydrant_account_identity.dart';
import 'inspection_remote_repository.dart';
import 'rv_answer_payload_builder.dart';
import 'rv_draft_repository.dart';

@visibleForTesting
int matchingRemotePhotoIndex({
  required List<RvPhotoReference> references,
  required RemotePhoto remotePhoto,
  required InspectionPhoto? Function(String id) localPhoto,
}) {
  final direct = references.indexWhere(
    (reference) =>
        reference.serverPhotoId == remotePhoto.id ||
        reference.photoId == remotePhoto.id,
  );
  if (direct >= 0) return direct;

  final hashMatches = <int>[];
  for (var index = 0; index < references.length; index++) {
    final local = localPhoto(references[index].photoId);
    if (local == null) continue;
    final localHashes = {
      local.sha256.toLowerCase(),
      if (local.remoteSha256 != null) local.remoteSha256!.toLowerCase(),
    };
    final remoteHashes = {
      if (remotePhoto.clientSha256 != null)
        remotePhoto.clientSha256!.toLowerCase(),
      if (remotePhoto.sha256 != null) remotePhoto.sha256!.toLowerCase(),
    };
    if (localHashes.intersection(remoteHashes).isNotEmpty) {
      hashMatches.add(index);
    }
  }
  return hashMatches.length == 1 ? hashMatches.single : -1;
}

@visibleForTesting
bool shouldReuploadForIntegrity(RemotePhotoIntegrity result) =>
    result.status == PhotoIntegrityStatus.notFound ||
    (const {
          PhotoIntegrityStatus.missingOriginal,
          PhotoIntegrityStatus.hashMismatch,
          PhotoIntegrityStatus.notVerified,
        }.contains(result.status) &&
        result.retryable);

class EvidenceReconciliationSummary {
  const EvidenceReconciliationSummary({
    required this.draft,
    required this.total,
    required this.confirmed,
    required this.pending,
    required this.missingServer,
    required this.missingMapping,
    required this.retryRequired,
    required this.failed,
  });

  final RvDraft draft;
  final int total,
      confirmed,
      pending,
      missingServer,
      missingMapping,
      retryRequired,
      failed;
}

class InspectionSyncCoordinator {
  InspectionSyncCoordinator({
    required this.drafts,
    required this.remote,
    required this.photoBox,
    required this.mediaQueue,
    this.mediaWorkQueue,
    this.diagnosticsBox,
    this.appVersion,
    this.appBuild,
    this.gitSha,
    this.buildDateUtc,
    this.catalogs,
    this.onHydrantResolved,
    this.validator = const RvValidator(),
  });
  final RvDraftRepository drafts;
  final InspectionRemoteRepository remote;
  final Box<String> photoBox, mediaQueue;
  final Box<String>? mediaWorkQueue;
  final Box<String>? diagnosticsBox;
  final String? appVersion, appBuild;
  final String? gitSha, buildDateUtc;
  final DynamicCatalogRepository? catalogs;
  final Future<void> Function(String localId, String serverId)?
  onHydrantResolved;
  final RvValidator validator;
  RvAnswerPayloadBuilder get _payloadBuilder =>
      RvAnswerPayloadBuilder(validator: validator);
  final Set<String> _running = {};
  final Map<String, Map<String, Object?>> failureDiagnostics = {};

  bool isRunning(String id) => _running.contains(id);

  Future<RvDraft> synchronize(
    RvDraft initial, {
    bool submit = false,
    bool forceRetry = false,
  }) async {
    if ((initial.localStatus == RvLocalStatus.conflict &&
            initial.serverInspectionId == null) ||
        initial.localStatus == RvLocalStatus.versionConflict ||
        (initial.localStatus == RvLocalStatus.submitted &&
            !initial.hasPendingChanges &&
            !_hasUnconfirmedEvidence(initial)) ||
        initial.localStatus == RvLocalStatus.cancelled) {
      return initial;
    }
    if (!forceRetry &&
        initial.localStatus == RvLocalStatus.syncError &&
        initial.nextRetryAt == null &&
        initial.lastAttemptAt != null &&
        !initial.updatedAt.isAfter(initial.lastAttemptAt!)) {
      _debug(initial, 'omitido', 'error determinista sin cambios');
      return initial;
    }
    if (!_running.add(initial.clientInspectionId))
      return drafts.find(initial.clientInspectionId) ?? initial;
    var draft = drafts.find(initial.clientInspectionId) ?? initial;
    final retryingLegacyConflict =
        draft.serverInspectionId != null &&
        draft.conflictId != null &&
        draft.remoteStatus == 'conflict';
    if (draft.localStatus == RvLocalStatus.conflict &&
        draft.serverInspectionId != null) {
      // Conflicts created by the former one-review-per-hydrant rule are
      // retryable submissions now that every clientInspectionId represents an
      // independent revision.
      draft = await _save(
        draft.copyWith(
          localStatus: RvLocalStatus.submitPending,
          submitStatus: RvPartStatus.pending,
          clearError: true,
          clearNextRetryAt: true,
        ),
      );
    }
    _debug(draft, 'inicio', submit ? 'submit solicitado' : 'sincronización');
    try {
      if (retryingLegacyConflict) {
        // The legacy server row is permanently locked. Preserve it as history,
        // clone the complete local capture under a fresh clientInspectionId and
        // submit that clone as an independent additional revision.
        final revision = await drafts.migrateConflictToAdditionalRevision(
          draft,
        );
        return synchronize(revision, submit: true, forceRetry: true);
      }
      if (draft.visualReportId != null && draft.hasPendingChanges) {
        return await _synchronizeVersion(draft);
      }
      draft = await _synchronizeCatalogs(draft);
      if (draft.serverInspectionId != null) {
        final remoteInspection = await remote.get(draft.serverInspectionId!);
        draft = (await reconcileInspectionEvidence(draft)).draft;
        draft = await _reconcileRemoteInspection(
          draft,
          remoteInspection: remoteInspection,
        );
        if (draft.isReadOnly) return draft;
      }
      draft = await _create(draft);
      draft = await _photos(draft);
      draft = (await reconcileInspectionEvidence(draft)).draft;
      if (_generalPhotosReady(draft)) {
        await remote.saveGeneralContent(draft);
      }
      draft = await _answers(draft);
      if (draft.parcelValveConfiguration != null) {
        await remote.saveParcelValves(
          draft.serverInspectionId!,
          draft.parcelValveConfiguration!,
        );
      }
      if (draft.location != null) draft = await _location(draft);
      if (draft.signal != null) draft = await _signal(draft);
      final localValidation = validator.validate(draft);
      if (localValidation.isValid && draft.photosVerified) {
        draft = await _save(
          draft.copyWith(
            localStatus: RvLocalStatus.readyToSubmit,
            clearError: true,
          ),
        );
      }
      if (submit) draft = await _submit(draft);
      if (draft.serverInspectionId != null && submit) {
        final confirmed = await remote.get(draft.serverInspectionId!);
        draft = await _reconcileRemoteInspection(
          draft,
          remoteInspection: confirmed,
        );
      }
      if (draft.localStatus == RvLocalStatus.syncError) {
        final validation = validator.validate(draft);
        draft = await _save(
          draft.copyWith(
            localStatus: validation.isValid && draft.photosVerified
                ? RvLocalStatus.readyToSubmit
                : draft.photosVerified
                ? RvLocalStatus.created
                : RvLocalStatus.pendingPhotos,
            clearError: true,
            retryCount: 0,
            clearNextRetryAt: true,
          ),
        );
      }
      _debug(draft, 'fin', draft.localStatus.name);
      return draft;
    } on ApiException catch (error, stackTrace) {
      return _failure(draft, error, stackTrace: stackTrace);
    } on Object catch (error, stackTrace) {
      return _failure(
        draft,
        ApiException(
          ApiErrorKind.unknown,
          'Ocurrió un error inesperado durante la sincronización.',
          originalRuntimeType: error.runtimeType.toString(),
          originalMessage: '$error',
        ),
        stackTrace: stackTrace,
      );
    } finally {
      _running.remove(initial.clientInspectionId);
    }
  }

  Future<RvDraft> _reconcileRemoteInspection(
    RvDraft draft, {
    RemoteInspection? remoteInspection,
  }) async {
    remoteInspection ??= await remote.get(draft.serverInspectionId!);
    if (draft.serverHydrantId == null &&
        remoteInspection.hydrantId?.isNotEmpty == true) {
      await onHydrantResolved?.call(
        draft.hydrantId,
        remoteInspection.hydrantId!,
      );
      draft = await _save(
        draft.copyWith(
          serverHydrantId: remoteInspection.hydrantId,
          recoveryStatus: 'remote_hydrant_backfilled',
        ),
      );
    }
    if (const {'submitted', 'validated'}.contains(remoteInspection.status)) {
      return _save(
        draft.copyWith(
          localStatus: RvLocalStatus.submitted,
          remoteStatus: remoteInspection.status,
          officialInspectionId:
              remoteInspection.officialInspectionId ?? remoteInspection.id,
          lastStatusChangedAt: remoteInspection.lastStatusChangedAt,
          submitStatus: RvPartStatus.synced,
          currentStep: RvSyncStep.verify,
          clearError: true,
          retryCount: 0,
          clearNextRetryAt: true,
        ),
      );
    }
    if (remoteInspection.status == 'conflict') {
      return _save(
        draft.copyWith(
          localStatus: RvLocalStatus.readyToSubmit,
          remoteStatus: 'conflict',
          officialInspectionId: remoteInspection.officialInspectionId,
          conflictId: remoteInspection.conflictId,
          submitStatus: RvPartStatus.pending,
          currentStep: RvSyncStep.submit,
          clearError: true,
          clearNextRetryAt: true,
        ),
      );
    }
    return draft;
  }

  Future<RvDraft> _synchronizeVersion(RvDraft draft) async {
    draft = await _save(
      draft.copyWith(
        localStatus: RvLocalStatus.syncingVersion,
        clearError: true,
      ),
    );
    draft = await _photos(draft);
    draft = await _reconcilePhotos(draft);
    final generalReady = draft.generalPhotos.every(
      (photo) => photo.status == RvPhotoUploadStatus.verified,
    );
    if (!generalReady) {
      return _save(
        draft.copyWith(
          localStatus: RvLocalStatus.pendingVersion,
          lastSyncError:
              'Las fotografías generales seleccionadas siguen pendientes de sincronización.',
        ),
      );
    }
    await remote.saveGeneralContent(draft);
    final result = await remote.createVersion(draft);
    switch (result.kind) {
      case RvVersionResultKind.created:
      case RvVersionResultKind.alreadyCreated:
        return _save(
          draft.copyWith(
            localStatus: RvLocalStatus.submitted,
            currentVersionId: result.currentVersionId ?? result.versionId,
            baseVersionId: result.currentVersionId ?? result.versionId,
            baseVersionNumber: result.versionNumber,
            hasPendingChanges: false,
            clearError: true,
            retryCount: 0,
            clearNextRetryAt: true,
          ),
        );
      case RvVersionResultKind.conflict:
        return _save(
          draft.copyWith(
            localStatus: RvLocalStatus.versionConflict,
            versionConflictId: result.conflictId,
            proposedVersionId: result.proposedVersionId,
            currentVersionId: result.currentVersionId,
            hasPendingChanges: true,
            clearError: true,
            clearNextRetryAt: true,
          ),
        );
      case RvVersionResultKind.forbiddenAfterValidation:
        return _save(
          draft.copyWith(
            localStatus: RvLocalStatus.pendingVersion,
            editingMode: RvEditingMode.validatedComplements,
            serverValidationStatus: 'validated',
            hasPendingChanges: true,
            lastSyncError:
                'El diagnóstico fue validado; conserva solo observaciones y fotos generales.',
            clearNextRetryAt: true,
          ),
        );
    }
  }

  Future<RvDraft> _synchronizeCatalogs(RvDraft draft) async {
    final repository = catalogs;
    if (repository == null) return draft;
    await repository.synchronizePending();
    var changed = false;
    final answers = <String, RvAnswer>{...draft.answers};
    for (final entry in answers.entries) {
      final answer = entry.value;
      if (answer.value is! Map) continue;
      final value = Map<String, dynamic>.from(answer.value! as Map);
      if (value['catalogId'] != null) continue;
      final remoteId = repository.remoteIdFor(
        value['localCatalogId']?.toString() ?? '',
      );
      if (remoteId == null) continue;
      changed = true;
      answers[entry.key] = RvAnswer(
        questionId: answer.questionId,
        sectionId: answer.sectionId,
        answerType: answer.answerType,
        value: {...value, 'catalogId': remoteId, 'isPendingSync': false},
        selectedOptions: answer.selectedOptions,
        notApplicable: answer.notApplicable,
        comment: answer.comment,
        updatedAt: DateTime.now().toUtc(),
      );
    }
    var configuration = draft.parcelValveConfiguration;
    if (configuration != null) {
      Map<String, dynamic>? reconcile(Map<String, dynamic>? value) {
        if (value == null || value['catalogId'] != null) return value;
        final remoteId = repository.remoteIdFor(
          value['localCatalogId']?.toString() ?? '',
        );
        if (remoteId == null) return value;
        changed = true;
        return {...value, 'catalogId': remoteId, 'isPendingSync': false};
      }

      configuration = configuration.copyWith(
        valves: [
          for (final valve in configuration.valves)
            valve.copyWith(
              valveBrand: reconcile(valve.valveBrand),
              diameter: reconcile(valve.diameter),
              solenoidBrand: reconcile(valve.solenoidBrand),
              pilotBrand: reconcile(valve.pilotBrand),
              pressureGaugeBrand: reconcile(valve.pressureGaugeBrand),
            ),
        ],
      );
    }
    if (!changed) return draft;
    final reconciled = draft.copyWith(
      answers: answers,
      parcelValveConfiguration: configuration,
      answersStatus: RvPartStatus.pending,
    );
    await drafts.save(reconciled);
    return reconciled;
  }

  Future<RvDraft> _create(RvDraft draft) async {
    if (draft.serverInspectionId != null) return draft;
    draft = await _save(
      draft.copyWith(
        localStatus: RvLocalStatus.creating,
        currentStep: RvSyncStep.create,
        lastAttemptAt: DateTime.now().toUtc(),
      ),
    );
    // Repeating the same clientInspectionId is the only creation reconciliation
    // exposed by the API and returns the existing row without duplication.
    late final RemoteInspection created;
    try {
      created = await remote.create(draft);
    } on ApiException catch (error) {
      if (!_isObjectiveHyphenIncompatibility(draft, error)) rethrow;
      final alias = transformLegacyHyphenAccount(draft.originalAccountNumber);
      final collision = await remote.findHydrantByAccount(alias);
      if (collision != null) {
        await _save(
          draft.copyWith(
            accountResolutionState:
                AccountResolutionState.unresolvedAccountCollision,
            recoveryStatus: 'accountAliasCollision',
            accountResolutionAttempts: [
              ...draft.accountResolutionAttempts,
              'create_original:hyphen_incompatible',
              'lookup_alias:collision',
            ],
          ),
        );
        throw const ApiException(
          ApiErrorKind.validation,
          'La cuenta alternativa coincide con otro hidrante. Tus datos se conservaron para conciliación.',
          domainCode: 'ACCOUNT_ALIAS_COLLISION',
        );
      }
      final transformed = draft.copyWith(
        effectiveAccountNumber: alias,
        accountTransformation: AccountTransformation.hyphenTo000,
        accountTransformationVersion: 1,
        accountTransformedAt: DateTime.now().toUtc(),
        accountResolutionState: AccountResolutionState.transformed,
        accountResolutionAttempts: [
          ...draft.accountResolutionAttempts,
          'create_original:hyphen_incompatible',
          'lookup_alias:not_found',
          'create_alias:attempt',
        ],
      );
      await _save(transformed);
      created = await remote.create(transformed);
      draft = transformed;
    }
    final serverHydrantId = created.hydrantId;
    if (serverHydrantId != null && serverHydrantId.isNotEmpty) {
      await onHydrantResolved?.call(draft.hydrantId, serverHydrantId);
    }
    _debug(draft, 'creación', 'confirmada');
    return _save(
      draft.copyWith(
        serverInspectionId: created.id,
        serverHydrantId: serverHydrantId,
        remoteStatus: created.status,
        localStatus: RvLocalStatus.created,
        currentStep: RvSyncStep.answers,
        clearError: true,
      ),
    );
  }

  bool _isObjectiveHyphenIncompatibility(RvDraft draft, ApiException error) {
    if (!draft.originalAccountNumber.contains('-')) return false;
    return const {
      'ACCOUNT_HYPHEN_UNSUPPORTED',
      'INVALID_ACCOUNT_FORMAT_HYPHEN',
    }.contains(error.domainCode);
  }

  Future<RvDraft> _answers(RvDraft draft) async {
    if (draft.answersStatus == RvPartStatus.synced) return draft;
    final id = draft.serverInspectionId!;
    late final List<Map<String, dynamic>> payload;
    try {
      payload = _payloadBuilder.build(draft);
    } on RvPayloadException catch (error) {
      throw ApiException(
        ApiErrorKind.validation,
        error.message,
        field: error.questionId,
      );
    }
    draft = await _save(
      draft.copyWith(
        answersStatus: RvPartStatus.syncing,
        localStatus: RvLocalStatus.pendingAnswers,
        currentStep: RvSyncStep.answers,
      ),
    );
    await remote.saveAnswers(
      id,
      payload,
      'answers-${draft.clientInspectionId}-${draft.updatedAt.microsecondsSinceEpoch}',
    );
    _debug(draft, 'respuestas', '${payload.length} sincronizadas');
    return _save(
      draft.copyWith(
        answersStatus: RvPartStatus.synced,
        currentStep: RvSyncStep.location,
        clearError: true,
      ),
    );
  }

  Future<RvDraft> _location(RvDraft draft) async {
    if (draft.locationStatus == RvPartStatus.synced) return draft;
    draft = await _save(
      draft.copyWith(
        locationStatus: RvPartStatus.syncing,
        localStatus: RvLocalStatus.pendingLocation,
        currentStep: RvSyncStep.location,
      ),
    );
    await remote.saveLocation(
      draft.serverInspectionId!,
      draft.location!,
      'location-${draft.clientInspectionId}-${draft.location!.capturedAt.microsecondsSinceEpoch}',
    );
    _debug(draft, 'ubicación', 'sincronizada');
    return _save(
      draft.copyWith(
        locationStatus: RvPartStatus.synced,
        currentStep: RvSyncStep.signal,
        clearError: true,
      ),
    );
  }

  Future<RvDraft> _signal(RvDraft draft) async {
    if (draft.signalStatus == RvPartStatus.synced) return draft;
    draft = await _save(
      draft.copyWith(
        signalStatus: RvPartStatus.syncing,
        localStatus: RvLocalStatus.pendingSignal,
        currentStep: RvSyncStep.signal,
      ),
    );
    await remote.saveSignal(
      draft.serverInspectionId!,
      draft.signal!,
      'signal-${draft.clientInspectionId}-${draft.signal!.capturedAt.microsecondsSinceEpoch}',
    );
    _debug(draft, 'señal', 'sincronizada');
    return _save(
      draft.copyWith(
        signalStatus: RvPartStatus.synced,
        currentStep: RvSyncStep.photos,
        clearError: true,
      ),
    );
  }

  Future<RvDraft> _photos(RvDraft draft) async {
    var refs = <String, List<RvPhotoReference>>{...draft.photos};
    for (final slot in refs.keys.toList()) {
      final slotRefs = [...draft.photosFor(slot)];
      for (var index = 0; index < slotRefs.length; index++) {
        var ref = slotRefs[index];
        if (ref.status == RvPhotoUploadStatus.verified) continue;
        var photo = _photo(ref.photoId);
        if (photo != null &&
            (photo.syncStatus == MediaSyncStatus.uploadedUnverified ||
                photo.syncStatus == MediaSyncStatus.verified)) {
          // A prior server receipt must be cross-checked before deciding that
          // bytes need to be sent again. This protects legacy evidence and the
          // capability-fallback rollout from mass reuploads.
          continue;
        }
        if (photo != null && photo.inspectionId != draft.clientInspectionId) {
          final newPhotoId = const Uuid().v4();
          final clonedJson = Map<String, dynamic>.from(photo.toJson())
            ..['id'] = newPhotoId
            ..['inspectionId'] = draft.clientInspectionId
            ..['syncStatus'] = MediaSyncStatus.pendingUpload.name
            ..['uploadAttempts'] = 0
            ..['uploadedAt'] = null
            ..['verifiedAt'] = null
            ..['remoteObjectKey'] = null
            ..['remoteSha256'] = null
            ..['remoteFileSize'] = null
            ..['lastError'] = null
            ..['updatedAt'] = DateTime.now().toUtc().toIso8601String();
          photo = InspectionPhoto.fromJson(clonedJson);
          await photoBox.put(newPhotoId, jsonEncode(photo.toJson()));
          await mediaQueue.put(newPhotoId, MediaSyncStatus.pendingUpload.name);
          ref = RvPhotoReference(
            photoId: newPhotoId,
            slotCode: ref.slotCode,
            status: RvPhotoUploadStatus.pending,
            retryCount: 0,
            order: ref.order,
            description: ref.description,
          );
          slotRefs[index] = ref;
          refs[slot] = slotRefs;
          draft = await _save(draft.copyWith(photos: refs));
        }
        if (photo == null || !await File(photo.localPath).exists()) {
          const message =
              'No se encontró el archivo local; no fue posible consultar/subir esta evidencia.';
          slotRefs[index] = RvPhotoReference(
            photoId: ref.photoId,
            slotCode: slot,
            status: RvPhotoUploadStatus.missingLocal,
            retryCount: ref.retryCount,
            lastError: message,
            order: ref.order,
            description: ref.description,
          );
          if (photo != null) {
            await _markPhotoFailure(
              photo,
              message,
              retryable: false,
              attempt: ref.retryCount + 1,
            );
          }
          refs[slot] = slotRefs;
          continue;
        }
        slotRefs[index] = RvPhotoReference(
          photoId: ref.photoId,
          slotCode: slot,
          status: RvPhotoUploadStatus.uploading,
          retryCount: ref.retryCount,
          order: ref.order,
          description: ref.description,
        );
        refs[slot] = slotRefs;
        draft = await _save(
          draft.copyWith(
            photos: refs,
            photosStatus: RvPartStatus.syncing,
            localStatus: RvLocalStatus.pendingPhotos,
            currentStep: RvSyncStep.photos,
          ),
        );
        try {
          _debug(draft, 'fotografía', 'subiendo slot=$slot');
          final uploaded = await remote.uploadPhoto(
            draft.serverInspectionId!,
            slot,
            photo,
          );
          slotRefs[index] = RvPhotoReference(
            photoId: ref.photoId,
            serverPhotoId: uploaded.id,
            slotCode: slot,
            status: RvPhotoUploadStatus.pending,
            retryCount: ref.retryCount,
            order: ref.order,
            description: ref.description,
          );
          await _markPhotoUploadedUnverified(
            photo,
            uploaded.sha256,
            serverPhotoId: uploaded.id,
          );
          _debug(
            draft,
            'fotografía',
            'recibida; confirmación pendiente slot=$slot',
          );
        } on ApiException catch (error) {
          final technicalError = _photoErrorDetail(error);
          slotRefs[index] = RvPhotoReference(
            photoId: ref.photoId,
            slotCode: slot,
            status: RvPhotoUploadStatus.error,
            retryCount: ref.retryCount + 1,
            lastError: technicalError,
            order: ref.order,
            description: ref.description,
          );
          await _markPhotoFailure(
            photo,
            technicalError,
            retryable: _retryable(error),
            attempt: ref.retryCount + 1,
          );
        }
        refs[slot] = slotRefs;
        draft = await _save(draft.copyWith(photos: refs));
      }
    }
    final complete =
        requiredRvPhotoSlots.every(
          (slot) => (refs[slot] ?? const []).any(
            (photo) => photo.status == RvPhotoUploadStatus.verified,
          ),
        ) &&
        refs.values
            .expand((items) => items)
            .every((photo) => photo.status == RvPhotoUploadStatus.verified);
    return _save(
      draft.copyWith(
        photos: refs,
        photosStatus: complete ? RvPartStatus.synced : RvPartStatus.pending,
        currentStep: RvSyncStep.reconcile,
      ),
    );
  }

  Future<EvidenceReconciliationSummary> reconcileInspectionEvidence(
    RvDraft draft,
  ) async {
    final reconciled = await _reconcilePhotos(draft);
    final photos = reconciled.photos.values
        .expand((items) => items)
        .map((reference) => _photo(reference.photoId))
        .whereType<InspectionPhoto>()
        .toList(growable: false);
    int count(PhotoIntegrityStatus status) =>
        photos.where((photo) => photo.integrityStatus == status).length;
    final confirmed = count(PhotoIntegrityStatus.confirmed);
    final failed = photos
        .where((photo) => photo.integrityStatus.requiresReview)
        .length;
    return EvidenceReconciliationSummary(
      draft: reconciled,
      total: photos.length,
      confirmed: confirmed,
      pending: photos.length - confirmed - failed,
      missingServer:
          count(PhotoIntegrityStatus.notFound) +
          count(PhotoIntegrityStatus.missingOriginal),
      missingMapping: count(PhotoIntegrityStatus.missingMapping),
      retryRequired: photos
          .where((photo) => photo.integrityRetryable == true)
          .length,
      failed: failed,
    );
  }

  Future<RvDraft> _reconcilePhotos(RvDraft draft) async {
    final refs = <String, List<RvPhotoReference>>{...draft.photos};
    final allRefs = refs.values.expand((items) => items).toList();
    final now = DateTime.now().toUtc();
    final dueRefs = allRefs.where((ref) {
      final photo = _photo(ref.photoId);
      if (photo?.integrityStatus.isConfirmed == true) return false;
      if (photo?.integrityStatus.requiresReview == true) return false;
      final retryAt = photo?.nextIntegrityRetryAt;
      return retryAt == null || !retryAt.isAfter(now);
    }).toList();
    final byServerId = {
      for (final ref in dueRefs) ref.serverPhotoId ?? ref.photoId: ref,
    };
    final results = <RemotePhotoIntegrity>[];
    try {
      final ids = byServerId.keys.toList();
      for (var start = 0; start < ids.length; start += 100) {
        final end = min(start + 100, ids.length);
        results.addAll(await remote.verifyPhotosBatch(ids.sublist(start, end)));
      }
    } on ApiException catch (error) {
      if (error.statusCode == 404 || error.statusCode == 405) {
        await _markIntegrityCapabilityUnavailable(dueRefs);
        _debug(
          draft,
          'verificación',
          'capability no disponible; evidencia conservada',
        );
        return _save(
          draft.copyWith(photos: _pendingUnconfirmedReferences(refs)),
        );
      }
      rethrow;
    }
    final returned = <String>{};
    for (final result in results) {
      returned.add(result.photoId);
      final ref = byServerId[result.photoId];
      if (ref == null) continue;
      var effective = result;
      final local = _photo(ref.photoId);
      if (shouldReuploadForIntegrity(result) &&
          local != null &&
          !local.isDeleted &&
          await File(local.localPath).exists()) {
        final uploaded = await remote.uploadPhoto(
          draft.serverInspectionId!,
          ref.slotCode,
          local,
        );
        await _markPhotoUploadedUnverified(
          local,
          uploaded.sha256,
          serverPhotoId: uploaded.id,
        );
        final verified = await remote.verifyPhotosBatch([uploaded.id]);
        if (verified.isNotEmpty) effective = verified.single;
      }
      await _applyIntegrityResult(ref.photoId, effective);
      final slotRefs = <RvPhotoReference>[
        ...(refs[ref.slotCode] ?? const <RvPhotoReference>[]),
      ];
      final index = slotRefs.indexWhere((item) => item.photoId == ref.photoId);
      if (index >= 0) {
        slotRefs[index] = RvPhotoReference(
          photoId: ref.photoId,
          serverPhotoId: result.photoId,
          slotCode: ref.slotCode,
          status: effective.status.isConfirmed
              ? RvPhotoUploadStatus.verified
              : RvPhotoUploadStatus.pending,
          retryCount: ref.retryCount,
          lastError: effective.status.requiresReview
              ? 'Esta evidencia requiere revisión.'
              : null,
          order: ref.order,
          description: ref.description,
        );
        refs[ref.slotCode] = slotRefs;
      }
    }
    for (final entry in byServerId.entries) {
      if (!returned.contains(entry.key)) {
        await _markIntegrityRetryRequired(entry.value.photoId);
      }
    }
    final complete =
        requiredRvPhotoSlots.every(
          (slot) => (refs[slot] ?? const []).any(
            (photo) => photo.status == RvPhotoUploadStatus.verified,
          ),
        ) &&
        refs.values
            .expand((items) => items)
            .every((photo) => photo.status == RvPhotoUploadStatus.verified);
    return _save(
      draft.copyWith(
        photos: refs,
        photosStatus: complete ? RvPartStatus.synced : RvPartStatus.pending,
        currentStep: draft.isReadOnly ? draft.currentStep : RvSyncStep.submit,
      ),
    );
  }

  bool _hasUnconfirmedEvidence(RvDraft draft) => draft.photos.values
      .expand((items) => items)
      .any((reference) => _photo(reference.photoId)?.isSynchronized != true);

  Map<String, List<RvPhotoReference>> _pendingUnconfirmedReferences(
    Map<String, List<RvPhotoReference>> refs,
  ) => {
    for (final entry in refs.entries)
      entry.key: [
        for (final ref in entry.value)
          RvPhotoReference(
            photoId: ref.photoId,
            serverPhotoId: ref.serverPhotoId,
            slotCode: ref.slotCode,
            status: _photo(ref.photoId)?.integrityStatus.isConfirmed == true
                ? RvPhotoUploadStatus.verified
                : RvPhotoUploadStatus.pending,
            retryCount: ref.retryCount,
            lastError: ref.lastError,
            order: ref.order,
            description: ref.description,
          ),
      ],
  };

  Future<RvDraft> _submit(RvDraft draft) async {
    final validation = validator.validate(draft, requireSynced: true);
    if (!validation.isValid) {
      throw ApiException(
        ApiErrorKind.validation,
        validation.issues.first.message,
      );
    }
    draft = await _save(
      draft.copyWith(
        localStatus: RvLocalStatus.submitting,
        submitStatus: RvPartStatus.syncing,
        currentStep: RvSyncStep.submit,
      ),
    );
    final result = await remote.submit(draft.serverInspectionId!);
    if (result.result == 'conflict') {
      _debug(
        draft,
        'submit',
        'enviado; conciliación administrativa persistida',
      );
      return _save(
        draft.copyWith(
          localStatus: RvLocalStatus.submitted,
          remoteStatus: 'submitted',
          submitStatus: RvPartStatus.synced,
          officialInspectionId: result.officialInspectionId,
          conflictId: result.conflictId,
          lastStatusChangedAt: result.lastStatusChangedAt,
          currentStep: RvSyncStep.verify,
          retryCount: 0,
          clearNextRetryAt: true,
          clearError: true,
        ),
      );
    }
    final accepted =
        result.result == 'official' ||
        result.result == 'already_official' ||
        result.status == 'submitted';
    if (!accepted) {
      throw const ApiException(
        ApiErrorKind.serverUnavailable,
        'No fue posible confirmar el envío.',
      );
    }
    _debug(draft, 'submit', 'confirmado por servidor');
    return _save(
      draft.copyWith(
        localStatus: RvLocalStatus.submitted,
        remoteStatus: result.status,
        officialInspectionId: result.officialInspectionId ?? result.id,
        lastStatusChangedAt: result.lastStatusChangedAt,
        submitStatus: RvPartStatus.synced,
        currentStep: RvSyncStep.verify,
        clearError: true,
        retryCount: 0,
        clearNextRetryAt: true,
      ),
    );
  }

  Future<RvDraft> _failure(
    RvDraft draft,
    ApiException error, {
    StackTrace? stackTrace,
  }) async {
    const retryCap = 8;
    final retry = min(draft.retryCount + 1, retryCap);
    final failedAt = DateTime.now().toUtc();
    final retryable = _retryable(error);
    final delay = error.retryAfter ?? _backoff(retry);
    final retryScheduled = retryable && retry < retryCap;
    _debug(
      draft,
      'error',
      '${error.kind.name}; retryable=$retryable; intento=$retry '
          'requestId=${error.requestId ?? '-'} field=${error.field ?? '-'}',
    );
    failureDiagnostics[draft.clientInspectionId] = {
      'accountNumber': draft.accountNumber,
      'hydrantId': draft.hydrantId,
      'clientInspectionId': draft.clientInspectionId,
      'serverInspectionId': draft.serverInspectionId,
      'step': draft.currentStep.name,
      'kind': error.kind.name,
      'statusCode': error.statusCode,
      'httpMethod': error.httpMethod,
      'logicalEndpoint': error.logicalEndpoint,
      'retryAfterSeconds': error.retryAfter?.inSeconds,
      'dioExceptionType': error.dioExceptionType,
      'requestId': error.requestId,
      'domainCode': error.domainCode,
      'field': error.field,
      'runtimeType': error.originalRuntimeType ?? error.runtimeType.toString(),
      'message': error.originalMessage ?? error.message,
      'stackTrace': stackTrace?.toString(),
      'timestampUtc': failedAt.toIso8601String(),
      'localStatusBefore': draft.localStatus.name,
      'retryCount': retry,
      'appVersion': appVersion,
      'appBuild': appBuild,
      'gitSha': gitSha,
      'buildDateUtc': buildDateUtc,
    };
    final diagnostic = failureDiagnostics[draft.clientInspectionId]!;
    await diagnosticsBox?.put(
      '${failedAt.microsecondsSinceEpoch}-${draft.clientInspectionId}',
      jsonEncode(diagnostic),
    );
    final failedDraft = draft.copyWith(
      localStatus: error.kind == ApiErrorKind.sessionRevoked
          ? RvLocalStatus.requiresAuthentication
          : RvLocalStatus.syncError,
      lastSyncError: retryable ? _retryMessage(error) : error.message,
      retryCount: retry,
      lastAttemptAt: failedAt,
      updatedAt: failedAt,
      nextRetryAt: retryScheduled ? DateTime.now().toUtc().add(delay) : null,
      recoveryStatus: retryable && !retryScheduled
          ? 'requiresRemoteReconciliation'
          : draft.recoveryStatus,
    );
    try {
      return await _save(failedDraft);
    } on StateError catch (saveError) {
      // A remote submit may have completed while the client timed out. The
      // local visual document is then immutable by design. Diagnostics above
      // are already durable; do not abort the remaining synchronization queue
      // merely because failure metadata cannot be embedded in that document.
      if ('$saveError'.contains('finalizado es inmutable')) return failedDraft;
      rethrow;
    }
  }

  bool _retryable(ApiException error) => const {
    ApiErrorKind.offline,
    ApiErrorKind.timeout,
    ApiErrorKind.serverUnavailable,
    ApiErrorKind.rateLimited,
    ApiErrorKind.serverError,
  }.contains(error.kind);

  String _retryMessage(ApiException error) => switch (error.kind) {
    ApiErrorKind.timeout =>
      'El servidor tardó demasiado en responder. La revisión quedó '
          'guardada en el dispositivo y se reintentará en segundo plano.',
    ApiErrorKind.serverError =>
      'El servidor respondió con un error. La revisión quedó guardada '
          'en el dispositivo y se reintentará en segundo plano.',
    ApiErrorKind.rateLimited =>
      'El servidor pidió pausar temporalmente la sincronización. Tus datos '
          'permanecen guardados. Código: RV-NET-429.',
    _ =>
      'No fue posible establecer comunicación con el servidor. La revisión '
          'quedó guardada en el dispositivo y se reintentará en segundo plano.',
  };

  Duration _backoff(int attempt) {
    final exponent = (attempt - 1).clamp(0, 10);
    final baseSeconds = min(3600, 5 * (1 << exponent));
    final jitter = Random().nextInt(max(1, baseSeconds ~/ 4));
    return Duration(seconds: baseSeconds + jitter);
  }

  bool _generalPhotosReady(RvDraft draft) => draft.generalPhotos.every(
    (photo) =>
        photo.status == RvPhotoUploadStatus.verified &&
        photo.serverPhotoId != null &&
        photo.serverPhotoId!.isNotEmpty,
  );
  InspectionPhoto? _photo(String id) {
    final raw = photoBox.get(id);
    if (raw == null) return null;
    try {
      return InspectionPhoto.fromJson(
        Map<String, dynamic>.from(jsonDecode(raw) as Map),
      );
    } on Object {
      return null;
    }
  }

  Future<void> _markPhotoUploadedUnverified(
    InspectionPhoto photo,
    String? remoteHash, {
    String? serverPhotoId,
  }) async {
    final now = DateTime.now().toUtc();
    final updated = InspectionPhoto.fromJson({
      ...photo.toJson(),
      'syncStatus': MediaSyncStatus.uploadedUnverified.name,
      'integrityStatus': PhotoIntegrityStatus.serverConfirmationPending.name,
      'integrityCheckedAt': null,
      'verifiedAt': null,
      'uploadedAt': now.toIso8601String(),
      'remoteObjectKey': serverPhotoId ?? photo.remoteObjectKey ?? photo.id,
      'remoteSha256': remoteHash,
      'updatedAt': now.toIso8601String(),
    });
    await photoBox.put(photo.id, jsonEncode(updated.toJson()));
    await mediaQueue.put(photo.id, MediaSyncStatus.uploadedUnverified.name);
    await (mediaWorkQueue ?? Hive.box<String>('media_work_queue_v1')).put(
      photo.id,
      jsonEncode({
        'photoId': photo.id,
        'status': 'verify',
        'serverPhotoId': serverPhotoId ?? photo.remoteObjectKey ?? photo.id,
        'remoteSha256': remoteHash,
        'reconciledAt': now.toIso8601String(),
        'source': 'upload-response',
      }),
    );
  }

  Future<void> _applyIntegrityResult(
    String localPhotoId,
    RemotePhotoIntegrity result,
  ) async {
    final photo = _photo(localPhotoId);
    if (photo == null) return;
    final now = DateTime.now().toUtc();
    final confirmed = result.status.isConfirmed;
    final attempts = confirmed ? 0 : photo.integrityAttempts + 1;
    final retryAt = !confirmed && result.retryable
        ? now.add(_backoff(attempts))
        : null;
    final updated = InspectionPhoto.fromJson({
      ...photo.toJson(),
      'schemaVersion': 2,
      'syncStatus': confirmed
          ? MediaSyncStatus.verified.name
          : MediaSyncStatus.uploadedUnverified.name,
      'integrityStatus': result.status.name,
      'mappingStatus': result.mappingStatus.name,
      'originalPresent': result.originalPresent,
      'thumbnailPresent': result.thumbnailPresent,
      'integrityRetryable': result.retryable,
      'integrityRepairable': result.repairable,
      'integrityAttempts': attempts,
      'integrityCheckedAt': now.toIso8601String(),
      'nextIntegrityRetryAt': retryAt?.toIso8601String(),
      'verifiedAt': confirmed ? now.toIso8601String() : null,
      'remoteSha256': result.serverSha256 ?? photo.remoteSha256,
      'lastError': result.status.requiresReview
          ? 'Esta evidencia requiere revisión.'
          : null,
      'updatedAt': now.toIso8601String(),
    });
    await photoBox.put(localPhotoId, jsonEncode(updated.toJson()));
    await mediaQueue.put(
      localPhotoId,
      confirmed ? MediaSyncStatus.verified.name : 'verify',
    );
    await (mediaWorkQueue ?? Hive.box<String>('media_work_queue_v1')).put(
      localPhotoId,
      jsonEncode({
        'photoId': localPhotoId,
        'status': confirmed
            ? MediaSyncStatus.verified.name
            : result.status.requiresReview
            ? 'requiresReview'
            : 'verify',
        'integrityStatus': result.status.name,
        'retryCount': attempts,
        'lastAttemptAt': now.toIso8601String(),
        'nextRetryAt': retryAt?.toIso8601String(),
      }),
    );
  }

  Future<void> _markIntegrityCapabilityUnavailable(
    Iterable<RvPhotoReference> references,
  ) async {
    for (final reference in references) {
      final photo = _photo(reference.photoId);
      if (photo == null || photo.integrityStatus.isConfirmed) continue;
      final now = DateTime.now().toUtc();
      final updated = InspectionPhoto.fromJson({
        ...photo.toJson(),
        'schemaVersion': 2,
        'integrityStatus': PhotoIntegrityStatus.capabilityUnavailable.name,
        'integrityCheckedAt': now.toIso8601String(),
        'nextIntegrityRetryAt': now
            .add(const Duration(hours: 6))
            .toIso8601String(),
        'updatedAt': now.toIso8601String(),
      });
      await photoBox.put(photo.id, jsonEncode(updated.toJson()));
      await mediaQueue.put(photo.id, 'verify');
    }
  }

  Future<void> _markIntegrityRetryRequired(String photoId) async {
    final photo = _photo(photoId);
    if (photo == null || photo.integrityStatus.isConfirmed) return;
    final now = DateTime.now().toUtc();
    final attempts = photo.integrityAttempts + 1;
    final updated = InspectionPhoto.fromJson({
      ...photo.toJson(),
      'integrityStatus': PhotoIntegrityStatus.retryRequired.name,
      'integrityAttempts': attempts,
      'integrityCheckedAt': now.toIso8601String(),
      'nextIntegrityRetryAt': now.add(_backoff(attempts)).toIso8601String(),
      'updatedAt': now.toIso8601String(),
    });
    await photoBox.put(photoId, jsonEncode(updated.toJson()));
    await mediaQueue.put(photoId, 'verify');
  }

  String _photoErrorDetail(ApiException error) {
    final context = <String>[
      if (error.statusCode != null) 'HTTP ${error.statusCode}',
      if (error.domainCode?.isNotEmpty == true) error.domainCode!,
      if (error.logicalEndpoint?.isNotEmpty == true) error.logicalEndpoint!,
      if (error.requestId?.isNotEmpty == true) 'requestId=${error.requestId}',
    ];
    return context.isEmpty
        ? error.message
        : '${error.message} (${context.join(' · ')})';
  }

  Future<void> _markPhotoFailure(
    InspectionPhoto photo,
    String error, {
    required bool retryable,
    required int attempt,
  }) async {
    final now = DateTime.now().toUtc();
    final status = retryable
        ? MediaSyncStatus.failedRetryable
        : MediaSyncStatus.failedPermanent;
    final updated = InspectionPhoto.fromJson({
      ...photo.toJson(),
      'syncStatus': status.name,
      'uploadAttempts': attempt,
      'lastError': error,
      'updatedAt': now.toIso8601String(),
    });
    await photoBox.put(photo.id, jsonEncode(updated.toJson()));
    await mediaQueue.put(photo.id, status.name);
    await (mediaWorkQueue ?? Hive.box<String>('media_work_queue_v1')).put(
      photo.id,
      jsonEncode({
        'photoId': photo.id,
        'status': status.name,
        'retryCount': attempt,
        'lastError': error,
        'lastAttemptAt': now.toIso8601String(),
      }),
    );
  }

  Future<RvDraft> _save(RvDraft value) async {
    await drafts.save(value);
    return value;
  }

  void _debug(RvDraft draft, String step, String detail) {
    if (!kDebugMode) return;
    final id = draft.clientInspectionId.length > 8
        ? draft.clientInspectionId.substring(0, 8)
        : draft.clientInspectionId;
    debugPrint('[RV-SYNC] inspection=$id step=$step $detail');
  }
}

// ignore_for_file: curly_braces_in_flow_control_structures
