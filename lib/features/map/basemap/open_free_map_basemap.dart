import 'package:flutter_map_vector_tiles/flutter_map_vector_tiles.dart'
    as vector_tiles;

import 'basemap_config.dart';
import 'basemap_provider.dart';

class OpenFreeMapBasemap implements BasemapProvider {
  const OpenFreeMapBasemap();

  static final Uri positronStyleUri = Uri.parse(
    'https://tiles.openfreemap.org/styles/positron',
  );

  static final BasemapConfig openFreeMapConfig = BasemapConfig(
    id: 'openfreemap-positron',
    provider: 'OpenFreeMap',
    styleUri: positronStyleUri,
    attributions: [
      BasemapAttribution(
        label: 'OpenFreeMap',
        url: Uri.parse('https://openfreemap.org/'),
      ),
      BasemapAttribution(
        label: '© OpenMapTiles',
        url: Uri.parse('https://openmaptiles.org/'),
      ),
      BasemapAttribution(
        label: '© OpenStreetMap contributors',
        url: Uri.parse('https://www.openstreetmap.org/copyright'),
      ),
    ],
    minimumZoom: 0,
    maximumZoom: 20,
    sourceType: BasemapSourceType.mapLibreVector,
    requiresApiKey: false,
  );

  @override
  BasemapConfig get config => openFreeMapConfig;

  @override
  Future<vector_tiles.Style> loadStyle() =>
      vector_tiles.StyleReader(uri: config.styleUri.toString()).read();
}
