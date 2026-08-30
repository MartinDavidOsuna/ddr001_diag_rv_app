import 'package:ddr001diag/core/network/connectivity_monitor.dart';
import 'package:ddr001diag/core/widgets/common_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Wi-Fi remains visible when the API is unavailable', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ConnectionBadge(
            online: false,
            state: NetworkAvailabilityState.apiUnavailable,
            transport: NetworkTransport.wireless,
          ),
        ),
      ),
    );

    expect(find.text('Red inalámbrica'), findsOneWidget);
    expect(find.text('Sin conexión'), findsNothing);
  });

  testWidgets('no active transport reports no connection', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ConnectionBadge(
            online: false,
            state: NetworkAvailabilityState.noNetwork,
            transport: NetworkTransport.none,
          ),
        ),
      ),
    );

    expect(find.text('Sin conexión'), findsOneWidget);
  });
}
