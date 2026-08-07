import '../../domain/enums/app_enums.dart';
import '../../domain/models/app_models.dart';
import '../inspections/domain/rv_draft.dart';
import '../inspections/domain/rv_sync_state.dart';

enum RvWorkGroup {
  inProgress,
  pendingSync,
  submitted,
  validated,
  returned,
  conflicts,
}

extension RvWorkGroupLabel on RvWorkGroup {
  String get label => switch (this) {
    RvWorkGroup.inProgress => 'En proceso',
    RvWorkGroup.pendingSync => 'Pendientes de sincronizar',
    RvWorkGroup.submitted => 'Enviados',
    RvWorkGroup.validated => 'Validados',
    RvWorkGroup.returned => 'Devueltos',
    RvWorkGroup.conflicts => 'Conflictos',
  };
}

abstract final class RvWorkDashboardProjection {
  static RvWorkGroup forDraft(RvDraft draft) {
    if (draft.localStatus == RvLocalStatus.conflict ||
        draft.localStatus == RvLocalStatus.versionConflict) {
      return RvWorkGroup.conflicts;
    }
    if (draft.remoteStatus == 'validated') return RvWorkGroup.validated;
    if (const {
      'returned',
      'rejected',
      'reopened',
    }.contains(draft.remoteStatus)) {
      return RvWorkGroup.returned;
    }
    if (draft.localStatus == RvLocalStatus.submitted) {
      return RvWorkGroup.submitted;
    }
    if (draft.lastSyncError != null ||
        const {
          RvLocalStatus.pendingCreate,
          RvLocalStatus.creating,
          RvLocalStatus.pendingAnswers,
          RvLocalStatus.pendingLocation,
          RvLocalStatus.pendingSignal,
          RvLocalStatus.pendingPhotos,
          RvLocalStatus.submitPending,
          RvLocalStatus.pendingVersion,
          RvLocalStatus.syncingVersion,
          RvLocalStatus.requiresAuthentication,
          RvLocalStatus.syncError,
        }.contains(draft.localStatus) ||
        draft.answersStatus == RvPartStatus.pending ||
        draft.answersStatus == RvPartStatus.error ||
        draft.locationStatus == RvPartStatus.pending ||
        draft.locationStatus == RvPartStatus.error ||
        draft.signalStatus == RvPartStatus.pending ||
        draft.signalStatus == RvPartStatus.error ||
        draft.photos.values
            .expand((items) => items)
            .any((photo) => photo.status != RvPhotoUploadStatus.verified)) {
      return RvWorkGroup.pendingSync;
    }
    return RvWorkGroup.inProgress;
  }

  static RvWorkGroup forRemote(InspectionStatus status) => switch (status) {
    InspectionStatus.validated => RvWorkGroup.validated,
    InspectionStatus.returned => RvWorkGroup.returned,
    InspectionStatus.completed => RvWorkGroup.submitted,
    _ => RvWorkGroup.inProgress,
  };

  static Map<RvWorkGroup, Set<String>> byHydrant({
    required List<RvDraft> drafts,
    required List<Hydrant> hydrants,
  }) {
    final result = {for (final group in RvWorkGroup.values) group: <String>{}};
    final byHydrant = <String, List<RvDraft>>{};
    for (final draft in drafts) {
      byHydrant.putIfAbsent(draft.hydrantId, () => []).add(draft);
    }
    for (final hydrant in hydrants) {
      final local = [...?byHydrant[hydrant.id]]
        ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      final current =
          local.where((draft) => !draft.isReadOnly).firstOrNull ??
          local.firstOrNull;
      if (current == null &&
          !hydrant.hasConflict &&
          !const {
            InspectionStatus.completed,
            InspectionStatus.validated,
            InspectionStatus.returned,
          }.contains(hydrant.f02a.status)) {
        continue;
      }
      final group = current != null
          ? forDraft(current)
          : hydrant.hasConflict
          ? RvWorkGroup.conflicts
          : forRemote(hydrant.f02a.status);
      result[group]!.add(hydrant.id);
    }
    return result;
  }
}
