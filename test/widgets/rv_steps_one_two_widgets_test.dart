import 'package:ddr001diag/features/inspections/domain/rv_draft.dart';
import 'package:ddr001diag/features/inspections/presentation/rv_steps_one_two.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget host(Widget child, {Size size = const Size(390, 844)}) => MediaQuery(
    data: MediaQueryData(size: size),
    child: MaterialApp(home: Scaffold(body: child)),
  );

  testWidgets(
    'muestra latitud, longitud, altura, precisión, fecha y origen GPS',
    (tester) async {
      await tester.pumpWidget(
        host(
          RvLocationDetails(
            sample: RvLocationSample(
              latitude: 29.12345678,
              longitude: -110.98765432,
              altitude: 222.4,
              horizontalAccuracy: 7.5,
              source: 'gps',
              capturedAt: DateTime.utc(2026, 7, 24, 12),
            ),
          ),
        ),
      );
      expect(find.textContaining('Latitud: 29.123457'), findsOneWidget);
      expect(find.textContaining('Longitud: -110.987654'), findsOneWidget);
      expect(find.textContaining('222.4 m'), findsOneWidget);
      expect(find.textContaining('7.5 m'), findsOneWidget);
      expect(find.textContaining('GPS automático'), findsOneWidget);
    },
  );

  testWidgets('identifica ubicación manual sin inventar precisión', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        RvLocationDetails(
          sample: RvLocationSample(
            latitude: 29,
            longitude: -110,
            source: 'manual',
            capturedAt: DateTime.utc(2026),
          ),
        ),
      ),
    );
    expect(find.textContaining('captura manual'), findsOneWidget);
    expect(find.textContaining('Precisión: No disponible'), findsOneWidget);
  });

  testWidgets('indicador de señal incluye porcentaje y texto, no solo color', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        RvSignalDetails(
          sample: RvSignalSample(
            generation: '4G',
            connected: true,
            capturedAt: DateTime.utc(2026),
            networkType: 'LTE',
            operatorName: 'Operador de prueba',
            level: 3,
          ),
        ),
      ),
    );
    expect(find.textContaining('Operador de prueba'), findsOneWidget);
    expect(find.textContaining('LTE'), findsOneWidget);
    expect(find.textContaining('75% · Buena'), findsOneWidget);
    expect(find.byIcon(Icons.signal_cellular_alt), findsOneWidget);
  });

  testWidgets('señal no disponible es explícita', (tester) async {
    await tester.pumpWidget(
      host(
        RvSignalDetails(
          sample: RvSignalSample(
            generation: 'UNKNOWN',
            connected: true,
            capturedAt: DateTime.utc(2026),
          ),
        ),
      ),
    );
    expect(find.textContaining('No disponible'), findsOneWidget);
    expect(find.textContaining('Desconocida'), findsOneWidget);
  });

  testWidgets('detalles de señal caben en pantalla estrecha', (tester) async {
    await tester.pumpWidget(
      host(
        RvSignalDetails(
          sample: RvSignalSample(
            generation: '5G',
            connected: true,
            capturedAt: DateTime.utc(2026),
            operatorName: 'Operador con nombre deliberadamente largo',
            level: 4,
          ),
        ),
        size: const Size(320, 640),
      ),
    );
    expect(tester.takeException(), isNull);
  });
}
