import 'package:flutter/material.dart';
import 'package:flutter_map_vector_tiles/flutter_map_vector_tiles.dart'
    as vector_tiles;

import 'basemap_provider.dart';

class BasemapLayer extends StatefulWidget {
  const BasemapLayer({super.key, required this.provider});

  final BasemapProvider provider;

  @override
  State<BasemapLayer> createState() => _BasemapLayerState();
}

class _BasemapLayerState extends State<BasemapLayer> {
  late Future<vector_tiles.Style> _styleFuture;
  vector_tiles.Style? _style;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _styleFuture = _loadStyle();
  }

  @override
  void didUpdateWidget(covariant BasemapLayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.provider == widget.provider) return;
    _style?.dispose();
    _style = null;
    _styleFuture = _loadStyle();
  }

  Future<vector_tiles.Style> _loadStyle() async {
    final generation = ++_generation;
    final style = await widget.provider.loadStyle();
    if (!mounted || generation != _generation) {
      style.dispose();
      return style;
    }
    _style = style;
    return style;
  }

  @override
  void dispose() {
    _generation++;
    _style?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: Theme.of(context).colorScheme.surfaceContainerLowest,
    child: FutureBuilder<vector_tiles.Style>(
      future: _styleFuture,
      builder: (context, snapshot) {
        final style = snapshot.data;
        if (style != null) {
          return vector_tiles.VectorTileLayer(
            key: ValueKey(widget.provider.config.id),
            theme: style.theme,
            tileProviders: style.providers,
            rasterSources: style.rasterSources,
            sprites: style.sprites,
          );
        }
        if (snapshot.hasError) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'Mapa base no disponible sin conexión.\n'
                'Los hidrantes guardados siguen visibles.',
                key: ValueKey('basemap-unavailable'),
                textAlign: TextAlign.center,
              ),
            ),
          );
        }
        return const SizedBox.expand(
          child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
        );
      },
    ),
  );
}
