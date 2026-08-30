import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'qa/qa_app.dart';
import 'qa/qa_app_config.dart';
import 'qa/qa_fixture_harness.dart';
import 'qa/qa_runtime_guard.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final cache = PaintingBinding.instance.imageCache;
  cache.maximumSize = 64;
  cache.maximumSizeBytes = 16 << 20;
  final config = createQaAppConfig();
  final packageInfo = await PackageInfo.fromPlatform();
  final check = QaRuntimeGuard.verify(
    config: config,
    packageName: packageInfo.packageName,
  );
  if (!check.allowed) {
    runApp(QaBlockedApp(code: check.code ?? 'QA_RUNTIME_BLOCKED'));
    return;
  }
  try {
    final harness = await QaFixtureHarness.open(config);
    runApp(QaApp(harness: harness, packageInfo: packageInfo));
  } on Object catch (error) {
    debugPrint('[QA] startup blocked type=${error.runtimeType}');
    runApp(const QaBlockedApp(code: 'QA_STARTUP_BLOCKED'));
  }
}

class QaBlockedApp extends StatelessWidget {
  const QaBlockedApp({required this.code, super.key});

  final String code;

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    home: Scaffold(
      backgroundColor: const Color(0xFF2B143D),
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.block, color: Colors.white, size: 56),
                const SizedBox(height: 16),
                const Text(
                  'QA bloqueada por configuración insegura',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 8),
                Text(code, style: const TextStyle(color: Colors.white70)),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
