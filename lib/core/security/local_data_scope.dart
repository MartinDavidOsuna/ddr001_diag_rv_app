import 'f02a_scoped_identity.dart';

class LocalDataScope {
  const LocalDataScope({
    required this.environment,
    required this.accountId,
    required this.userId,
    required this.brigadeId,
    required this.role,
  });

  final String environment, accountId, userId, brigadeId, role;

  bool get isUsable =>
      environment.trim().isNotEmpty &&
      accountId.trim().isNotEmpty &&
      userId.trim().isNotEmpty;

  bool get isAdministrator => role.toLowerCase() == 'admin';

  String get namespace =>
      '${canonicalScopeSegment(environment) ?? ''}/'
      '${canonicalScopeSegment(accountId) ?? ''}/'
      '${canonicalScopeSegment(userId) ?? ''}';

  bool owns({required String ownerUserId}) =>
      isUsable &&
      ownerUserId.trim().isNotEmpty &&
      ownerUserId.trim().toLowerCase() == userId.trim().toLowerCase();

  bool sameEnvironment(String value) =>
      value.trim().toLowerCase() == environment.trim().toLowerCase();

  bool sameAccount(String value) =>
      value.trim().toLowerCase() == accountId.trim().toLowerCase();
}
