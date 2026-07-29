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
      '${_part(environment)}/${_part(accountId)}/${_part(userId)}';

  bool owns({required String ownerUserId}) =>
      isUsable && ownerUserId.isNotEmpty && ownerUserId == userId;

  static String _part(String value) =>
      Uri.encodeComponent(value.trim().toLowerCase());
}
