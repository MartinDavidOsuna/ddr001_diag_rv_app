import 'package:hive_ce/hive.dart';
import 'package:uuid/uuid.dart';

import '../../core/persistence/versioned_json_codec.dart';
import '../../domain/integrity/integrity_models.dart';
import '../../domain/workflow/current_report_revision_resolver.dart';

class ReportRevisionResolverService {
  const ReportRevisionResolverService({
    this.resolver = const CurrentReportRevisionResolver(),
  });

  final CurrentReportRevisionResolver resolver;

  ({CurrentReportRevisionResolution resolution, List<IntegrityIssue> issues})
  resolveForHydrant({required String hydrantId, required String reportType}) {
    final boxName = reportType == 'f02A'
        ? 'visual_inspections_v1'
        : 'functional_inspections_v1';
    final nodes = <ReportRevisionNode>[];
    final issues = <IntegrityIssue>[];
    for (final entry in Hive.box<String>(boxName).toMap().entries) {
      try {
        final json = VersionedJsonCodec.decode(entry.value).payload;
        if (json['hydrantId'] != hydrantId) continue;
        nodes.add(
          ReportRevisionNode(
            reportId: json['id'] as String? ?? '${entry.key}',
            reportType: reportType,
            hydrantId: hydrantId,
            status: json['status'] as String? ?? 'draft',
            revisionOfReportId: json['revisionOfReportId'] as String?,
            previousRevisionId: json['previousRevisionId'] as String?,
            revisionNumber: json['revisionNumber'] as int? ?? 0,
            createdAt:
                DateTime.tryParse(
                  json['createdAt'] as String? ?? '',
                )?.toUtc() ??
                DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
          ),
        );
      } on Object catch (error) {
        issues.add(
          _issue(
            entityType: boxName,
            entityId: '${entry.key}',
            message: 'Documento de revisión ilegible: $error',
          ),
        );
      }
    }
    final resolution = resolver.resolve(nodes);
    for (final code in resolution.problemCodes) {
      issues.add(
        _issue(
          entityType: reportType,
          entityId: hydrantId,
          message: 'Cadena de revisiones ambigua: $code',
        ),
      );
    }
    return (resolution: resolution, issues: issues);
  }

  IntegrityIssue _issue({
    required String entityType,
    required String entityId,
    required String message,
  }) => IntegrityIssue(
    id: const Uuid().v4(),
    type: IntegrityIssueType.invalidRevisionReference,
    severity: IntegritySeverity.critical,
    entityType: entityType,
    entityId: entityId,
    userMessage: 'Revisión pendiente de resolver.',
    technicalMessage: message,
    recommendedAction: RecoveryAction.manualReview,
  );
}
