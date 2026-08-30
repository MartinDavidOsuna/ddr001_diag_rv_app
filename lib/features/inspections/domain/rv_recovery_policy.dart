import 'rv_draft.dart';

bool hasMeaningfulLocalData(RvDraft draft) {
  if (draft.answers.isNotEmpty || draft.photoCount > 0) return true;
  if (draft.location != null || draft.signal != null) return true;
  if (draft.parcelValveConfiguration != null) return true;
  if (draft.generalObservations?.trim().isNotEmpty == true) return true;
  if (draft.checklistSnapshot['generalContent'] != null) return true;
  if (draft.activeFormStep > 0 || draft.navigationQuestionId != null) {
    return true;
  }
  return draft.serverInspectionId != null ||
      draft.serverHydrantId != null ||
      draft.officialInspectionId != null ||
      draft.visualReportId != null;
}

int meaningfulLocalDataScore(RvDraft draft) {
  var score = draft.answers.length * 100 + draft.photoCount * 50;
  if (draft.location != null) score += 25;
  if (draft.signal != null) score += 20;
  if (draft.parcelValveConfiguration != null) score += 30;
  if (draft.generalObservations?.trim().isNotEmpty == true) score += 15;
  if (draft.serverInspectionId != null) score += 10000;
  if (draft.serverHydrantId != null) score += 5000;
  if (draft.officialInspectionId != null) score += 20000;
  return score;
}

int compareCanonicalDrafts(RvDraft left, RvDraft right) {
  final score = meaningfulLocalDataScore(
    left,
  ).compareTo(meaningfulLocalDataScore(right));
  if (score != 0) return score;
  final updated = left.updatedAt.compareTo(right.updatedAt);
  if (updated != 0) return updated;
  return -left.clientInspectionId.compareTo(right.clientInspectionId);
}

RvDraft selectCanonicalDraft(Iterable<RvDraft> drafts) {
  final values = drafts.toList(growable: false)..sort(compareCanonicalDrafts);
  if (values.isEmpty) throw ArgumentError.value(drafts, 'drafts', 'empty');
  return values.last;
}
