import 'dart:io';

import 'package:ddr001diag/core/media/image_decode_policy.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ddr001diag/main.dart' as production;

void main() {
  testWidgets('el cache global de imágenes queda acotado a 32 MiB', (
    tester,
  ) async {
    production.configureImageCache();
    final cache = PaintingBinding.instance.imageCache;
    expect(cache.maximumSize, 128);
    expect(cache.maximumSizeBytes, 32 << 20);
  });

  testWidgets('el visor solicita decode según pantalla y nunca mayor a 2048', (
    tester,
  ) async {
    late int width;
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(
            size: Size(1080, 2400),
            devicePixelRatio: 3,
          ),
          child: Builder(
            builder: (context) {
              width = evidenceViewerDecodeWidth(context);
              return const SizedBox();
            },
          ),
        ),
      ),
    );
    expect(width, maximumEvidenceViewerDecodePixels);
  });

  test('todas las vistas de evidencia dimensionan miniaturas u originales', () {
    for (final path in [
      'lib/features/hydrants/photo_gallery_page.dart',
      'lib/features/hydrants/inspection_placeholder_page.dart',
      'lib/features/inspections/presentation/rv_steps_one_two.dart',
    ]) {
      final source = File(path).readAsStringSync();
      expect(source, contains('cacheWidth:'));
    }
  });

  test('hash y multipart no materializan el JPEG completo en Dart', () {
    final source = File(
      'lib/features/inspections/data/inspection_remote_repository.dart',
    ).readAsStringSync();
    expect(source, isNot(contains('.readAsBytes(')));
    expect(source, isNot(contains('MultipartFile.fromBytes')));
    expect(source, contains('MultipartFile.fromFile'));
    expect(source, contains('_digestService.sha256Of'));
  });

  test('el staging nativo recicla bitmap aun si falla la compresión', () {
    final source = File(
      'android/app/src/main/kotlin/com/aquafim/ddr001diag/MainActivity.kt',
    ).readAsStringSync();
    expect(source, contains('finally {'));
    expect(source, contains('bitmap.recycle()'));
  });

  test('normalización conserva corrección EXIF sin retener metadatos', () {
    final source = File(
      'lib/core/media/image_processing_service.dart',
    ).readAsStringSync();
    expect(source, contains('autoCorrectionAngle: true'));
    expect(source, contains('keepExif: false'));
    expect(source, contains('minWidth: landscape ? 1920 : 1080'));
  });
}
