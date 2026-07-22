import 'package:ddr001diag/domain/workflow/current_report_revision_resolver.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const resolver = CurrentReportRevisionResolver();
  final base = DateTime.utc(2026, 7, 15);

  ReportRevisionNode node(
    String id,
    int revision, {
    String? previous,
    String status = 'completed',
  }) => ReportRevisionNode(
    reportId: id,
    reportType: 'f02A',
    hydrantId: 'hydrant-1104',
    status: status,
    revisionNumber: revision,
    revisionOfReportId: revision == 0 ? null : 'rv-0',
    previousRevisionId: previous,
    createdAt: base.add(Duration(minutes: revision)),
  );

  test('elige la hoja de una cadena lineal sin confiar en activeRevision', () {
    final result = resolver.resolve([
      node('rv-0', 0),
      node('rv-1', 1, previous: 'rv-0'),
      node('rv-2', 2, previous: 'rv-1'),
    ]);

    expect(result.resolved, isTrue);
    expect(result.original?.reportId, 'rv-0');
    expect(result.activeRevision?.reportId, 'rv-2');
    expect(result.chain.map((value) => value.reportId), ['rv-0', 'rv-1', 'rv-2']);
  });

  test('una bifurcación no elige silenciosamente una revisión', () {
    final result = resolver.resolve([
      node('rv-0', 0),
      node('rv-1a', 1, previous: 'rv-0'),
      node('rv-1b', 1, previous: 'rv-0'),
    ]);

    expect(result.status, RevisionResolutionStatus.ambiguous);
    expect(result.activeRevision, isNull);
    expect(result.problemCodes, contains('fork:rv-0'));
  });

  test('detecta ciclos y referencias ausentes conservando los nodos', () {
    final result = resolver.resolve([
      node('rv-1', 1, previous: 'rv-2'),
      node('rv-2', 2, previous: 'rv-1'),
      node('rv-3', 3, previous: 'missing'),
    ]);

    expect(result.resolved, isFalse);
    expect(result.problemCodes.any((value) => value.startsWith('cycle:')), isTrue);
    expect(
      result.problemCodes,
      contains('missingPrevious:rv-3:missing'),
    );
  });
}
