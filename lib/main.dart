import 'package:flutter/material.dart';

import 'app/bootstrap.dart';

Future<void> main() async {
  final launch = Stopwatch()..start();
  WidgetsFlutterBinding.ensureInitialized();
  configureImageCache();
  runApp(const AppBootstrapShell());
  WidgetsBinding.instance.addPostFrameCallback((_) {
    debugPrint('[PERF] first_frame_ms=${launch.elapsedMilliseconds}');
  });
}

@visibleForTesting
void configureImageCache() {
  final cache = PaintingBinding.instance.imageCache;
  cache.maximumSize = 128;
  cache.maximumSizeBytes = 32 << 20;
}
