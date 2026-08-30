import 'package:ddr001diag/qa/qa_app.dart';
import 'package:ddr001diag/qa/qa_fixture_catalog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('catálogo QA construye sólo la ventana visible', (tester) async {
    final fixtures = List.generate(
      100,
      (index) => QaFixtureRecord(
        id: 'qa-review-virtual-$index',
        hydrantId: 'qa-hydrant-virtual-$index',
        account: 'QA-VIRTUAL-$index',
        state: QaFixtureState.normal,
        latitude: 1,
        longitude: -1,
      ),
    );
    final built = <String>{};
    await tester.binding.setSurfaceSize(const Size(800, 600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: CustomScrollView(
          slivers: [
            QaFixtureSliver(fixtures: fixtures, onTileBuilt: built.add),
          ],
        ),
      ),
    );

    expect(built, isNotEmpty);
    expect(built.length, lessThan(fixtures.length));
    final initiallyBuilt = built.length;
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -500));
    await tester.pump();
    expect(built.length, greaterThan(initiallyBuilt));
    expect(built.length, lessThan(fixtures.length));
  });
}
