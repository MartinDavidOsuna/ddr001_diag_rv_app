import 'dart:convert';
import 'dart:io';

import 'package:hive_ce/hive.dart';
import 'package:uuid/uuid.dart';
import 'package:crypto/crypto.dart';

import '../../../data/local/visual_inspection_repository.dart';
import '../../../data/local/operation_journal_repository.dart';
import '../../../core/persistence/versioned_json_codec.dart';
import '../../../domain/enums/app_enums.dart';
import '../../../domain/inspections/visual_inspection.dart';
import '../../../domain/models/app_models.dart';
import '../../checklist/data/checklist_models.dart';
import '../domain/rv_draft.dart';
import '../domain/rv_visual_document_classification.dart';
import '../domain/rv_sync_state.dart';
import '../domain/rv_recovery_policy.dart';
import '../../../domain/media/inspection_photo.dart';
import '../../../domain/media/media_sync_status.dart';
import '../../../domain/media/photo_integrity_status.dart';
import '../../../data/local/media_work_item_codec.dart';
import '../../../domain/sync/sync_queue_item.dart';
import '../../../core/media/file_digest_service.dart';
import '../../../domain/integrity/operation_journal.dart';

class RvDraftRepository {
  RvDraftRepository(this.visualRepository);
  final VisualInspectionRepository visualRepository;
  static const storageKey = rvDraftDocumentStorageKey;
  int _lastInactiveDiscardDocumentDecodes = 0;

  /// Synthetic/profile metric for the conservative cross-reference scan.
  int get lastInactiveDiscardDocumentDecodes =>
      _lastInactiveDiscardDocumentDecodes;

  Future<RvDraft> openOrCreate({
    required Hydrant hydrant,
    required AppUser user,
    required DynamicChecklist checklist,
  }) async {
    final indexed = activeFor(hydrant.id);
    if (indexed != null &&
        !indexed.isReadOnly &&
        indexed.supersededBy == null) {
      final upgraded = upgradeDraftChecklist(indexed, checklist);
      if (!identical(upgraded, indexed)) await save(upgraded);
      return upgraded;
    }
    final normalizedAccount = hydrant.code.trim().toUpperCase();
    final recovered = all()
        .where((draft) {
          if (draft.isReadOnly || draft.supersededBy != null) return false;
          final inspection = visualRepository.findById(
            draft.clientInspectionId,
          );
          final owned =
              inspection == null ||
              inspection.createdBy == user.id ||
              inspection.inspectorId == user.id;
          return owned &&
              {
                draft.originalAccountNumber.trim().toUpperCase(),
                draft.effectiveAccountNumber.trim().toUpperCase(),
              }.contains(normalizedAccount);
        })
        .toList(growable: false);
    if (recovered.isNotEmpty) {
      final existing = selectCanonicalDraft(recovered);
      final upgraded = upgradeDraftChecklist(existing, checklist);
      if (!identical(upgraded, existing)) await save(upgraded);
      return upgraded;
    }
    final inspection = await visualRepository.openOrCreate(hydrant, user);
    final existing = fromInspection(inspection);
    if (existing != null) {
      final upgraded = upgradeDraftChecklist(existing, checklist);
      if (!identical(upgraded, existing)) await save(upgraded);
      return upgraded;
    }
    final now = DateTime.now().toUtc();
    final draft = RvDraft(
      clientInspectionId: inspection.id.isEmpty
          ? const Uuid().v4()
          : inspection.id,
      hydrantId: hydrant.id,
      accountNumber: hydrant.code,
      fieldSessionId: user.id,
      checklistId: checklist.id,
      checklistVersion: checklist.version,
      checklistSnapshot: checklist.toJson(),
      createdAt: now,
      updatedAt: now,
    );
    await save(draft);
    return draft;
  }

  RvDraft? activeFor(String hydrantId) {
    final inspection = visualRepository.activeForHydrant(hydrantId);
    if (inspection == null) return null;
    final draft = fromInspection(inspection);
    return draft != null && !draft.isReadOnly && draft.supersededBy == null
        ? draft
        : null;
  }

  List<RvDraft> pending() {
    final values = <RvDraft>[];
    for (final inspection in visualRepository.accessible()) {
      final value = fromInspection(inspection);
      if (value != null && !value.isReadOnly && value.supersededBy == null) {
        values.add(value);
      }
    }
    return values;
  }

  List<RvDraft> all() {
    final values = <RvDraft>[];
    for (final inspection in visualRepository.accessible()) {
      final value = fromInspection(inspection);
      if (value != null) values.add(value);
    }
    return values;
  }

  RvDraft? find(String clientInspectionId) {
    final value = visualRepository.findById(clientInspectionId);
    return value == null ? null : fromInspection(value);
  }

  bool canDeleteUnsyncedLocal({
    required String clientInspectionId,
    required String creatorId,
  }) {
    final draft = find(clientInspectionId);
    final inspection = visualRepository.findById(clientInspectionId);
    if (draft == null || inspection == null) return false;
    if (inspection.status == InspectionStatus.completed) return false;
    final ownedByCreator =
        inspection.createdBy == creatorId ||
        inspection.inspectorId == creatorId;
    final hasOfficialRemoteState =
        draft.officialInspectionId != null ||
        draft.visualReportId != null ||
        const {
          'submitted',
          'completed',
          'validated',
        }.contains(draft.remoteStatus);
    return ownedByCreator &&
        !hasOfficialRemoteState &&
        draft.localStatus != RvLocalStatus.submitted &&
        !draft.isReadOnly;
  }

  RvDraft? fromInspection(VisualInspection inspection) {
    final raw = inspection.unknownFields[storageKey];
    return raw is Map ? RvDraft.fromJson(Map<String, dynamic>.from(raw)) : null;
  }

  Future<void> save(RvDraft draft) async {
    final inspection = visualRepository.findById(draft.clientInspectionId);
    if (inspection == null)
      throw StateError('No existe el documento local de inspección.');
    final submitted =
        draft.localStatus == RvLocalStatus.submitted &&
        const {'submitted', 'validated'}.contains(draft.remoteStatus);
    if (inspection.status == InspectionStatus.completed) {
      await visualRepository.saveCompletedSyncMetadata(
        inspectionId: inspection.id,
        storageKey: storageKey,
        metadata: draft.toJson(),
      );
      return;
    }
    await visualRepository.save(
      inspection.copyWith(
        status: submitted ? InspectionStatus.completed : inspection.status,
        completedAt: submitted
            ? (draft.lastStatusChangedAt ?? draft.updatedAt)
            : inspection.completedAt,
        updatedAt: draft.updatedAt,
        unknownFields: {
          ...inspection.unknownFields,
          storageKey: draft.toJson(),
        },
      ),
    );
  }

  Future<RvDraft> saveInactiveClosureDraft({
    required String clientInspectionId,
    required AppUser user,
    required String comment,
    bool allowEmpty = false,
    DateTime? now,
  }) async {
    final inspection = visualRepository.findById(clientInspectionId);
    final current = inspection == null ? null : fromInspection(inspection);
    if (inspection == null || current == null) {
      throw StateError('No existe la revisión local.');
    }
    _validateInactiveDraftOwner(inspection, current, user);
    final location = current.location;
    if (location == null || !location.isValid) {
      throw StateError('Captura y guarda una coordenada válida.');
    }
    final normalizedComment = comment.trim();
    if (normalizedComment.length > inactiveClosureCommentMaxLength) {
      throw StateError(
        'El comentario no puede exceder '
        '$inactiveClosureCommentMaxLength caracteres.',
      );
    }
    final photoIds = current
        .photosFor(noHydrantAtLocationPhotoSlot)
        .map((photo) => photo.photoId)
        .toList(growable: false);
    final existing = current.inactiveClosureDraft;
    if (normalizedComment.isEmpty &&
        photoIds.isEmpty &&
        existing == null &&
        !allowEmpty) {
      return current;
    }
    if (existing != null) {
      if (existing.createdByUserId.toLowerCase() != user.id.toLowerCase() ||
          existing.deviceId.toLowerCase() != user.deviceId.toLowerCase() ||
          !sameRvLocationSample(existing.location, location)) {
        throw StateError('El borrador de cierre pertenece a otro contexto.');
      }
    }
    final timestamp = (now ?? DateTime.now()).toUtc();
    final inactiveDraft = RvInactiveClosureDraft(
      draftId: existing?.draftId ?? const Uuid().v4(),
      location: location,
      comment: normalizedComment,
      startedAt: existing?.startedAt ?? timestamp,
      updatedAt: timestamp,
      createdByUserId: user.id,
      createdByName: user.fullName,
      brigadeId: user.brigadeId,
      deviceId: user.deviceId,
      photoIds: List.unmodifiable(photoIds),
    );
    final updated = current.copyWith(
      inactiveClosureDraft: inactiveDraft,
      updatedAt: timestamp,
    );
    await _saveInactiveDraftJournaled(
      inspection: inspection,
      draft: updated,
      user: user,
    );
    return find(clientInspectionId) ?? updated;
  }

  Future<void> _saveInactiveDraftJournaled({
    required VisualInspection inspection,
    required RvDraft draft,
    required AppUser user,
  }) async {
    final journal = OperationJournalRepository(
      Hive.box<String>('operation_journal_v1'),
    );
    var operation = OperationJournalEntry(
      operationId: const Uuid().v4(),
      operationType: JournalOperationType.saveInactiveClosureDraft,
      entityIds: [inspection.id],
      documentWrites: [inspection.id],
      preparedAt: DateTime.now().toUtc(),
      actor: user.id,
      deviceId: user.deviceId,
      correlationId: draft.inactiveClosureDraft!.draftId,
    );
    await journal.save(operation);
    try {
      await save(draft);
      final confirmed = find(draft.clientInspectionId);
      if (confirmed?.inactiveClosureDraft?.draftId !=
          draft.inactiveClosureDraft?.draftId) {
        throw StateError('No fue posible confirmar el borrador inactivo.');
      }
      operation = operation.advance(JournalStatus.documentsWritten);
      await journal.save(operation);
      await journal.save(operation.advance(JournalStatus.committed));
    } on Object catch (error) {
      await journal.save(
        operation.advance(JournalStatus.needsRecovery, error: '$error'),
      );
      rethrow;
    }
  }

  Future<RvDraft> discardInactiveClosureDraft({
    required String clientInspectionId,
    required AppUser user,
  }) async {
    final inspection = visualRepository.findById(clientInspectionId);
    final current = inspection == null ? null : fromInspection(inspection);
    if (inspection == null || current == null) {
      throw StateError('No existe la revisión local.');
    }
    if (current.isInactive || current.inactiveClosure != null) {
      throw StateError('Un cierre inactivo confirmado no puede descartarse.');
    }
    _validateInactiveDraftOwner(inspection, current, user);
    final references = current.photosFor(noHydrantAtLocationPhotoSlot);
    final inactiveDraft = current.inactiveClosureDraft;
    if (references.isEmpty && inactiveDraft == null) return current;
    final referenceIds = references.map((item) => item.photoId).toSet();
    if (inactiveDraft != null &&
        !referenceIds.containsAll(inactiveDraft.photoIds)) {
      throw StateError('El borrador no coincide con su evidencia dedicada.');
    }
    final photoBox = Hive.box<String>('inspection_photos_v1');
    final photos = <String, Map<String, dynamic>>{};
    for (final reference in references) {
      final raw = photoBox.get(reference.photoId);
      if (raw == null) {
        throw StateError('Falta el documento de evidencia dedicada.');
      }
      final json = Map<String, dynamic>.from(jsonDecode(raw) as Map);
      final photo = InspectionPhoto.fromJson(json);
      _validateDiscardableInactivePhoto(
        photo: photo,
        reference: reference,
        clientInspectionId: clientInspectionId,
        user: user,
      );
      photos[photo.id] = json;
    }
    _assertPhotosHaveNoOtherReferences(
      photoIds: referenceIds,
      currentInspectionId: clientInspectionId,
    );
    final journal = OperationJournalRepository(
      Hive.box<String>('operation_journal_v1'),
    );
    final operationId = inactiveDraft == null
        ? 'inactive-discard-$clientInspectionId-${const Uuid().v4()}'
        : 'inactive-discard-${inactiveDraft.draftId}';
    final prior = journal.find(operationId);
    if (prior?.status == JournalStatus.committed) {
      return find(clientInspectionId) ?? current;
    }
    var operation =
        prior ??
        OperationJournalEntry(
          operationId: operationId,
          operationType: JournalOperationType.discardInactiveClosureDraft,
          entityIds: [clientInspectionId, ...referenceIds],
          documentWrites: [clientInspectionId, ...referenceIds],
          queueWrites: referenceIds.toList(growable: false),
          fileWrites: [
            for (final json in photos.values)
              if (json['localPath'] case final String path) path,
          ],
          preparedAt: DateTime.now().toUtc(),
          actor: user.id,
          deviceId: user.deviceId,
          correlationId: operationId,
        );
    await journal.save(operation);
    try {
      final latest = find(clientInspectionId);
      final latestIds =
          latest
              ?.photosFor(noHydrantAtLocationPhotoSlot)
              .map((photo) => photo.photoId.toLowerCase())
              .toSet() ??
          const <String>{};
      if (latest == null ||
          latest.isInactive ||
          latest.updatedAt.toUtc() != current.updatedAt.toUtc() ||
          latest.inactiveClosureDraft?.draftId != inactiveDraft?.draftId ||
          latestIds.length != referenceIds.length ||
          !latestIds.containsAll(referenceIds.map((id) => id.toLowerCase()))) {
        throw StateError(
          'La revisión cambió durante el descarte; no se retiró evidencia.',
        );
      }
      final discardedAt = DateTime.now().toUtc();
      for (final entry in photos.entries) {
        await photoBox.put(
          entry.key,
          jsonEncode({
            ...entry.value,
            'deletedAt': discardedAt.toIso8601String(),
            'updatedAt': discardedAt.toIso8601String(),
            'discardReason': 'inactiveClosureDraftDiscarded',
            'discardOperationId': operation.operationId,
          }),
        );
        await _resolveDiscardedMediaWork(
          photoId: entry.key,
          inspectionId: clientInspectionId,
        );
      }
      operation = operation.advance(JournalStatus.filesWritten);
      await journal.save(operation);
      final photosBySlot = <String, List<RvPhotoReference>>{...current.photos}
        ..remove(noHydrantAtLocationPhotoSlot);
      await save(
        latest.copyWith(
          photos: photosBySlot,
          clearInactiveClosureDraft: true,
          photosStatus: RvPartStatus.pending,
          updatedAt: discardedAt,
        ),
      );
      operation = operation.advance(JournalStatus.documentsWritten);
      await journal.save(operation);
      _verifyInactiveDraftDiscard(
        clientInspectionId: clientInspectionId,
        photoIds: referenceIds,
      );
      await journal.save(operation.advance(JournalStatus.committed));
      return find(clientInspectionId)!;
    } on Object catch (error) {
      await journal.save(
        operation.advance(JournalStatus.needsRecovery, error: '$error'),
      );
      rethrow;
    }
  }

  void _validateInactiveDraftOwner(
    VisualInspection inspection,
    RvDraft current,
    AppUser user,
  ) {
    if (current.isReadOnly || inspection.status == InspectionStatus.completed) {
      throw StateError('La revisión ya no admite cambios.');
    }
    if (current.activeFormStep != 0) {
      throw StateError(
        'El reporte inactivo sólo está disponible en el paso 1.',
      );
    }
    final owned =
        inspection.createdBy.toLowerCase() == user.id.toLowerCase() ||
        inspection.inspectorId.toLowerCase() == user.id.toLowerCase();
    if (!owned) throw StateError('La revisión pertenece a otro usuario.');
    if (current.fieldSessionId.trim().isEmpty ||
        current.fieldSessionId.toLowerCase() != user.id.toLowerCase()) {
      throw StateError('La revisión pertenece a otro scope local.');
    }
    if (inspection.deviceId.isNotEmpty &&
        inspection.deviceId.toLowerCase() != user.deviceId.toLowerCase()) {
      throw StateError('La revisión pertenece a otro dispositivo.');
    }
  }

  void _validateDiscardableInactivePhoto({
    required InspectionPhoto photo,
    required RvPhotoReference reference,
    required String clientInspectionId,
    required AppUser user,
  }) {
    final hasRemoteState =
        reference.serverPhotoId != null ||
        reference.status != RvPhotoUploadStatus.pending ||
        photo.uploadedAt != null ||
        photo.verifiedAt != null ||
        photo.remoteObjectKey != null ||
        photo.remoteSha256 != null ||
        photo.syncStatus != MediaSyncStatus.pendingUpload;
    if (photo.isDeleted ||
        photo.inspectionId.toLowerCase() != clientInspectionId.toLowerCase() ||
        photo.category != noHydrantAtLocationPhotoSlot ||
        reference.slotCode != noHydrantAtLocationPhotoSlot ||
        photo.capturedByUserId.toLowerCase() != user.id.toLowerCase() ||
        photo.deviceId.toLowerCase() != user.deviceId.toLowerCase() ||
        hasRemoteState) {
      throw StateError(
        'La evidencia dedicada no puede descartarse de forma segura.',
      );
    }
  }

  void _assertPhotosHaveNoOtherReferences({
    required Set<String> photoIds,
    required String currentInspectionId,
  }) {
    _lastInactiveDiscardDocumentDecodes = 0;
    final targetIds = photoIds.map((id) => id.toLowerCase()).toSet();
    for (final entry in visualRepository.documents.toMap().entries) {
      try {
        final payload = VersionedJsonCodec.decode(entry.value).payload;
        final embedded = payload[storageKey];
        if (embedded is! Map) continue;
        _lastInactiveDiscardDocumentDecodes++;
        final draft = RvDraft.fromJson(Map<String, dynamic>.from(embedded));
        final referencedSlots = <String>[
          for (final slot in draft.photos.entries)
            if (slot.value.any(
              (reference) =>
                  targetIds.contains(reference.photoId.toLowerCase()),
            ))
              slot.key,
        ];
        final confirmed =
            draft.inactiveClosure?.photoIds.any(
              (id) => targetIds.contains(id.toLowerCase()),
            ) ==
            true;
        if ((referencedSlots.isNotEmpty &&
                '${entry.key}'.toLowerCase() !=
                    currentInspectionId.toLowerCase()) ||
            referencedSlots.any(
              (slot) => slot != noHydrantAtLocationPhotoSlot,
            ) ||
            confirmed) {
          throw StateError(
            'La evidencia está referenciada por otro documento.',
          );
        }
      } on StateError {
        rethrow;
      } on Object {
        throw StateError(
          'No fue posible demostrar que la evidencia sea exclusiva.',
        );
      }
    }
  }

  Future<void> _resolveDiscardedMediaWork({
    required String photoId,
    required String inspectionId,
  }) async {
    final resolved = MediaWorkItemCodec.pending(
      photoId: photoId,
      inspectionId: inspectionId,
      slotCode: noHydrantAtLocationPhotoSlot,
      status: 'discardedLocalInactiveDraft',
    );
    await Hive.box<String>('media_work_queue_v1').put(photoId, resolved);
    await Hive.box<String>('media_sync_queue').put(photoId, resolved);
  }

  void _verifyInactiveDraftDiscard({
    required String clientInspectionId,
    required Set<String> photoIds,
  }) {
    final confirmed = find(clientInspectionId);
    if (confirmed == null ||
        confirmed.inactiveClosureDraft != null ||
        confirmed.photosFor(noHydrantAtLocationPhotoSlot).isNotEmpty) {
      throw StateError('No fue posible confirmar el descarte del reporte.');
    }
    final photoBox = Hive.box<String>('inspection_photos_v1');
    for (final photoId in photoIds) {
      final raw = photoBox.get(photoId);
      if (raw == null ||
          InspectionPhoto.fromJson(
                Map<String, dynamic>.from(jsonDecode(raw) as Map),
              ).isDeleted !=
              true ||
          MediaWorkItemCodec.statusOf(
                photoId,
                Hive.box<String>('media_work_queue_v1').get(photoId),
              ) !=
              'discardedLocalInactiveDraft' ||
          MediaWorkItemCodec.statusOf(
                photoId,
                Hive.box<String>('media_sync_queue').get(photoId),
              ) !=
              'discardedLocalInactiveDraft') {
        throw StateError('El descarte de evidencia no quedó confirmado.');
      }
    }
  }

  Future<RvDraft> closeAsInactive({
    required String clientInspectionId,
    required AppUser user,
    required String comment,
    DateTime? closedAt,
    FileDigestService digestService = const StreamingFileDigestService(),
  }) async {
    final normalizedComment = comment.trim();
    if (normalizedComment.length < inactiveClosureCommentMinLength ||
        normalizedComment.length > inactiveClosureCommentMaxLength) {
      throw StateError(
        'El comentario debe tener entre $inactiveClosureCommentMinLength y '
        '$inactiveClosureCommentMaxLength caracteres.',
      );
    }
    final inspection = visualRepository.findById(clientInspectionId);
    final current = inspection == null ? null : fromInspection(inspection);
    if (inspection == null || current == null) {
      throw StateError('No existe la revisión local.');
    }
    if (current.isInactive) {
      final prior = current.inactiveClosure!;
      if (await _confirmedInactiveClosureMatches(
        draft: current,
        closure: prior,
        clientInspectionId: clientInspectionId,
        user: user,
        normalizedComment: normalizedComment,
        digestService: digestService,
      )) {
        return current;
      }
      throw StateError('La revisión ya fue cerrada con otra evidencia.');
    }
    _validateInactiveDraftOwner(inspection, current, user);
    final location = current.location;
    if (location == null || !location.isValid) {
      throw StateError('Captura y guarda una coordenada válida.');
    }
    final references = current.photosFor(noHydrantAtLocationPhotoSlot);
    if (references.isEmpty) {
      throw StateError('Captura al menos una fotografía del lugar.');
    }
    final inactiveDraft = current.inactiveClosureDraft;
    if (inactiveDraft == null ||
        inactiveDraft.comment != normalizedComment ||
        inactiveDraft.createdByUserId.toLowerCase() != user.id.toLowerCase() ||
        inactiveDraft.deviceId.toLowerCase() != user.deviceId.toLowerCase() ||
        !sameRvLocationSample(inactiveDraft.location, location) ||
        inactiveDraft.contractVersion != inactiveClosureContractVersion) {
      throw StateError(
        'Guarda y verifica el borrador del reporte antes de cerrarlo.',
      );
    }
    final referenceIds = references.map((item) => item.photoId).toList();
    if (!_sameOrderedIds(inactiveDraft.photoIds, referenceIds)) {
      throw StateError('La evidencia cambió después de guardar el borrador.');
    }
    final photoBox = Hive.box<String>('inspection_photos_v1');
    final photoIds = <String>[];
    final normalizedHashes = <String, String>{};
    final receivedHashes = <String, String>{};
    for (final reference in references) {
      final raw = photoBox.get(reference.photoId);
      if (raw == null) {
        throw StateError('No existe el documento local de la fotografía.');
      }
      final photo = InspectionPhoto.fromJson(
        Map<String, dynamic>.from(jsonDecode(raw) as Map),
      );
      if (photo.isDeleted ||
          photo.inspectionId.toLowerCase() !=
              clientInspectionId.toLowerCase() ||
          photo.category != noHydrantAtLocationPhotoSlot ||
          photo.capturedByUserId.toLowerCase() != user.id.toLowerCase() ||
          photo.deviceId.toLowerCase() != user.deviceId.toLowerCase() ||
          photo.sha256.isEmpty ||
          photo.receivedSha256.isEmpty) {
        throw StateError('La fotografía no pertenece a este cierre.');
      }
      final file = File(photo.localPath);
      if (!await file.exists() || await file.length() != photo.fileSize) {
        throw StateError('El archivo de la fotografía no está íntegro.');
      }
      if ((await digestService.sha256Of(file)).toLowerCase() !=
          photo.sha256.toLowerCase()) {
        throw StateError('El hash físico de la fotografía no coincide.');
      }
      photoIds.add(photo.id);
      normalizedHashes[photo.id] = photo.sha256;
      receivedHashes[photo.id] = photo.receivedSha256;
    }
    final now = (closedAt ?? DateTime.now()).toUtc();
    final idempotencyKey = _inactiveClosureIdempotencyKey(
      clientInspectionId: clientInspectionId,
      comment: normalizedComment,
      location: location,
      user: user,
      photoIds: photoIds,
      normalizedHashes: normalizedHashes,
      receivedHashes: receivedHashes,
    );
    final closure = RvInactiveClosure(
      reasonCode: noHydrantAtLocationReasonCode,
      comment: normalizedComment,
      location: location,
      closedAt: now,
      closedByUserId: user.id,
      closedByName: user.fullName,
      brigadeId: user.brigadeId,
      deviceId: user.deviceId,
      photoIds: List.unmodifiable(photoIds),
      normalizedPhotoHashes: Map.unmodifiable(normalizedHashes),
      receivedPhotoHashes: Map.unmodifiable(receivedHashes),
      idempotencyKey: idempotencyKey,
    );
    final closedDraft = current.copyWith(
      localStatus: RvLocalStatus.inactive,
      photosStatus: RvPartStatus.pending,
      submitStatus: RvPartStatus.notCaptured,
      inactiveClosure: closure,
      clearInactiveClosureDraft: true,
      lastStatusChangedAt: now,
      updatedAt: now,
      clearError: true,
      clearNextRetryAt: true,
    );
    await visualRepository.finalize(
      inspection.copyWith(
        status: InspectionStatus.completed,
        completedAt: now,
        updatedAt: now,
        unknownFields: {
          ...inspection.unknownFields,
          storageKey: closedDraft.toJson(),
        },
      ),
      operationType: JournalOperationType.closeInactiveVisualReport,
    );
    final confirmed = find(clientInspectionId);
    final active = visualRepository.activeForHydrant(current.hydrantId);
    if (confirmed?.isInactive != true ||
        active?.id.toLowerCase() == clientInspectionId.toLowerCase()) {
      throw StateError('No fue posible confirmar el cierre inactivo local.');
    }
    return confirmed!;
  }

  Future<bool> _confirmedInactiveClosureMatches({
    required RvDraft draft,
    required RvInactiveClosure closure,
    required String clientInspectionId,
    required AppUser user,
    required String normalizedComment,
    required FileDigestService digestService,
  }) async {
    if (draft.clientInspectionId.toLowerCase() !=
            clientInspectionId.toLowerCase() ||
        closure.reasonCode != noHydrantAtLocationReasonCode ||
        closure.comment != normalizedComment ||
        closure.closedByUserId.toLowerCase() != user.id.toLowerCase() ||
        closure.deviceId.toLowerCase() != user.deviceId.toLowerCase() ||
        closure.contractVersion != inactiveClosureContractVersion ||
        draft.location == null ||
        !sameRvLocationSample(closure.location, draft.location!)) {
      return false;
    }
    final references = draft.photosFor(noHydrantAtLocationPhotoSlot);
    final referenceIds = references.map((item) => item.photoId).toList();
    if (!_sameOrderedIds(closure.photoIds, referenceIds)) return false;
    final expectedKey = _inactiveClosureIdempotencyKey(
      clientInspectionId: clientInspectionId,
      comment: normalizedComment,
      location: closure.location,
      user: user,
      photoIds: closure.photoIds,
      normalizedHashes: closure.normalizedPhotoHashes,
      receivedHashes: closure.receivedPhotoHashes,
    );
    if (closure.idempotencyKey != expectedKey) return false;
    final photoBox = Hive.box<String>('inspection_photos_v1');
    for (final photoId in closure.photoIds) {
      final raw = photoBox.get(photoId);
      if (raw == null) return false;
      try {
        final photo = InspectionPhoto.fromJson(
          Map<String, dynamic>.from(jsonDecode(raw) as Map),
        );
        final file = File(photo.localPath);
        if (photo.isDeleted ||
            photo.inspectionId.toLowerCase() !=
                clientInspectionId.toLowerCase() ||
            photo.category != noHydrantAtLocationPhotoSlot ||
            photo.capturedByUserId.toLowerCase() != user.id.toLowerCase() ||
            photo.deviceId.toLowerCase() != user.deviceId.toLowerCase() ||
            closure.normalizedPhotoHashes[photoId] != photo.sha256 ||
            closure.receivedPhotoHashes[photoId] != photo.receivedSha256 ||
            !await file.exists() ||
            await file.length() != photo.fileSize ||
            (await digestService.sha256Of(file)).toLowerCase() !=
                photo.sha256.toLowerCase()) {
          return false;
        }
      } on Object {
        return false;
      }
    }
    return true;
  }

  bool _sameOrderedIds(List<String> left, List<String> right) {
    if (left.length != right.length) return false;
    for (var index = 0; index < left.length; index++) {
      if (left[index].toLowerCase() != right[index].toLowerCase()) return false;
    }
    return true;
  }

  String _inactiveClosureIdempotencyKey({
    required String clientInspectionId,
    required String comment,
    required RvLocationSample location,
    required AppUser user,
    required List<String> photoIds,
    required Map<String, String> normalizedHashes,
    required Map<String, String> receivedHashes,
  }) {
    final identity = jsonEncode({
      'clientInspectionId': clientInspectionId.toLowerCase(),
      'reasonCode': noHydrantAtLocationReasonCode,
      'comment': comment,
      'location': location.toJson(),
      'userId': user.id.toLowerCase(),
      'deviceId': user.deviceId.toLowerCase(),
      'photoIds': photoIds.map((id) => id.toLowerCase()).toList(),
      'normalizedHashes': {
        for (final id in photoIds) id.toLowerCase(): normalizedHashes[id],
      },
      'receivedHashes': {
        for (final id in photoIds) id.toLowerCase(): receivedHashes[id],
      },
      'contractVersion': inactiveClosureContractVersion,
    });
    return 'inactive-v$inactiveClosureContractVersion-'
        '${sha256.convert(utf8.encode(identity))}';
  }

  Future<RvDraft> migrateConflictToAdditionalRevision(RvDraft legacy) async {
    final source = visualRepository.findById(legacy.clientInspectionId);
    if (source == null) {
      throw StateError('No existe la captura local del conflicto.');
    }
    final now = DateTime.now().toUtc();
    final newId = const Uuid().v4();
    final draftJson = Map<String, dynamic>.from(legacy.toJson())
      ..['clientInspectionId'] = newId
      ..remove('serverInspectionId')
      ..remove('serverHydrantId')
      ..remove('officialInspectionId')
      ..remove('conflictId')
      ..remove('visualReportId')
      ..remove('currentVersionId')
      ..remove('baseVersionId')
      ..remove('versionConflictId')
      ..remove('proposedVersionId')
      ..['localStatus'] = RvLocalStatus.pendingCreate.name
      ..['remoteStatus'] = null
      ..['answersStatus'] = RvPartStatus.pending.name
      ..['locationStatus'] = RvPartStatus.pending.name
      ..['signalStatus'] = RvPartStatus.pending.name
      ..['photosStatus'] = RvPartStatus.pending.name
      ..['submitStatus'] = RvPartStatus.pending.name
      ..['currentStep'] = RvSyncStep.create.name
      ..['retryCount'] = 0
      ..['lastSyncError'] = null
      ..['nextRetryAt'] = null
      ..['createdAt'] = now.toIso8601String()
      ..['updatedAt'] = now.toIso8601String();
    final photoGroups = Map<String, dynamic>.from(
      draftJson['photos'] as Map? ?? const {},
    );
    draftJson['photos'] = photoGroups.map(
      (slot, rawItems) => MapEntry(
        slot,
        (rawItems as List).map((raw) {
          return Map<String, dynamic>.from(raw as Map)
            ..['status'] = RvPhotoUploadStatus.pending.name
            ..remove('serverPhotoId')
            ..['retryCount'] = 0
            ..remove('lastError');
        }).toList(),
      ),
    );
    final revisionDraft = RvDraft.fromJson(draftJson);
    final inspectionJson = Map<String, dynamic>.from(source.toJson())
      ..['id'] = newId
      ..['status'] = InspectionStatus.inProgress.name
      ..['completedAt'] = null
      ..['startedAt'] = now.toIso8601String()
      ..['createdAt'] = now.toIso8601String()
      ..['updatedAt'] = now.toIso8601String()
      ..['revisionOfReportId'] = source.id
      ..['previousRevisionId'] = source.id
      ..['revisionNumber'] = source.revisionNumber + 1
      ..['revisionReason'] = 'Migración de conflicto a revisión adicional'
      ..[storageKey] = revisionDraft.toJson();
    await visualRepository.createRevisionClone(
      VisualInspection.fromJson(inspectionJson),
    );
    await save(
      legacy.copyWith(
        supersededBy: newId,
        recoveryStatus: 'legacyConflictMigratedToAdditionalRevision',
      ),
    );
    return revisionDraft;
  }

  Future<void> deleteUnsyncedLocal({
    required String clientInspectionId,
    required String creatorId,
  }) async {
    final draft = find(clientInspectionId);
    if (draft == null) throw StateError('No se encontró el borrador local.');
    final inspection = visualRepository.findById(clientInspectionId);
    if (inspection == null ||
        (inspection.createdBy != creatorId &&
            inspection.inspectorId != creatorId)) {
      throw StateError('Sólo el creador puede eliminar este borrador.');
    }
    if (!canDeleteUnsyncedLocal(
      clientInspectionId: clientInspectionId,
      creatorId: creatorId,
    )) {
      throw StateError(
        'Esta revisión ya fue enviada y no puede eliminarse localmente.',
      );
    }
    // Technician deletion is a reversible business state. Documents, files,
    // queues and journals stay available for audit and recovery.
    await save(
      draft.copyWith(
        localStatus: RvLocalStatus.cancelled,
        recoveryStatus: 'archivedByTechnician',
        updatedAt: DateTime.now().toUtc(),
      ),
    );
    await visualRepository.deleteLocalDraft(
      clientInspectionId,
      creatorId: creatorId,
      reason: 'technician_archive',
      correlationId: clientInspectionId,
    );
  }

  /// Restores photo documents that survived a crash before their draft link.
  /// Documents are authoritative and the operation is idempotent.
  Future<int> reconcileOrphanedPhotoReferences() async {
    var repaired = 0;
    final photoBox = Hive.box<String>('inspection_photos_v1');
    final workBox = Hive.box<String>('media_work_queue_v1');
    for (final entry in photoBox.toMap().entries) {
      try {
        final photo = InspectionPhoto.fromJson(
          Map<String, dynamic>.from(jsonDecode(entry.value) as Map),
        );
        if (photo.isDeleted ||
            photo.inspectionId.isEmpty ||
            photo.id.isEmpty ||
            photo.sha256.isEmpty ||
            !File(photo.localPath).existsSync()) {
          continue;
        }
        final draft = find(photo.inspectionId);
        if (draft == null) continue;
        final alreadyLinked = draft.photos.values
            .expand((items) => items)
            .any((reference) => reference.photoId == photo.id);
        if (!alreadyLinked) {
          final slot = photo.category.isEmpty
              ? (photo.evidenceRequirementId ?? 'recovered:${photo.id}')
              : photo.category;
          final photos = <String, List<RvPhotoReference>>{
            ...draft.photos,
            slot: [
              ...draft.photosFor(slot),
              RvPhotoReference(
                photoId: photo.id,
                slotCode: slot,
                status: photo.integrityStatus == PhotoIntegrityStatus.confirmed
                    ? RvPhotoUploadStatus.verified
                    : RvPhotoUploadStatus.pending,
              ),
            ],
          };
          await save(
            draft.copyWith(
              photos: photos,
              photosStatus: RvPartStatus.pending,
              recoveryStatus: 'orphanPhotoReferencesRecovered',
            ),
          );
          repaired++;
        }
        final current = workBox.get(photo.id);
        final decoded = current == null
            ? null
            : MediaWorkItemCodec.decode(photo.id, current);
        if (decoded == null || decoded.schemaVersion < 2) {
          await workBox.put(
            photo.id,
            MediaWorkItemCodec.pending(
              photoId: photo.id,
              inspectionId: photo.inspectionId,
              slotCode: photo.category,
              status: decoded?.status ?? 'pendingUpload',
            ),
          );
        }
      } on Object {
        // The original entry remains untouched and is handled by quarantine.
      }
    }
    return repaired;
  }

  Future<void> reconcileSubmittedStatuses() async {
    for (final inspection in visualRepository.accessible()) {
      if (inspection.status == InspectionStatus.completed) continue;
      final draft = fromInspection(inspection);
      if (draft == null ||
          draft.localStatus != RvLocalStatus.submitted ||
          !const {'submitted', 'validated'}.contains(draft.remoteStatus)) {
        continue;
      }
      await visualRepository.save(
        inspection.copyWith(
          status: InspectionStatus.completed,
          completedAt: draft.lastStatusChangedAt ?? draft.updatedAt,
          updatedAt: draft.updatedAt,
        ),
      );
    }
  }

  /// Repairs legacy duplicate state using only a persisted remote confirmation.
  /// It never infers verification from file presence or queue membership.
  Future<int> reconcileVerifiedPhotoReferences(Box<String> mediaSyncBox) async {
    var repaired = 0;
    for (final draft in all()) {
      var changed = false;
      final photos = <String, List<RvPhotoReference>>{};
      for (final entry in draft.photos.entries) {
        photos[entry.key] = [
          for (final reference in entry.value)
            if (MediaWorkItemCodec.statusOf(
                      reference.photoId,
                      mediaSyncBox.get(reference.photoId),
                    ) ==
                    MediaSyncStatus.verified.name &&
                reference.status != RvPhotoUploadStatus.verified)
              () {
                changed = true;
                repaired++;
                return RvPhotoReference(
                  photoId: reference.photoId,
                  serverPhotoId: reference.serverPhotoId,
                  slotCode: reference.slotCode,
                  status: RvPhotoUploadStatus.verified,
                  retryCount: reference.retryCount,
                  order: reference.order,
                  description: reference.description,
                );
              }()
            else
              reference,
        ];
      }
      if (changed) {
        final complete = requiredRvPhotoSlots.every(
          (slot) => (photos[slot] ?? const []).any(
            (photo) => photo.status == RvPhotoUploadStatus.verified,
          ),
        );
        await save(
          draft.copyWith(
            photos: photos,
            photosStatus: complete ? RvPartStatus.synced : RvPartStatus.pending,
            updatedAt: DateTime.now().toUtc(),
          ),
        );
      }
    }
    return repaired;
  }

  Future<int> reconcileOrphanedInspectionQueue({
    required String creatorId,
  }) async {
    final queueBox = Hive.box<String>('sync_queue');
    final orphanKeys = <Object>[];
    for (final entry in queueBox.toMap().entries) {
      try {
        final item = SyncQueueItem.fromJson(
          Map<String, dynamic>.from(jsonDecode(entry.value) as Map),
        );
        final inspectionId = item.inspectionId;
        if (item.ownerUserId != creatorId ||
            inspectionId == null ||
            inspectionId.isEmpty ||
            item.entityType.toLowerCase().contains('photo') ||
            visualRepository.findById(inspectionId) != null) {
          continue;
        }
        orphanKeys.add(entry.key);
      } on FormatException {
        // Una entrada ilegible se conserva para diagnóstico; no se borra a ciegas.
      }
    }
    if (orphanKeys.isNotEmpty) await queueBox.deleteAll(orphanKeys);
    return orphanKeys.length;
  }
}

RvDraft upgradeDraftChecklist(RvDraft draft, DynamicChecklist current) {
  if (draft.isReadOnly ||
      draft.checklistId != current.id ||
      draft.checklistVersion != current.version) {
    return draft;
  }
  final storedIds = draft.checklist.sections
      .expand((section) => section.items)
      .map((item) => item.id)
      .toSet();
  final currentIds = current.sections
      .expand((section) => section.items)
      .map((item) => item.id)
      .toSet();
  if (!currentIds.containsAll(storedIds) ||
      (currentIds.length == storedIds.length &&
          draft.checklist.etag == current.etag)) {
    return draft;
  }
  return RvDraft.fromJson({
    ...draft.toJson(),
    'checklistSnapshot': current.toJson(),
    'updatedAt': DateTime.now().toUtc().toIso8601String(),
  });
}

// ignore_for_file: curly_braces_in_flow_control_structures
