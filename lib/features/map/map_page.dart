import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../../app/theme/app_theme.dart';
import '../../core/services/app_state.dart';
import '../../core/widgets/common_widgets.dart';
import '../../domain/enums/app_enums.dart';
import '../../domain/models/app_models.dart';
import '../hydrants/new_survey_route.dart';
import 'hydrant_map_marker_source.dart';
import 'map_location_provider.dart';

class MapPage extends StatefulWidget {
  const MapPage({
    super.key,
    this.markerSource = const FlatHydrantMapMarkerSource(),
    this.locationProvider = const GeolocatorMapLocationProvider(),
  });

  final HydrantMapMarkerSource markerSource;
  final MapLocationProvider locationProvider;

  @override
  State<MapPage> createState() => _MapPageState();
}

class _MapPageState extends State<MapPage> with SingleTickerProviderStateMixin {
  static const _fallbackCenter = LatLng(22.0, -102.3);

  final MapController _mapController = MapController();
  final HydrantMapSelection _selection = HydrantMapSelection();
  late final AnimationController _cameraAnimation;
  bool _locating = false;
  LatLng? _currentLocation;

  @override
  void initState() {
    super.initState();
    _cameraAnimation = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
    );
  }

  @override
  void dispose() {
    _cameraAnimation.dispose();
    _mapController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final items = widget.markerSource.itemsFor(state.catalogHydrants);
    final selected = _selection.selectedFrom(items);
    final withoutCoordinates = state.catalogHydrants.length - items.length;

    return Scaffold(
      appBar: AppPageHeader(
        title: 'Mapa general',
        subtitle:
            '${items.length} hidrantes · $withoutCoordinates sin coordenadas',
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: ConnectionBadge(online: state.online),
          ),
        ],
      ),
      body: Column(
        children: [
          const Padding(
            padding: EdgeInsets.all(10),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _Legend(color: AppColors.brightBlue, label: 'RV pendiente'),
                SizedBox(width: 20),
                _Legend(color: AppColors.green, label: 'RV terminada'),
              ],
            ),
          ),
          Expanded(
            child: items.isEmpty
                ? const Center(
                    child: Text(
                      'No hay hidrantes con coordenadas WGS84 válidas.',
                    ),
                  )
                : Stack(
                    children: [
                      Positioned.fill(
                        child: FlutterMap(
                          mapController: _mapController,
                          options: MapOptions(
                            initialCenter: _centerOf(items),
                            initialZoom: HydrantMapCameraPolicy.initialZoom,
                            minZoom: HydrantMapCameraPolicy.minimumZoom,
                            maxZoom: HydrantMapCameraPolicy.maximumZoom,
                            interactionOptions: const InteractionOptions(
                              flags:
                                  InteractiveFlag.drag |
                                  InteractiveFlag.pinchZoom |
                                  InteractiveFlag.doubleTapZoom |
                                  InteractiveFlag.scrollWheelZoom,
                            ),
                            onTap: (_, _) => _clearSelection(),
                          ),
                          children: [
                            TileLayer(
                              urlTemplate:
                                  'https://{s}.basemaps.cartocdn.com/'
                                  'light_all/{z}/{x}/{y}.png',
                              subdomains: const ['a', 'b', 'c', 'd'],
                              userAgentPackageName: 'com.aquafim.ddr001diag',
                              maxNativeZoom: 20,
                            ),
                            MarkerLayer(
                              markers: [
                                for (final item in items)
                                  Marker(
                                    point: item.position,
                                    width: 48,
                                    height: 48,
                                    child: _HydrantMarker(
                                      item: item,
                                      selected: item.id == selected?.id,
                                      onTap: () => _selectHydrant(item),
                                    ),
                                  ),
                                if (_currentLocation case final location?)
                                  Marker(
                                    point: location,
                                    width: 34,
                                    height: 34,
                                    child: const _CurrentLocationMarker(),
                                  ),
                              ],
                            ),
                            const RichAttributionWidget(
                              attributions: [
                                TextSourceAttribution(
                                  '© OpenStreetMap contributors',
                                ),
                                TextSourceAttribution('© CARTO'),
                              ],
                            ),
                          ],
                        ),
                      ),
                      Positioned(
                        top: 12,
                        right: 12,
                        child: _ZoomControls(
                          onZoomIn: () => _changeZoom(1),
                          onZoomOut: () => _changeZoom(-1),
                        ),
                      ),
                      Positioned(
                        left: 12,
                        bottom: selected == null ? 12 : 198,
                        child: _MapActions(
                          locating: _locating,
                          onShowAll: () => _showAll(items),
                          onMyLocation: _goToCurrentLocation,
                        ),
                      ),
                      if (selected != null)
                        Positioned(
                          left: 12,
                          right: 12,
                          bottom: 12,
                          child: _HydrantSheet(
                            hydrant: selected.hydrant,
                            hasMine: state.hydrants.any(
                              (item) => item.id == selected.id,
                            ),
                          ),
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  void _clearSelection() {
    if (_selection.selectedId == null) return;
    setState(_selection.clear);
  }

  void _selectHydrant(HydrantMapItem item) {
    setState(() => _selection.select(item.id));
    _animateCamera(item.position, HydrantMapCameraPolicy.selectedHydrantZoom);
  }

  Future<void> _goToCurrentLocation() async {
    if (_locating) return;
    setState(() => _locating = true);
    try {
      final location = await widget.locationProvider.currentLocation();
      if (!mounted) return;
      setState(() => _currentLocation = location);
      await _animateCamera(
        location,
        HydrantMapCameraPolicy.currentLocationZoom,
      );
    } on Object catch (error) {
      if (!mounted) return;
      final message = error is MapLocationException
          ? error.message
          : 'No fue posible obtener tu ubicación.';
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  void _showAll(List<HydrantMapItem> items) {
    if (items.length == 1) {
      _animateCamera(items.single.position, 16);
      return;
    }
    _cameraAnimation.stop();
    _mapController.fitCamera(
      CameraFit.bounds(
        bounds: LatLngBounds.fromPoints(
          items.map((item) => item.position).toList(growable: false),
        ),
        padding: const EdgeInsets.fromLTRB(48, 72, 48, 72),
        maxZoom: 16,
      ),
    );
  }

  void _changeZoom(double delta) {
    final camera = _mapController.camera;
    _animateCamera(
      camera.center,
      HydrantMapCameraPolicy.clampZoom(camera.zoom + delta),
    );
  }

  Future<void> _animateCamera(LatLng target, double targetZoom) async {
    _cameraAnimation.stop();
    final camera = _mapController.camera;
    final start = camera.center;
    final startZoom = camera.zoom;
    final animation = CurvedAnimation(
      parent: _cameraAnimation,
      curve: Curves.easeOutCubic,
    );
    void moveCamera() {
      final progress = animation.value;
      _mapController.move(
        LatLng(
          start.latitude + (target.latitude - start.latitude) * progress,
          start.longitude + (target.longitude - start.longitude) * progress,
        ),
        startZoom + (targetZoom - startZoom) * progress,
      );
    }

    _cameraAnimation
      ..reset()
      ..addListener(moveCamera);
    try {
      await _cameraAnimation.forward().orCancel;
    } on TickerCanceled {
      // A newer camera request superseded this animation.
    } finally {
      _cameraAnimation.removeListener(moveCamera);
    }
  }

  static LatLng _centerOf(List<HydrantMapItem> items) {
    if (items.isEmpty) return _fallbackCenter;
    final latitude =
        items.fold<double>(0, (sum, item) => sum + item.position.latitude) /
        items.length;
    final longitude =
        items.fold<double>(0, (sum, item) => sum + item.position.longitude) /
        items.length;
    return LatLng(latitude, longitude);
  }

  static bool _completed(Hydrant hydrant) =>
      hydrant.f02a.status == InspectionStatus.completed;
}

class _HydrantMarker extends StatelessWidget {
  const _HydrantMarker({
    required this.item,
    required this.selected,
    required this.onTap,
  });

  final HydrantMapItem item;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    label:
        'Cuenta ${item.hydrant.code}, '
        '${_MapPageState._completed(item.hydrant) ? 'RV terminada' : 'RV pendiente'}',
    button: true,
    selected: selected,
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Icon(
        Icons.location_on,
        size: selected ? 42 : 32,
        color: _MapPageState._completed(item.hydrant)
            ? AppColors.green
            : AppColors.brightBlue,
        shadows: const [
          Shadow(color: Colors.white, blurRadius: 3),
          Shadow(color: Colors.black38, blurRadius: 5),
        ],
      ),
    ),
  );
}

class _CurrentLocationMarker extends StatelessWidget {
  const _CurrentLocationMarker();

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Mi ubicación',
    child: DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primary,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 4),
        boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 5)],
      ),
    ),
  );
}

class _ZoomControls extends StatelessWidget {
  const _ZoomControls({required this.onZoomIn, required this.onZoomOut});

  final VoidCallback onZoomIn;
  final VoidCallback onZoomOut;

  @override
  Widget build(BuildContext context) => Material(
    elevation: 4,
    borderRadius: BorderRadius.circular(14),
    clipBehavior: Clip.antiAlias,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          key: const ValueKey('map-zoom-in'),
          tooltip: 'Acercar',
          onPressed: onZoomIn,
          icon: const Icon(Icons.add),
        ),
        const Divider(height: 1),
        IconButton(
          key: const ValueKey('map-zoom-out'),
          tooltip: 'Alejar',
          onPressed: onZoomOut,
          icon: const Icon(Icons.remove),
        ),
      ],
    ),
  );
}

class _MapActions extends StatelessWidget {
  const _MapActions({
    required this.locating,
    required this.onShowAll,
    required this.onMyLocation,
  });

  final bool locating;
  final VoidCallback onShowAll;
  final VoidCallback onMyLocation;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      FloatingActionButton.extended(
        key: const ValueKey('map-show-all'),
        heroTag: 'map-show-all',
        onPressed: onShowAll,
        icon: const Icon(Icons.fit_screen),
        label: const Text('Mostrar todos los hidrantes'),
      ),
      const SizedBox(height: 8),
      FloatingActionButton.extended(
        key: const ValueKey('map-my-location'),
        heroTag: 'map-my-location',
        onPressed: locating ? null : onMyLocation,
        icon: locating
            ? const SizedBox.square(
                dimension: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.my_location),
        label: const Text('Mi ubicación'),
      ),
    ],
  );
}

class _HydrantSheet extends StatelessWidget {
  const _HydrantSheet({required this.hydrant, required this.hasMine});
  final Hydrant hydrant;
  final bool hasMine;

  @override
  Widget build(BuildContext context) => SectionCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Cuenta ${hydrant.code}',
          style: const TextStyle(fontWeight: FontWeight.w900),
        ),
        Text('${hydrant.locality} · ${hydrant.parcel}'),
        Text(
          hydrant.f02a.status == InspectionStatus.completed
              ? 'RV terminada'
              : 'RV pendiente',
        ),
        const SizedBox(height: 8),
        FilledButton(
          onPressed: () => context.push(newSurveyRouteForHydrant(hydrant.id)),
          child: const Text('Iniciar nueva revisión'),
        ),
        if (hasMine)
          TextButton(
            onPressed: () => context.push('/hydrants/${hydrant.id}'),
            child: const Text('Ver mi revisión'),
          ),
      ],
    ),
  );
}

class _Legend extends StatelessWidget {
  const _Legend({required this.color, required this.label});
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Container(
        width: 12,
        height: 12,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
      const SizedBox(width: 6),
      Text(label),
    ],
  );
}
