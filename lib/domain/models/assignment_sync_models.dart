import 'app_models.dart';

enum AssignmentSyncScenario {
  noChanges,
  twoNew,
  updatedAndRemoved,
  temporaryError,
}

class AssignmentSyncResult {
  const AssignmentSyncResult({
    required this.nextCursor,
    required this.newAssignments,
    required this.updatedAssignments,
    required this.removedIds,
    required this.message,
  });
  final String nextCursor, message;
  final List<Hydrant> newAssignments, updatedAssignments;
  final List<String> removedIds;
  int get newCount => newAssignments.length;
  int get updatedCount => updatedAssignments.length;
  int get removedCount => removedIds.length;
}

/// Contrato futuro incremental. La solicitud remota incluirá userId,
/// brigadeId, deviceId, cursor y catalogVersion. La respuesta incluirá
/// nextCursor, hasMore, altas, actualizaciones, retiros, hidrantes modificados
/// y versión de catálogos. No se usa polling; futuras consultas automáticas
/// respetarán [minimumAutomaticInterval].
abstract interface class AssignmentSyncService {
  Duration get minimumAutomaticInterval;
  Future<AssignmentSyncResult> synchronize({
    required AssignmentSyncScenario scenario,
    required String userId,
    required String brigadeId,
    required String deviceId,
    String? cursor,
    String? catalogVersion,
  });
}
