import 'package:flutter_map_vector_tiles/flutter_map_vector_tiles.dart'
    as vector_tiles;

import 'basemap_config.dart';

abstract interface class BasemapProvider {
  const BasemapProvider();

  BasemapConfig get config;

  Future<vector_tiles.Style> loadStyle();
}
