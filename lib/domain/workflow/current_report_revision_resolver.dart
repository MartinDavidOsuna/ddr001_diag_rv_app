enum RevisionResolutionStatus { resolved, noReports, ambiguous, corrupt }

class ReportRevisionNode {
  const ReportRevisionNode({
    required this.reportId,
    required this.reportType,
    required this.hydrantId,
    required this.status,
    required this.revisionNumber,
    required this.createdAt,
    this.revisionOfReportId,
    this.previousRevisionId,
  });

  final String reportId, reportType, hydrantId, status;
  final String? revisionOfReportId, previousRevisionId;
  final int revisionNumber;
  final DateTime createdAt;

  bool get cancelled => status == 'cancelled';
  bool get pending => status == 'pendingReview';
}

class CurrentReportRevisionResolution {
  const CurrentReportRevisionResolution({
    required this.status,
    required this.chain,
    required this.cancelledRevisions,
    required this.pendingRevisions,
    required this.problemCodes,
    this.original,
    this.activeRevision,
  });

  final RevisionResolutionStatus status;
  final ReportRevisionNode? original, activeRevision;
  final List<ReportRevisionNode> chain, cancelledRevisions, pendingRevisions;
  final List<String> problemCodes;
  bool get resolved => status == RevisionResolutionStatus.resolved;
}

class CurrentReportRevisionResolver {
  const CurrentReportRevisionResolver();

  CurrentReportRevisionResolution resolve(List<ReportRevisionNode> reports) {
    if (reports.isEmpty) {
      return const CurrentReportRevisionResolution(
        status: RevisionResolutionStatus.noReports,
        chain: [],
        cancelledRevisions: [],
        pendingRevisions: [],
        problemCodes: [],
      );
    }
    final byId = {for (final report in reports) report.reportId: report};
    final problems = <String>[];
    final children = <String, List<ReportRevisionNode>>{};
    for (final report in reports) {
      final previous = report.previousRevisionId;
      if (previous != null && previous.isNotEmpty) {
        if (!byId.containsKey(previous)) {
          problems.add('missingPrevious:${report.reportId}:$previous');
        }
        children.putIfAbsent(previous, () => []).add(report);
      }
    }
    for (final entry in children.entries) {
      if (entry.value.where((item) => !item.cancelled).length > 1) {
        problems.add('fork:${entry.key}');
      }
    }
    for (final report in reports) {
      final seen = <String>{};
      ReportRevisionNode? cursor = report;
      while (cursor != null && cursor.previousRevisionId != null) {
        if (!seen.add(cursor.reportId)) {
          problems.add('cycle:${cursor.reportId}');
          break;
        }
        cursor = byId[cursor.previousRevisionId];
      }
    }
    final roots = reports.where((report) {
      final previous = report.previousRevisionId;
      return previous == null || previous.isEmpty;
    }).toList();
    roots.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final original = roots.firstOrNull;
    final familyIds = <String>{};
    if (original != null) {
      final pending = <ReportRevisionNode>[original];
      while (pending.isNotEmpty) {
        final node = pending.removeLast();
        if (!familyIds.add(node.reportId)) continue;
        pending.addAll(children[node.reportId] ?? const []);
      }
    }
    final chain = <ReportRevisionNode>[];
    if (original != null) {
      var current = original;
      final visited = <String>{};
      while (visited.add(current.reportId)) {
        chain.add(current);
        final next =
            children[current.reportId]
                ?.where((item) => !item.cancelled)
                .toList() ??
            const [];
        if (next.length != 1) break;
        final candidate = next.single;
        if (candidate.revisionNumber <= current.revisionNumber) {
          problems.add('revisionOrder:${candidate.reportId}');
          break;
        }
        current = candidate;
      }
    }
    final family = reports.where((item) => familyIds.contains(item.reportId));
    final nonCancelledLeaves = family
        .where((item) => !item.cancelled)
        .where(
          (item) => (children[item.reportId] ?? const [])
              .where((child) => !child.cancelled)
              .isEmpty,
        )
        .toList();
    if (nonCancelledLeaves.length != 1) {
      problems.add('activeLeafCount:${nonCancelledLeaves.length}');
    }
    final valid = problems.isEmpty && nonCancelledLeaves.length == 1;
    return CurrentReportRevisionResolution(
      status: valid
          ? RevisionResolutionStatus.resolved
          : RevisionResolutionStatus.ambiguous,
      original: original,
      activeRevision: valid ? nonCancelledLeaves.single : null,
      chain: chain,
      cancelledRevisions: family.where((item) => item.cancelled).toList(),
      pendingRevisions: family.where((item) => item.pending).toList(),
      problemCodes: problems.toSet().toList(),
    );
  }
}
