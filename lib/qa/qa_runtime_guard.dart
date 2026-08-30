import 'package:package_info_plus/package_info_plus.dart';

import 'qa_app_config.dart';
import 'qa_network_policy.dart';

class QaRuntimeCheck {
  const QaRuntimeCheck._({required this.allowed, this.code});

  const QaRuntimeCheck.allowed() : this._(allowed: true);
  const QaRuntimeCheck.blocked(String code)
    : this._(allowed: false, code: code);

  final bool allowed;
  final String? code;
}

abstract final class QaRuntimeGuard {
  static const packageName = 'com.aquafim.ddr001diag.qa';

  static QaRuntimeCheck verify({
    required QaAppConfig config,
    required String packageName,
  }) {
    if (packageName != QaRuntimeGuard.packageName) {
      return const QaRuntimeCheck.blocked('QA_PACKAGE_MISMATCH');
    }
    if (!config.isQa || !config.fixtureMode || config.syncEnabled) {
      return const QaRuntimeCheck.blocked('QA_CONFIG_MISMATCH');
    }
    try {
      QaNetworkPolicy.validateConfiguredEndpoint(config);
    } on Object {
      return const QaRuntimeCheck.blocked('QA_NETWORK_POLICY_MISMATCH');
    }
    return const QaRuntimeCheck.allowed();
  }

  static Future<QaRuntimeCheck> verifyPlatform(QaAppConfig config) async {
    final info = await PackageInfo.fromPlatform();
    return verify(config: config, packageName: info.packageName);
  }
}
