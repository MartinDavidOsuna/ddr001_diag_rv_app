import '../../../domain/enums/app_enums.dart';
import '../../../domain/inspections/visual_inspection.dart';
import 'rv_draft.dart';

const rvDraftDocumentStorageKey = 'rvDynamicDraft';

enum RvVisualDocumentKind { active, normalCompleted, inactiveClosure }

RvVisualDocumentKind classifyRvVisualDocument(VisualInspection inspection) {
  final raw = inspection.unknownFields[rvDraftDocumentStorageKey];
  if (raw is Map) {
    try {
      final draft = RvDraft.fromJson(Map<String, dynamic>.from(raw));
      if (draft.isInactive || draft.inactiveClosure != null) {
        return RvVisualDocumentKind.inactiveClosure;
      }
    } on Object {
      // A malformed legacy payload is not reclassified without evidence.
    }
  }
  return inspection.status == InspectionStatus.completed
      ? RvVisualDocumentKind.normalCompleted
      : RvVisualDocumentKind.active;
}

bool isNormalCompletedRvDocument(VisualInspection inspection) =>
    classifyRvVisualDocument(inspection) ==
    RvVisualDocumentKind.normalCompleted;

bool isInactiveRvDocument(VisualInspection inspection) =>
    classifyRvVisualDocument(inspection) ==
    RvVisualDocumentKind.inactiveClosure;
