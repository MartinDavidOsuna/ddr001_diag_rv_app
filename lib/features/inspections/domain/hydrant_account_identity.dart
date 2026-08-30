enum AccountTransformation { none, hyphenTo000 }

enum AccountResolutionState {
  original,
  transformed,
  unresolvedAccountCollision,
  unresolved,
}

String transformLegacyHyphenAccount(String account) =>
    account.contains('-') ? account.replaceAll('-', '000') : account;

class HydrantAccountIdentity {
  const HydrantAccountIdentity({
    required this.originalAccountNumber,
    required this.effectiveAccountNumber,
    this.serverAccountNumber,
    this.transformation = AccountTransformation.none,
    this.transformationVersion,
    this.transformedAt,
    this.resolutionState = AccountResolutionState.original,
    this.resolutionAttempts = const [],
  });

  factory HydrantAccountIdentity.original(String account) =>
      HydrantAccountIdentity(
        originalAccountNumber: account,
        effectiveAccountNumber: account,
      );

  final String originalAccountNumber;
  final String effectiveAccountNumber;
  final String? serverAccountNumber;
  final AccountTransformation transformation;
  final int? transformationVersion;
  final DateTime? transformedAt;
  final AccountResolutionState resolutionState;
  final List<String> resolutionAttempts;

  bool get isTransformed => transformation != AccountTransformation.none;

  Map<String, dynamic> toJson() => {
    'originalAccountNumber': originalAccountNumber,
    'effectiveAccountNumber': effectiveAccountNumber,
    'serverAccountNumber': serverAccountNumber,
    'accountTransformation': transformation == AccountTransformation.none
        ? null
        : 'hyphen_to_000',
    'accountTransformationVersion': transformationVersion,
    'accountTransformedAt': transformedAt?.toUtc().toIso8601String(),
    'accountResolutionState': resolutionState.name,
    'accountResolutionAttempts': resolutionAttempts,
  };

  factory HydrantAccountIdentity.fromJson(
    Map<String, dynamic> json, {
    required String legacyAccountNumber,
  }) {
    final original =
        json['originalAccountNumber']?.toString() ?? legacyAccountNumber;
    final effective =
        json['effectiveAccountNumber']?.toString() ?? legacyAccountNumber;
    return HydrantAccountIdentity(
      originalAccountNumber: original,
      effectiveAccountNumber: effective,
      serverAccountNumber: json['serverAccountNumber']?.toString(),
      transformation: json['accountTransformation'] == 'hyphen_to_000'
          ? AccountTransformation.hyphenTo000
          : AccountTransformation.none,
      transformationVersion: json['accountTransformationVersion'] as int?,
      transformedAt: DateTime.tryParse(
        json['accountTransformedAt']?.toString() ?? '',
      )?.toUtc(),
      resolutionState: AccountResolutionState.values.firstWhere(
        (value) => value.name == json['accountResolutionState'],
        orElse: () => AccountResolutionState.original,
      ),
      resolutionAttempts:
          (json['accountResolutionAttempts'] as List? ?? const [])
              .map((value) => '$value')
              .toList(growable: false),
    );
  }
}

/// Pure policy gate for the legacy alias. A 404 is never proof that a hyphen
/// is incompatible: the original create attempt must have failed for a reason
/// explicitly attributable to the hyphen before this can return true.
bool mayUseLegacyHyphenAlias({
  required String originalAccountNumber,
  required bool originalAbsent,
  required bool originalCreateHyphenIncompatible,
  required bool aliasCollisionChecked,
  required bool aliasBelongsToDifferentHydrant,
}) =>
    originalAccountNumber.contains('-') &&
    originalAbsent &&
    originalCreateHyphenIncompatible &&
    aliasCollisionChecked &&
    !aliasBelongsToDifferentHydrant;
