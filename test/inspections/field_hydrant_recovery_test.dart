import 'package:ddr001diag/features/inspections/domain/rv_draft.dart';
import 'package:ddr001diag/features/inspections/domain/rv_sync_state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('draft v58 sin serverHydrantId sigue siendo compatible', () {
    final draft = RvDraft.fromJson(_fixture('486-2'));

    expect(draft.accountNumber, '486-2');
    expect(draft.serverInspectionId, isNull);
    expect(draft.serverHydrantId, isNull);
    expect(draft.currentStep, RvSyncStep.create);
  });

  for (final account in const ['1134', '486-2', '367-2', '446', '472-2']) {
    test('$account conserva identidad exacta al enlazar hidrante servidor', () {
      final draft = RvDraft.fromJson(_fixture(account));
      final linked = draft.copyWith(
        serverInspectionId: 'inspection-$account',
        serverHydrantId: 'server-hydrant-$account',
      );

      expect(linked.hydrantId, 'local-hydrant-$account');
      expect(linked.accountNumber, account);
      expect(linked.serverHydrantId, 'server-hydrant-$account');
      expect(linked.toJson()['serverHydrantId'], 'server-hydrant-$account');
    });
  }
}

Map<String, dynamic> _fixture(String account) => {
  'clientInspectionId': 'client-$account',
  'hydrantId': 'local-hydrant-$account',
  'accountNumber': account,
  'fieldSessionId': 'field-session',
  'checklistId': 'rv-v2',
  'checklistVersion': 2,
  'checklistSnapshot': <String, dynamic>{},
  'createdAt': DateTime.utc(2026, 8, 11).toIso8601String(),
  'updatedAt': DateTime.utc(2026, 8, 13).toIso8601String(),
  'currentStep': 'create',
};
