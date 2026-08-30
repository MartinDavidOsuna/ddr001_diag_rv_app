import 'package:ddr001diag/features/map/basemap/basemap_config.dart';
import 'package:ddr001diag/features/map/basemap/basemap_layer.dart';
import 'package:ddr001diag/features/map/basemap/basemap_provider.dart';
import 'package:ddr001diag/features/map/basemap/open_free_map_basemap.dart';
import 'package:ddr001diag/features/map/map_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map_vector_tiles/flutter_map_vector_tiles.dart'
    as vector_tiles;
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('OpenFreeMap basemap configuration', () {
    const provider = OpenFreeMapBasemap();

    test('is the default vector basemap and needs no credentials', () {
      final mapPage = const MapPage();
      final config = mapPage.basemapProvider.config;

      expect(mapPage.basemapProvider, isA<OpenFreeMapBasemap>());
      expect(config.id, 'openfreemap-positron');
      expect(config.provider, 'OpenFreeMap');
      expect(
        config.styleUri,
        Uri.parse('https://tiles.openfreemap.org/styles/positron'),
      );
      expect(config.sourceType, BasemapSourceType.mapLibreVector);
      expect(config.requiresApiKey, isFalse);
      expect(config.styleUri.queryParameters, isEmpty);
    });

    test('publishes the required open-data attribution', () {
      final labels = provider.config.attributions.map(
        (attribution) => attribution.label,
      );

      expect(labels, contains('OpenFreeMap'));
      expect(labels, contains('© OpenMapTiles'));
      expect(labels, contains('© OpenStreetMap contributors'));
      expect(
        provider.config.attributions.every(
          (attribution) => attribution.url.scheme == 'https',
        ),
        isTrue,
      );
    });

    test('contains no commercial provider or credential parameter', () {
      final serialized = [
        provider.config.id,
        provider.config.provider,
        provider.config.styleUri.toString(),
        for (final attribution in provider.config.attributions) ...[
          attribution.label,
          attribution.url.toString(),
        ],
      ].join(' ').toLowerCase();

      for (final forbidden in const [
        'carto',
        'mapbox',
        'google',
        'maptiler',
        'stadia',
        'api_key',
        'access_token',
      ]) {
        expect(serialized, isNot(contains(forbidden)));
      }
    });
  });

  testWidgets('network failure degrades without repeatedly loading the style', (
    tester,
  ) async {
    final provider = _UnavailableBasemapProvider();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: BasemapLayer(provider: provider)),
      ),
    );
    await tester.pump();

    expect(find.byKey(const ValueKey('basemap-unavailable')), findsOneWidget);
    expect(find.textContaining('hidrantes guardados'), findsOneWidget);
    expect(provider.loadCount, 1);

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(colorSchemeSeed: Colors.blue),
        home: Scaffold(body: BasemapLayer(provider: provider)),
      ),
    );
    await tester.pump();

    expect(provider.loadCount, 1);
  });
}

class _UnavailableBasemapProvider implements BasemapProvider {
  int loadCount = 0;

  @override
  BasemapConfig get config => OpenFreeMapBasemap.openFreeMapConfig;

  @override
  Future<vector_tiles.Style> loadStyle() {
    loadCount++;
    return Future.error(StateError('offline'));
  }
}
