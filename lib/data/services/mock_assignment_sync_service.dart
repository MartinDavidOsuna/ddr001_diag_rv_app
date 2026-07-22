import '../../domain/enums/app_enums.dart';
import '../../domain/models/app_models.dart';
import '../../domain/models/assignment_sync_models.dart';

class MockAssignmentSyncService implements AssignmentSyncService {
  @override
  Duration get minimumAutomaticInterval => const Duration(minutes: 15);
  @override
  Future<AssignmentSyncResult> synchronize({
    required AssignmentSyncScenario scenario,
    required String userId,
    required String brigadeId,
    required String deviceId,
    String? cursor,
    String? catalogVersion,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 900));
    if (scenario == AssignmentSyncScenario.temporaryError) {
      throw const AssignmentSyncException(
        'Error temporal de conexión. Intenta nuevamente.',
      );
    }
    final noneB = const InspectionSummary(
      type: InspectionType.f02B,
      status: InspectionStatus.notRequired,
      progress: 0,
    );
    final pendingA = const InspectionSummary(
      type: InspectionType.f02A,
      status: InspectionStatus.pending,
      progress: 0,
    );
    final additions = scenario == AssignmentSyncScenario.twoNew
        ? [
            Hydrant(
              id: '1401',
              code: 'DDR001-HID-1401',
              locality: 'Pabellón de Arteaga',
              parcel: 'P-1201',
              priority: PriorityLevel.medium,
              access: AccessType.vehicle,
              syncStatus: SyncStatus.synced,
              f02a: pendingA,
              f02b: noneB,
              latitude: .57,
              longitude: .17,
            ),
            Hydrant(
              id: '1402',
              code: 'DDR001-HID-1402',
              locality: 'Rincón de Romos',
              parcel: 'P-1202',
              priority: PriorityLevel.high,
              access: AccessType.both,
              syncStatus: SyncStatus.synced,
              f02a: pendingA,
              f02b: noneB,
              latitude: .67,
              longitude: .72,
            ),
          ]
        : <Hydrant>[];
    final updates = scenario == AssignmentSyncScenario.updatedAndRemoved
        ? [
            Hydrant(
              id: '128',
              code: 'DDR001-HID-0128',
              locality: 'Tepezalá Centro',
              parcel: 'P-0245',
              priority: PriorityLevel.high,
              access: AccessType.walking,
              syncStatus: SyncStatus.synced,
              f02a: pendingA,
              f02b: noneB,
              latitude: .61,
              longitude: .51,
            ),
          ]
        : <Hydrant>[];
    final removed = scenario == AssignmentSyncScenario.updatedAndRemoved
        ? <String>['1388']
        : <String>[];
    return AssignmentSyncResult(
      nextCursor: 'demo-${DateTime.now().millisecondsSinceEpoch}',
      newAssignments: additions,
      updatedAssignments: updates,
      removedIds: removed,
      message: additions.isEmpty && updates.isEmpty && removed.isEmpty
          ? 'Sin cambios'
          : 'Asignaciones actualizadas',
    );
  }
}

class AssignmentSyncException implements Exception {
  const AssignmentSyncException(this.message);
  final String message;
  @override
  String toString() => message;
}
