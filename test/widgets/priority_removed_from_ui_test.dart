import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('la experiencia funcional no muestra ni usa prioridad', () {
    final uiFiles = Directory('lib/features')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'));
    final offenders = <String>[];
    for (final file in uiFiles) {
      final source = file.readAsStringSync();
      if (RegExp(r'Prioridad|\.priority\b').hasMatch(source)) {
        offenders.add(file.path);
      }
    }
    expect(
      offenders,
      isEmpty,
      reason: 'Prioridad encontrada en UI: $offenders',
    );
  });
}
