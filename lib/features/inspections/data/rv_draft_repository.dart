import 'package:uuid/uuid.dart';

import '../../../data/local/visual_inspection_repository.dart';
import '../../../domain/inspections/visual_inspection.dart';
import '../../../domain/models/app_models.dart';
import '../../checklist/data/checklist_models.dart';
import '../domain/rv_draft.dart';

class RvDraftRepository {
  RvDraftRepository(this.visualRepository);
  final VisualInspectionRepository visualRepository;
  static const storageKey = 'rvDynamicDraft';

  Future<RvDraft> openOrCreate({
    required Hydrant hydrant,
    required AppUser user,
    required DynamicChecklist checklist,
  }) async {
    final inspection = await visualRepository.openOrCreate(hydrant, user);
    final existing = fromInspection(inspection);
    if (existing != null) return existing;
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
    for (final inspection in visualRepository.forHydrant(hydrantId)) {
      final draft = fromInspection(inspection);
      if (draft != null && !draft.isReadOnly) return draft;
    }
    return null;
  }

  List<RvDraft> pending() {
    final values = <RvDraft>[];
    for (final inspection in visualRepository.accessible()) {
      final value = fromInspection(inspection);
      if (value != null && !value.isReadOnly) values.add(value);
    }
    return values;
  }

  RvDraft? find(String clientInspectionId) {
    final value = visualRepository.findById(clientInspectionId);
    return value == null ? null : fromInspection(value);
  }

  RvDraft? fromInspection(VisualInspection inspection) {
    final raw = inspection.unknownFields[storageKey];
    return raw is Map ? RvDraft.fromJson(Map<String, dynamic>.from(raw)) : null;
  }

  Future<void> save(RvDraft draft) async {
    final inspection = visualRepository.findById(draft.clientInspectionId);
    if (inspection == null)
      throw StateError('No existe el documento local de inspección.');
    await visualRepository.save(
      inspection.copyWith(
        updatedAt: draft.updatedAt,
        unknownFields: {
          ...inspection.unknownFields,
          storageKey: draft.toJson(),
        },
      ),
    );
  }
}

// ignore_for_file: curly_braces_in_flow_control_structures
