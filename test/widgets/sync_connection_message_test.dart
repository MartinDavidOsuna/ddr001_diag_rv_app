import 'package:ddr001diag/features/sync/sync_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('describe la confirmación remota cuando hay conexión real', () {
    expect(syncConnectionMessage(true), contains('Conectado a la API'));
    expect(syncConnectionMessage(true), isNot(contains('Simulación local')));
  });

  test('explica la persistencia local cuando no hay conexión', () {
    expect(syncConnectionMessage(false), contains('permanecen guardados'));
    expect(syncConnectionMessage(false), contains('recuperar la conexión'));
  });

  test('una foto sin proyección Hive permanece pendiente y no rompe la UI', () {
    expect(mediaSyncStatusForUi(null), 'Información pendiente');
  });

  testWidgets('muestra causa segura por evidencia y permite reintentar', (
    tester,
  ) async {
    var retried = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PhotoRow(
            id: 'photo-1',
            status: 'Requiere reintento',
            error: 'No fue posible completar la sincronización.',
            onRetry: () => retried = true,
          ),
        ),
      ),
    );

    expect(find.textContaining('No fue posible'), findsOneWidget);
    expect(find.textContaining('HTTP'), findsNothing);
    await tester.tap(find.text('Reintentar'));
    expect(retried, isTrue);
  });
}
