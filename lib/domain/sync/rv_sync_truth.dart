import 'dart:convert';

import 'package:hive_ce/hive.dart';

import '../../data/local/media_work_item_codec.dart';
import '../../features/inspections/domain/rv_draft.dart';
import '../../features/inspections/domain/rv_sync_state.dart';
import '../integrity/operation_journal.dart';
import '../media/inspection_photo.dart';

class RvSyncTruth {
  const RvSyncTruth({required this.synchronized, required this.reasons});
  final bool synchronized;
  final Set<String> reasons;
}

/// Single local truth consumed by every projection through AppState.
abstract final class RvSyncTruthService {
  static RvSyncTruth evaluate(RvDraft draft) {
    final reasons = <String>{};
    final photoBox = Hive.box<String>('inspection_photos_v1');
    final work = Hive.box<String>('media_work_queue_v1');
    final sync = Hive.box<String>('media_sync_queue');
    final references = draft.photos.values.expand((items) => items).toList();
    final ids = references.map((item) => item.photoId).toSet();
    if (draft.isInactive) {
      if (draft.inactiveClosure?.syncStatus !=
          RvInactiveClosureSyncStatus.remoteVerified) {
        reasons.add('inactiveClosureContractPending');
      }
    } else if (!draft.hasAllPhotoSlots) {
      reasons.add('requiredContentMissing');
    }
    for (final reference in references) {
      final raw = photoBox.get(reference.photoId);
      if (raw == null) {
        reasons.add('photoDocumentMissing');
        continue;
      }
      try {
        final photo = InspectionPhoto.fromJson(
          Map<String, dynamic>.from(jsonDecode(raw) as Map),
        );
        if (!photo.isSynchronized) reasons.add('photoUnconfirmed');
      } on Object {
        reasons.add('photoUnreadable');
      }
      final statuses = {
        MediaWorkItemCodec.statusOf(
          reference.photoId,
          work.get(reference.photoId),
        ),
        MediaWorkItemCodec.statusOf(
          reference.photoId,
          sync.get(reference.photoId),
        ),
      };
      if (statuses.any((status) => status != null && status != 'verified')) {
        reasons.add('queuePending');
      }
    }
    for (final raw in photoBox.values) {
      try {
        final photo = InspectionPhoto.fromJson(
          Map<String, dynamic>.from(jsonDecode(raw) as Map),
        );
        if (!photo.isDeleted &&
            photo.inspectionId == draft.clientInspectionId &&
            !ids.contains(photo.id)) {
          reasons.add('orphanPhoto');
        }
      } on Object {
        reasons.add('photoUnreadable');
      }
    }
    for (final raw in Hive.box<String>('operation_journal_v1').values) {
      try {
        final entry = OperationJournalEntry.fromJson(
          Map<String, dynamic>.from(jsonDecode(raw) as Map),
        );
        if (entry.status != JournalStatus.committed &&
            entry.entityIds.contains(draft.clientInspectionId)) {
          reasons.add('journalIncomplete');
        }
      } on Object {
        reasons.add('journalUnreadable');
      }
    }
    if (draft.localStatus == RvLocalStatus.conflict ||
        draft.localStatus == RvLocalStatus.versionConflict) {
      reasons.add('conflictPending');
    }
    return RvSyncTruth(synchronized: reasons.isEmpty, reasons: reasons);
  }
}
