import 'package:ddr001diag/diagnostic_main.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('is a single-purpose recovery UI', (tester) async {
    await tester.pumpWidget(const DiagnosticApp());
    expect(find.text('Iniciar análisis'), findsOneWidget);
    expect(find.textContaining('No elimina'), findsOneWidget);
    expect(find.text('Sincronizar y enviar'), findsNothing);
  });
}
