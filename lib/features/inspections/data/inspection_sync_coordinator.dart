import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:hive_ce/hive.dart';

import '../../../core/network/api_exception.dart';
import '../../../domain/media/inspection_photo.dart';
import '../../../domain/media/media_sync_status.dart';
import '../../catalogs/dynamic_catalog_repository.dart';
import '../domain/rv_draft.dart';
import '../domain/rv_sync_state.dart';
import '../domain/rv_versioning.dart';
import '../domain/rv_validator.dart';
import 'inspection_remote_repository.dart';
import 'rv_answer_payload_builder.dart';
import 'rv_draft_repository.dart';

class InspectionSyncCoordinator {
  InspectionSyncCoordinator({
    required this.drafts,
    required this.remote,
    required this.photoBox,
    required this.mediaQueue,
    this.catalogs,
    this.validator = const RvValidator(),
  });
  final RvDraftRepository drafts;
  final InspectionRemoteRepository remote;
  final Box<String> photoBox, mediaQueue;
  final DynamicCatalogRepository? catalogs;
  final RvValidator validator;
  RvAnswerPayloadBuilder get _payloadBuilder =>
      RvAnswerPayloadBuilder(validator: validator);
  final Set<String> _running = {};

  bool isRunning(String id) => _running.contains(id);

  Future<RvDraft> synchronize(RvDraft initial, {bool submit = false}) async {
    if (initial.localStatus == RvLocalStatus.conflict ||
        initial.localStatus == RvLocalStatus.versionConflict ||
        (initial.localStatus == RvLocalStatus.submitted &&
            !initial.hasPendingChanges) ||
        initial.localStatus == RvLocalStatus.cancelled) {
      return initial;
    }
    if (initial.localStatus == RvLocalStatus.syncError &&
        initial.nextRetryAt == null &&
        initial.lastAttemptAt != null &&
        !initial.updatedAt.isAfter(initial.lastAttemptAt!)) {
      _debug(initial, 'omitido', 'error determinista sin cambios');
      return initial;
    }
    if (!_running.add(initial.clientInspectionId))
      return drafts.find(initial.clientInspectionId) ?? initial;
    var draft = drafts.find(initial.clientInspectionId) ?? initial;
    _debug(draft, 'inicio', submit ? 'submit solicitado' : 'sincronización');
    try {
      if (draft.visualReportId != null && draft.hasPendingChanges) {
        return await _synchronizeVersion(draft);
      }
      draft = await _synchronizeCatalogs(draft);
      draft = await _create(draft);
      draft = await _photos(draft);
      draft = await _reconcilePhotos(draft);
      await remote.saveGeneralContent(draft);
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
      _debug(draft, 'fin', draft.localStatus.name);
      return draft;
    } on ApiException catch (error) {
      return _failure(draft, error);
    } on TimeoutException {
      return _failure(
        draft,
        const ApiException(
          ApiErrorKind.timeout,
          'El servidor tardó demasiado en responder.',
        ),
      );
    } on SocketException {
      return _failure(
        draft,
        const ApiException(
          ApiErrorKind.serverUnavailable,
          'No fue posible comunicarse con el servidor.',
        ),
      );
    } on Object catch (error, stackTrace) {
      if (kDebugMode) {
        debugPrint('[RV-SYNC] error inesperado ${error.runtimeType}: $error');
        debugPrintStack(stackTrace: stackTrace);
      }
      return _failure(
        draft,
        ApiException(
          ApiErrorKind.unknown,
          'No fue posible completar el envío (${error.runtimeType}).',
        ),
      );
    } finally {
      _running.remove(initial.clientInspectionId);
    }
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
    final created = await remote.create(draft);
    _debug(draft, 'creación', 'confirmada');
    return _save(
      draft.copyWith(
        serverInspectionId: created.id,
        remoteStatus: created.status,
        localStatus: RvLocalStatus.created,
        currentStep: RvSyncStep.answers,
        clearError: true,
      ),
    );
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
        final ref = slotRefs[index];
        if (ref.status == RvPhotoUploadStatus.verified) continue;
        final photo = _photo(ref.photoId);
        if (photo == null || !File(photo.localPath).existsSync()) {
          slotRefs[index] = RvPhotoReference(
            photoId: ref.photoId,
            slotCode: slot,
            status: RvPhotoUploadStatus.missingLocal,
            retryCount: ref.retryCount,
            lastError: 'El archivo local no existe.',
            order: ref.order,
            description: ref.description,
          );
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
            status: RvPhotoUploadStatus.verified,
            retryCount: ref.retryCount,
            order: ref.order,
            description: ref.description,
          );
          await _markPhotoVerified(photo, uploaded.sha256);
          _debug(draft, 'fotografía', 'verificada slot=$slot');
        } on ApiException catch (error) {
          slotRefs[index] = RvPhotoReference(
            photoId: ref.photoId,
            slotCode: slot,
            status: RvPhotoUploadStatus.error,
            retryCount: ref.retryCount + 1,
            lastError: error.message,
            order: ref.order,
            description: ref.description,
          );
          if (!_retryable(error)) rethrow;
        }
        refs[slot] = slotRefs;
        draft = await _save(draft.copyWith(photos: refs));
      }
    }
    final complete = requiredRvPhotoSlots.every(
      (slot) => (refs[slot] ?? const []).any(
        (photo) => photo.status == RvPhotoUploadStatus.verified,
      ),
    );
    return _save(
      draft.copyWith(
        photos: refs,
        photosStatus: complete ? RvPartStatus.synced : RvPartStatus.pending,
        currentStep: RvSyncStep.reconcile,
      ),
    );
  }

  Future<RvDraft> _reconcilePhotos(RvDraft draft) async {
    final server = await remote.photos(draft.serverInspectionId!);
    _debug(draft, 'reconciliación', '${server.length} fotos remotas');
    final refs = <String, List<RvPhotoReference>>{...draft.photos};
    for (final remotePhoto in server) {
      final slotRefs = [...draft.photosFor(remotePhoto.slotCode)];
      final index = slotRefs.indexWhere(
        (photo) => photo.photoId == remotePhoto.id,
      );
      if (index >= 0 && remotePhoto.status == 'verified') {
        final local = slotRefs[index];
        slotRefs[index] = RvPhotoReference(
          photoId: local.photoId,
          serverPhotoId: remotePhoto.id,
          slotCode: local.slotCode,
          status: RvPhotoUploadStatus.verified,
          retryCount: local.retryCount,
          order: local.order,
          description: local.description,
        );
        refs[remotePhoto.slotCode] = slotRefs;
        final photo = _photo(local.photoId);
        if (photo != null) await _markPhotoVerified(photo, remotePhoto.sha256);
      }
    }
    final complete = requiredRvPhotoSlots.every(
      (slot) => (refs[slot] ?? const []).any(
        (photo) => photo.status == RvPhotoUploadStatus.verified,
      ),
    );
    return _save(
      draft.copyWith(
        photos: refs,
        photosStatus: complete ? RvPartStatus.synced : RvPartStatus.pending,
        currentStep: RvSyncStep.submit,
      ),
    );
  }

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
      _debug(draft, 'submit', 'conflicto persistido por servidor');
      return _save(
        draft.copyWith(
          localStatus: RvLocalStatus.conflict,
          remoteStatus: 'conflict',
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

  Future<RvDraft> _failure(RvDraft draft, ApiException error) {
    final retry = draft.retryCount + 1;
    final failedAt = DateTime.now().toUtc();
    final delay = switch (retry) {
      1 => const Duration(seconds: 5),
      2 => const Duration(seconds: 15),
      _ => const Duration(seconds: 45),
    };
    _debug(
      draft,
      'error',
      '${error.kind.name}; retryable=${_retryable(error)}; intento=$retry '
          'requestId=${error.requestId ?? '-'} field=${error.field ?? '-'}',
    );
    final retryable = _retryable(error);
    return _save(
      draft.copyWith(
        localStatus: error.kind == ApiErrorKind.sessionRevoked
            ? RvLocalStatus.requiresAuthentication
            : retryable
            ? RvLocalStatus.submitPending
            : RvLocalStatus.syncError,
        lastSyncError: retryable
            ? 'Sin conexión con el servidor. Puedes continuar trabajando; '
                  'los cambios se sincronizarán después.'
            : error.message,
        retryCount: retry,
        lastAttemptAt: failedAt,
        updatedAt: failedAt,
        nextRetryAt: retryable ? DateTime.now().toUtc().add(delay) : null,
      ),
    );
  }

  bool _retryable(ApiException error) => const {
    ApiErrorKind.offline,
    ApiErrorKind.timeout,
    ApiErrorKind.serverUnavailable,
  }.contains(error.kind);
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

  Future<void> _markPhotoVerified(
    InspectionPhoto photo,
    String? remoteHash,
  ) async {
    final now = DateTime.now().toUtc();
    final updated = InspectionPhoto.fromJson({
      ...photo.toJson(),
      'syncStatus': MediaSyncStatus.verified.name,
      'verifiedAt': now.toIso8601String(),
      'uploadedAt': now.toIso8601String(),
      'remoteObjectKey': photo.id,
      'remoteSha256': remoteHash,
      'updatedAt': now.toIso8601String(),
    });
    await photoBox.put(photo.id, jsonEncode(updated.toJson()));
    await mediaQueue.put(photo.id, MediaSyncStatus.verified.name);
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
