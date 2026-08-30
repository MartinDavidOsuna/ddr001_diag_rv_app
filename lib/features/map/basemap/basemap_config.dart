enum BasemapSourceType { mapLibreVector, pmTiles, mbTiles, selfHostedVector }

class BasemapAttribution {
  const BasemapAttribution({required this.label, required this.url});

  final String label;
  final Uri url;
}

class BasemapConfig {
  const BasemapConfig({
    required this.id,
    required this.provider,
    required this.styleUri,
    required this.attributions,
    required this.minimumZoom,
    required this.maximumZoom,
    required this.sourceType,
    required this.requiresApiKey,
  });

  final String id;
  final String provider;
  final Uri styleUri;
  final List<BasemapAttribution> attributions;
  final double minimumZoom;
  final double maximumZoom;
  final BasemapSourceType sourceType;
  final bool requiresApiKey;
}
