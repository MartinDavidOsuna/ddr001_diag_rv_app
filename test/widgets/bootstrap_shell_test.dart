import 'dart:async';

import 'package:ddr001diag/app/bootstrap.dart';
import 'package:ddr001diag/core/services/app_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('muestra UI Flutter antes de terminar bootstrap', (tester) async {
    final pending = Completer<AppState>();
    await tester.pumpWidget(
      AppBootstrapShell(
        bootstrapLoader: (report) {
          report('Inicializando almacenamiento');
          return pending.future;
        },
      ),
    );
    await tester.pump();
    expect(find.byType(Scaffold), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('Inicializando almacenamiento'), findsOneWidget);
    pending.completeError(StateError('synthetic configuration error'));
    await tester.pump();
  });
}
