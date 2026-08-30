import 'package:ddr001diag/features/inspections/domain/rv_versioning.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('interpreta versión creada e idempotente', () {
    for (final name in ['created', 'already_created']) {
      final result = RvVersionResult.fromJson({
        'result': name,
        'visualReportId': 'report',
        'versionId': 'version',
        'currentVersionId': 'version',
        'versionNumber': 2,
      });
      expect(result.visualReportId, 'report');
      expect(result.versionNumber, 2);
    }
  });

  test('conflicto conserva vigente y propuesta por separado', () {
    final result = RvVersionResult.fromJson({
      'result': 'conflict',
      'visualReportId': 'report',
      'currentVersionId': 'server',
      'proposedVersionId': 'mobile',
      'conflictId': 'conflict',
    });
    expect(result.kind, RvVersionResultKind.conflict);
    expect(result.currentVersionId, 'server');
    expect(result.proposedVersionId, 'mobile');
  });

  test('rechazo posterior a validación es resultado de dominio', () {
    final result = RvVersionResult.fromJson({
      'result': 'forbidden_after_validation',
      'visualReportId': 'report',
      'currentVersionId': 'server',
    });
    expect(result.kind, RvVersionResultKind.forbiddenAfterValidation);
  });
}
