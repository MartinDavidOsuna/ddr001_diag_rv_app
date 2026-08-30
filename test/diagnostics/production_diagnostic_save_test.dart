import 'dart:io';

import 'package:ddr001diag/features/diagnostics/rv_diagnostic_export_service.dart';
import 'package:ddr001diag/features/profile/profile_pages.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('solicita guardado local del JSON sin mutar el reporte', () async {
    const channel = MethodChannel('diagnostic-save-test');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    MethodCall? observed;
    messenger.setMockMethodCallHandler(channel, (call) async {
      observed = call;
      return true;
    });
    final directory = await Directory.systemTemp.createTemp(
      'diagnostic-save-test-',
    );
    final file = File(
      '${directory.path}/DDR001_RV_DIAGNOSTIC_v60_20260829T220000Z.json',
    );
    await file.writeAsString('{"immutable":true}');
    final before = await file.readAsBytes();

    final saved = await saveDiagnosticJson(
      RvDiagnosticExportResult(
        file: file,
        remoteSnapshotComplete: true,
        errorCount: 0,
      ),
      channel: channel,
    );

    expect(saved, isTrue);
    expect(observed?.method, 'save');
    expect(observed?.arguments, {'path': file.path});
    expect(await file.readAsBytes(), before);

    messenger.setMockMethodCallHandler(channel, null);
    await directory.delete(recursive: true);
  });

  test('cancelar selector se propaga como guardado no completado', () async {
    const channel = MethodChannel('diagnostic-save-cancel-test');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (_) async => false);
    final file = File(
      '${Directory.systemTemp.path}/DDR001_RV_DIAGNOSTIC_v60_20260829T220001Z.json',
    );

    expect(
      await saveDiagnosticJson(
        RvDiagnosticExportResult(
          file: file,
          remoteSnapshotComplete: false,
          errorCount: 0,
        ),
        channel: channel,
      ),
      isFalse,
    );

    messenger.setMockMethodCallHandler(channel, null);
  });
}
