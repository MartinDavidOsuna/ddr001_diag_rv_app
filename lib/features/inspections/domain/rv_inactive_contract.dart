// ignore_for_file: curly_braces_in_flow_control_structures
import 'rv_draft.dart';

/// The API command is deliberately independent of the persisted local envelope.
Map<String, dynamic> inactiveClosureCommand(RvInactiveClosure closure) => {
  'contractVersion': closure.contractVersion,
  'idempotencyKey': closure.idempotencyKey,
  'reasonCode': closure.reasonCode,
  'comment': closure.comment,
  'closedAt': closure.closedAt.toUtc().toIso8601String(),
  'location': {
    'latitude': closure.location.latitude,
    'longitude': closure.location.longitude,
    if (closure.location.altitude != null)
      'altitude': closure.location.altitude,
    if (closure.location.horizontalAccuracy != null)
      'horizontalAccuracy': closure.location.horizontalAccuracy,
    if (closure.location.verticalAccuracy != null)
      'verticalAccuracy': closure.location.verticalAccuracy,
    'source': closure.location.source,
    'capturedAt': closure.location.capturedAt.toUtc().toIso8601String(),
  },
  'photoIds': [...closure.photoIds],
};

bool validInactiveCommand(RvInactiveClosure closure) {
  final uuid = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
  );
  return closure.contractVersion == 1 &&
      closure.reasonCode == noHydrantAtLocationReasonCode &&
      RegExp(r'^[a-zA-Z0-9:_-]{16,120}$').hasMatch(closure.idempotencyKey) &&
      closure.comment.trim().length >= 10 &&
      closure.comment.trim().length <= 500 &&
      closure.location.isValid &&
      const {
        'gps',
        'network',
        'manual',
        'rtk',
      }.contains(closure.location.source) &&
      (closure.location.altitude?.isFinite ?? true) &&
      (closure.location.verticalAccuracy == null ||
          (closure.location.verticalAccuracy!.isFinite &&
              closure.location.verticalAccuracy! >= 0)) &&
      closure.closedAt.millisecondsSinceEpoch > 0 &&
      closure.photoIds.isNotEmpty &&
      closure.photoIds.length <= 20 &&
      closure.photoIds.every(uuid.hasMatch) &&
      closure.photoIds.map((id) => id.toLowerCase()).toSet().length ==
          closure.photoIds.length;
}

bool inactiveReceiptMatches(
  Map<String, dynamic> receipt,
  String inspectionId,
  RvInactiveClosure closure,
) {
  if (!validInactiveCommand(closure) ||
      receipt['status'] != 'inactive' ||
      '${receipt['inspectionId']}'.toLowerCase() !=
          inspectionId.toLowerCase() ||
      receipt['statusLabel'] != 'Ausente' ||
      receipt['alreadyClosed'] is! bool ||
      DateTime.tryParse('${receipt['receivedAt']}') == null ||
      receipt['closure'] is! Map)
    return false;
  return _equivalent(inactiveClosureCommand(closure), receipt['closure']);
}

bool isInactiveRemoteVerified(RvDraft draft) {
  final closure = draft.inactiveClosure;
  final receipt = closure?.remoteReceipt;
  final serverId = draft.serverInspectionId;
  return draft.isInactive &&
      closure != null &&
      closure.syncStatus == RvInactiveClosureSyncStatus.remoteVerified &&
      receipt != null &&
      serverId != null &&
      inactiveReceiptMatches(receipt, serverId, closure);
}

bool _equivalent(Object? a, Object? b, [String? key]) {
  if (key == 'closedAt' || key == 'capturedAt') {
    final left = DateTime.tryParse('$a');
    final right = DateTime.tryParse('$b');
    return left != null &&
        right != null &&
        left.millisecondsSinceEpoch == right.millisecondsSinceEpoch;
  }
  if (key == 'photoIds' && a is List && b is List) {
    final left = a.map((v) => '$v'.toLowerCase()).toSet();
    final right = b.map((v) => '$v'.toLowerCase()).toSet();
    return a.length == b.length &&
        left.length == a.length &&
        left.length == right.length &&
        left.containsAll(right);
  }
  if (a is Map && b is Map) {
    final keys = {...a.keys, ...b.keys};
    return keys.every((k) => _equivalent(a[k], b[k], '$k'));
  }
  return a == b;
}
