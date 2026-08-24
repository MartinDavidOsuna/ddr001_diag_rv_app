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
  static bool isEmptyLegacySyncShell(RvDraft draft) =>
      draft.serverInspectionId != null &&
      draft.remoteStatus == 'in_progress' &&
      draft.answers.isEmpty &&
      draft.answersStatus == RvPartStatus.synced &&
      draft.photos.values.expand((items) => items).isEmpty &&
      draft.submitStatus == RvPartStatus.notCaptured &&
      const {
        RvLocalStatus.pendingAnswers,
        RvLocalStatus.pendingLocation,
        RvLocalStatus.pendingSignal,
      }.contains(draft.localStatus);

  static List<Hydrant> personalWorkHydrants({
    required List<Hydrant> assigned,
    required List<Hydrant> catalog,
    required List<RvDraft> drafts,
  }) {
    final result = <String, Hydrant>{
      for (final hydrant in assigned) hydrant.id: hydrant,
    };
    final localWorkIds = drafts.map((draft) => draft.hydrantId).toSet();
    for (final hydrant in catalog) {
      if (localWorkIds.contains(hydrant.id)) {
        result.putIfAbsent(hydrant.id, () => hydrant);
      }
    }
    return result.values.toList(growable: false);
  }

  static List<Hydrant> recent({
    required List<RvDraft> drafts,
    required List<Hydrant> hydrants,
    int limit = 5,
  }) {
    final hydrantsById = {for (final hydrant in hydrants) hydrant.id: hydrant};
    final timestamps = <String, DateTime>{};
    for (final draft in drafts) {
      if (!hydrantsById.containsKey(draft.hydrantId)) continue;
      final previous = timestamps[draft.hydrantId];
      if (previous == null || draft.updatedAt.isAfter(previous)) {
        timestamps[draft.hydrantId] = draft.updatedAt;
      }
    }
    for (final hydrant in hydrants) {
      final isRemoteReport =
          hydrant.officialInspectionId != null ||
          hydrant.hasConflict ||
          const {
            InspectionStatus.completed,
            InspectionStatus.validated,
            InspectionStatus.returned,
          }.contains(hydrant.f02a.status);
      if (!isRemoteReport) continue;
      timestamps.putIfAbsent(
        hydrant.id,
        () =>
            hydrant.lastStatusChangedAt ??
            DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      );
    }
    final result =
        timestamps.entries
            .map(
              (entry) => (hydrant: hydrantsById[entry.key]!, at: entry.value),
            )
            .toList()
          ..sort((a, b) => b.at.compareTo(a.at));
    return result.take(limit).map((entry) => entry.hydrant).toList();
  }

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
      final hasSubmittedRevision = local.any(
        (draft) => draft.localStatus == RvLocalStatus.submitted,
      );
      final visible = local
          .where(
            (draft) =>
                !isEmptyLegacySyncShell(draft) &&
                !(hasSubmittedRevision && draft.remoteStatus == 'conflict'),
          )
          .toList(growable: false);
      final current =
          visible.where((draft) => !draft.isReadOnly).firstOrNull ??
          visible.firstOrNull;
      final hasOfficialRemoteState =
          hydrant.officialInspectionId != null ||
          const {
            InspectionStatus.completed,
            InspectionStatus.validated,
            InspectionStatus.returned,
          }.contains(hydrant.f02a.status);
      if (current == null && !hydrant.hasConflict && !hasOfficialRemoteState) {
        continue;
      }
      final group = hydrant.hasConflict
          ? RvWorkGroup.conflicts
          : current != null
          ? forDraft(current)
          : forRemote(hydrant.f02a.status);
      result[group]!.add(hydrant.id);
    }
    return result;
  }
}
