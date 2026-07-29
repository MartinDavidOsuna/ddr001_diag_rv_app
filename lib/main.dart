import 'package:flutter/material.dart';

import 'app/bootstrap.dart';

Future<void> main() async {
  final launch = Stopwatch()..start();
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const AppBootstrapShell());
  WidgetsBinding.instance.addPostFrameCallback((_) {
    debugPrint('[PERF] first_frame_ms=${launch.elapsedMilliseconds}');
  });
}
