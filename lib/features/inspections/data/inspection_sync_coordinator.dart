import 'dart:convert';
import 'dart:io';

import 'package:hive_ce/hive.dart';

import '../../../core/network/api_exception.dart';
import '../../../domain/media/inspection_photo.dart';
import '../../../domain/media/media_sync_status.dart';
import '../domain/rv_draft.dart';
import '../domain/rv_sync_state.dart';
import '../domain/rv_validator.dart';
import 'inspection_remote_repository.dart';
import 'rv_draft_repository.dart';

class InspectionSyncCoordinator {
  InspectionSyncCoordinator({
    required this.drafts,
    required this.remote,
    required this.photoBox,
    required this.mediaQueue,
    this.validator = const RvValidator(),
  });
  final RvDraftRepository drafts;
  final InspectionRemoteRepository remote;
  final Box<String> photoBox, mediaQueue;
  final RvValidator validator;
  final Set<String> _running = {};

  bool isRunning(String id) => _running.contains(id);

  Future<RvDraft> synchronize(RvDraft initial, {bool submit = false}) async {
    if (!_running.add(initial.clientInspectionId))
      return drafts.find(initial.clientInspectionId) ?? initial;
    var draft = drafts.find(initial.clientInspectionId) ?? initial;
    try {
      draft = await _create(draft);
      draft = await _answers(draft);
      if (draft.location != null) draft = await _location(draft);
      if (draft.signal != null) draft = await _signal(draft);
      draft = await _photos(draft);
      draft = await _reconcilePhotos(draft);
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
      return draft;
    } on ApiException catch (error) {
      return _failure(draft, error);
    } on Object {
      return _failure(
        draft,
        const ApiException(ApiErrorKind.unknown, 'Error desconocido.'),
      );
    } finally {
      _running.remove(initial.clientInspectionId);
    }
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
    draft = await _save(
      draft.copyWith(
        answersStatus: RvPartStatus.syncing,
        localStatus: RvLocalStatus.pendingAnswers,
        currentStep: RvSyncStep.answers,
      ),
    );
    final checklist = draft.checklist;
    final payload = <Map<String, dynamic>>[];
    for (final section in checklist.sections) {
      for (final item in section.items) {
        if (const {
          'photo',
          'coordinates',
          'signal',
          'readonly',
        }.contains(item.type))
          continue;
        final answer = draft.answers[item.id];
        if (answer == null) continue;
        final visible = validator.isVisible(item, checklist, draft.answers);
        payload.add({
          'itemId': item.id,
          if (!answer.notApplicable && visible)
            'value': item.type == 'multiselect'
                ? answer.selectedOptions
                : answer.value,
          'notApplicable': answer.notApplicable || !visible,
        });
      }
    }
    await remote.saveAnswers(
      id,
      payload,
      'answers-${draft.clientInspectionId}-${draft.updatedAt.microsecondsSinceEpoch}',
    );
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
    return _save(
      draft.copyWith(
        signalStatus: RvPartStatus.synced,
        currentStep: RvSyncStep.photos,
        clearError: true,
      ),
    );
  }

  Future<RvDraft> _photos(RvDraft draft) async {
    var refs = {...draft.photos};
    for (final slot in requiredRvPhotoSlots) {
      final ref = refs[slot];
      if (ref == null || ref.status == RvPhotoUploadStatus.verified) continue;
      final photo = _photo(ref.photoId);
      if (photo == null || !File(photo.localPath).existsSync()) {
        refs[slot] = RvPhotoReference(
          photoId: ref.photoId,
          slotCode: slot,
          status: RvPhotoUploadStatus.missingLocal,
          retryCount: ref.retryCount,
          lastError: 'El archivo local no existe.',
        );
        continue;
      }
      refs[slot] = RvPhotoReference(
        photoId: ref.photoId,
        slotCode: slot,
        status: RvPhotoUploadStatus.uploading,
        retryCount: ref.retryCount,
      );
      draft = await _save(
        draft.copyWith(
          photos: refs,
          photosStatus: RvPartStatus.syncing,
          localStatus: RvLocalStatus.pendingPhotos,
          currentStep: RvSyncStep.photos,
        ),
      );
      try {
        final uploaded = await remote.uploadPhoto(
          draft.serverInspectionId!,
          slot,
          photo,
        );
        refs[slot] = RvPhotoReference(
          photoId: ref.photoId,
          serverPhotoId: uploaded.id,
          slotCode: slot,
          status: RvPhotoUploadStatus.verified,
          retryCount: ref.retryCount,
        );
        await _markPhotoVerified(photo, uploaded.sha256);
      } on ApiException catch (error) {
        refs[slot] = RvPhotoReference(
          photoId: ref.photoId,
          slotCode: slot,
          status: RvPhotoUploadStatus.error,
          retryCount: ref.retryCount + 1,
          lastError: error.message,
        );
        if (!_retryable(error)) rethrow;
      }
      draft = await _save(draft.copyWith(photos: refs));
    }
    final complete = requiredRvPhotoSlots.every(
      (slot) => refs[slot]?.status == RvPhotoUploadStatus.verified,
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
    final refs = {...draft.photos};
    for (final remotePhoto in server) {
      final local = refs[remotePhoto.slotCode];
      if (local != null &&
          local.photoId == remotePhoto.id &&
          remotePhoto.status == 'verified') {
        refs[remotePhoto.slotCode] = RvPhotoReference(
          photoId: local.photoId,
          serverPhotoId: remotePhoto.id,
          slotCode: local.slotCode,
          status: RvPhotoUploadStatus.verified,
          retryCount: local.retryCount,
        );
        final photo = _photo(local.photoId);
        if (photo != null) await _markPhotoVerified(photo, remotePhoto.sha256);
      }
    }
    final complete = requiredRvPhotoSlots.every(
      (slot) => refs[slot]?.status == RvPhotoUploadStatus.verified,
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
    if (result.status != 'submitted') {
      throw const ApiException(
        ApiErrorKind.serverUnavailable,
        'No fue posible confirmar el envío.',
      );
    }
    return _save(
      draft.copyWith(
        localStatus: RvLocalStatus.submitted,
        remoteStatus: result.status,
        submitStatus: RvPartStatus.synced,
        currentStep: RvSyncStep.verify,
        clearError: true,
      ),
    );
  }

  Future<RvDraft> cancel(RvDraft draft, String reason) async {
    if (draft.serverInspectionId != null)
      await remote.cancel(draft.serverInspectionId!, reason);
    return _save(
      draft.copyWith(
        localStatus: RvLocalStatus.cancelled,
        remoteStatus: 'cancelled',
        clearError: true,
      ),
    );
  }

  Future<RvDraft> _failure(RvDraft draft, ApiException error) {
    final retry = draft.retryCount + 1;
    final delay = switch (retry) {
      1 => const Duration(seconds: 5),
      2 => const Duration(seconds: 15),
      _ => const Duration(seconds: 45),
    };
    return _save(
      draft.copyWith(
        localStatus: RvLocalStatus.syncError,
        lastSyncError: error.message,
        retryCount: retry,
        nextRetryAt: _retryable(error)
            ? DateTime.now().toUtc().add(delay)
            : null,
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
}

// ignore_for_file: curly_braces_in_flow_control_structures
