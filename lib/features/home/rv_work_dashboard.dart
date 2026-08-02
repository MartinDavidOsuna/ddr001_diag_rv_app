import '../../domain/enums/app_enums.dart';
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
    if (draft.serverInspectionId != null ||
        draft.lastSyncError != null ||
        draft.localStatus.name.contains('pending') ||
        draft.localStatus == RvLocalStatus.syncError) {
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
}
