import 'rv_draft.dart';
import 'rv_sync_state.dart';
import 'rv_validator.dart';

enum RvHumanGateReason {
  captureIncomplete,
  contractConflict,
  inactiveContractPending,
}

class RvHumanGateDecision {
  const RvHumanGateDecision._(this.reason);

  const RvHumanGateDecision.open() : reason = null;

  final RvHumanGateReason? reason;

  bool get blocksRemoteMutation => reason != null;
  String? get wireReason => switch (reason) {
    RvHumanGateReason.captureIncomplete =>
      'capture_incomplete_requires_technician',
    RvHumanGateReason.contractConflict => 'contract_conflict_requires_action',
    RvHumanGateReason.inactiveContractPending => 'inactive_contract_pending',
    null => null,
  };
}

/// Single policy governing whether an RV draft may cause a remote mutation.
///
/// Remote reads and reconciliation remain allowed. A technician authorizes a
/// complete ordinary review by confirming "Enviar revisión", which persists
/// [RvDraft.remoteMutationAuthorization] before synchronization starts.
class RvHumanGatePolicy {
  const RvHumanGatePolicy({this.validator = const RvValidator()});

  final RvValidator validator;

  RvHumanGateDecision evaluate(RvDraft draft) {
    if (draft.localStatus == RvLocalStatus.inactive ||
        draft.inactiveClosureDraft != null ||
        draft.inactiveClosure != null) {
      return const RvHumanGateDecision._(
        RvHumanGateReason.inactiveContractPending,
      );
    }
    if (draft.localStatus == RvLocalStatus.conflict ||
        draft.localStatus == RvLocalStatus.versionConflict ||
        draft.remoteStatus == 'conflict' ||
        draft.conflictId != null ||
        draft.versionConflictId != null) {
      return const RvHumanGateDecision._(RvHumanGateReason.contractConflict);
    }
    if (!validator.validate(draft).isValid) {
      return const RvHumanGateDecision._(RvHumanGateReason.captureIncomplete);
    }
    // The persisted confirmation never bypasses missing evidence or an active
    // conflict. It only records the explicit human event that started submit.
    if (draft.remoteMutationAuthorization ==
        RvDraft.technicianSubmitAuthorization) {
      return const RvHumanGateDecision.open();
    }
    final persistedReason = switch (draft.remoteMutationBlockReason) {
      'capture_incomplete_requires_technician' =>
        RvHumanGateReason.captureIncomplete,
      'contract_conflict_requires_action' => RvHumanGateReason.contractConflict,
      'inactive_contract_pending' => RvHumanGateReason.inactiveContractPending,
      final String reason when reason.trim().isNotEmpty =>
        RvHumanGateReason.captureIncomplete,
      _ => null,
    };
    if (persistedReason != null) {
      return RvHumanGateDecision._(persistedReason);
    }
    return const RvHumanGateDecision.open();
  }
}
