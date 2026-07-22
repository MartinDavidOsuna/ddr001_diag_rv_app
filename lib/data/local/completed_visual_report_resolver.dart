import '../../core/persistence/versioned_json_codec.dart';
import '../../domain/enums/app_enums.dart';
import '../../domain/inspections/visual_inspection.dart';
import '../../domain/models/app_models.dart';
import 'visual_inspection_repository.dart';

enum CompletedVisualResolutionSource { document, legacyProjection, none }

class CompletedVisualReportResolution {
  const CompletedVisualReportResolution({
    required this.source,
    this.report,
    this.legacyReportId,
  });
  final CompletedVisualResolutionSource source;
  final VisualInspection? report;
  final String? legacyReportId;
  bool get found => source != CompletedVisualResolutionSource.none;
  String? get reportId => report?.id ?? legacyReportId;
}

class CompletedVisualReportResolver {
  const CompletedVisualReportResolver(this.repository);
  final VisualInspectionRepository repository;

  CompletedVisualReportResolution findLatestCompletedForHydrant(
    Hydrant hydrant,
  ) {
    final candidates = <VisualInspection>[];
    for (final raw in repository.documents.values) {
      try {
        final report = VisualInspection.fromJson(
          VersionedJsonCodec.decode(raw).payload,
        );
        if (_sameCanonicalId(report.hydrantId, hydrant.id) &&
            report.status == InspectionStatus.completed) {
          candidates.add(report);
        }
      } on Object {
        continue;
      }
    }
    candidates.sort((a, b) {
      final left = a.completedAt ?? a.updatedAt;
      final right = b.completedAt ?? b.updatedAt;
      return right.compareTo(left);
    });
    if (candidates.isNotEmpty) {
      return CompletedVisualReportResolution(
        source: CompletedVisualResolutionSource.document,
        report: candidates.first,
      );
    }
    if (hydrant.f02a.status == InspectionStatus.completed) {
      return CompletedVisualReportResolution(
        source: CompletedVisualResolutionSource.legacyProjection,
        legacyReportId: 'legacy:${hydrant.id}:f02A',
      );
    }
    return const CompletedVisualReportResolution(
      source: CompletedVisualResolutionSource.none,
    );
  }

  bool _sameCanonicalId(String left, String right) =>
      left.trim().toLowerCase() == right.trim().toLowerCase();
}
