enum RvVersionResultKind {
  created,
  alreadyCreated,
  conflict,
  forbiddenAfterValidation,
}

class RvVersionResult {
  const RvVersionResult({
    required this.kind,
    required this.visualReportId,
    this.versionId,
    this.versionNumber,
    this.currentVersionId,
    this.proposedVersionId,
    this.conflictId,
  });

  final RvVersionResultKind kind;
  final String visualReportId;
  final String? versionId, currentVersionId, proposedVersionId, conflictId;
  final int? versionNumber;

  factory RvVersionResult.fromJson(Map<String, dynamic> json) {
    final result = json['result']?.toString();
    final kind = switch (result) {
      'created' => RvVersionResultKind.created,
      'already_created' => RvVersionResultKind.alreadyCreated,
      'conflict' => RvVersionResultKind.conflict,
      'forbidden_after_validation' =>
        RvVersionResultKind.forbiddenAfterValidation,
      _ => throw const FormatException('Unknown visual report version result'),
    };
    return RvVersionResult(
      kind: kind,
      visualReportId: json['visualReportId'] as String,
      versionId: json['versionId'] as String?,
      versionNumber: json['versionNumber'] as int?,
      currentVersionId: json['currentVersionId'] as String?,
      proposedVersionId: json['proposedVersionId'] as String?,
      conflictId: json['conflictId'] as String?,
    );
  }
}
