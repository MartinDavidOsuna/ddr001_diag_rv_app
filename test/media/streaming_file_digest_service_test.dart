import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:ddr001diag/core/media/file_digest_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'archivo grande se procesa por stream y permite eventos intermedios',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'rv-digest-test-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final file = File('${directory.path}/large.jpg');
      final sink = file.openWrite();
      final chunk = List<int>.generate(64 * 1024, (index) => index & 0xff);
      for (var index = 0; index < 128; index++) {
        sink.add(chunk);
      }
      await sink.close();

      var eventDelivered = false;
      final watch = Stopwatch()..start();
      final digestFuture = const StreamingFileDigestService().sha256Of(file);
      unawaited(
        Future<void>.delayed(Duration.zero, () => eventDelivered = true),
      );
      final digest = await digestFuture;
      // Sanitized deterministic fixture metric; no field path or content.
      // ignore: avoid_print
      print(
        '[PERF][TEST] streaming_sha256_8mib_ms=${watch.elapsedMilliseconds}',
      );

      expect(eventDelivered, isTrue);
      expect(digest, sha256.convert(await file.readAsBytes()).toString());
    },
  );
}
