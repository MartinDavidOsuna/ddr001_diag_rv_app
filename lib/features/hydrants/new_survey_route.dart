import '../../domain/models/app_models.dart';

const newSurveyPath = '/hydrants/new';

String newSurveyRouteForHydrant(String hydrantId) {
  return Uri(
    path: newSurveyPath,
    queryParameters: {'hydrantId': hydrantId},
  ).toString();
}

List<Hydrant> prioritizeSelectedHydrant(
  Iterable<Hydrant> hydrants,
  String? selectedHydrantId,
) {
  final items = hydrants.toList();
  if (selectedHydrantId == null || selectedHydrantId.isEmpty) return items;
  final selectedIndex = items.indexWhere(
    (hydrant) => hydrant.id == selectedHydrantId,
  );
  if (selectedIndex <= 0) return items;
  final selected = items.removeAt(selectedIndex);
  return [selected, ...items];
}

bool containsSelectedHydrant(
  Iterable<Hydrant> hydrants,
  String? selectedHydrantId,
) {
  return selectedHydrantId != null &&
      selectedHydrantId.isNotEmpty &&
      hydrants.any((hydrant) => hydrant.id == selectedHydrantId);
}
