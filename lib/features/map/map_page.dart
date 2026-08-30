import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';

import '../../app/theme/app_theme.dart';
import '../../core/network/api_exception.dart';
import '../../core/services/app_state.dart';
import '../../core/widgets/common_widgets.dart';
import '../../domain/enums/app_enums.dart';
import '../../domain/models/app_models.dart';
import '../hydrants/data/hydrant_repository.dart';
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
  bool _loadingRegion = false;
  bool _regionDirty = false;
  bool _mapReady = false;
  LatLng? _currentLocation;
  Timer? _cameraDebounce;
  int _requestGeneration = 0;
  int _catalogSignature = -1;
  DateTime? _regionUpdatedAt;
  String? _regionError;
  final Map<String, HydrantMapItem> _visibleItems = {};
  HydrantMapFilter _filter = HydrantMapFilter.all;

  @override
  void initState() {
    super.initState();
    _cameraAnimation = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
    );
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _refreshInitialCatalog(),
    );
  }

  @override
  void dispose() {
    _cameraAnimation.dispose();
    _cameraDebounce?.cancel();
    _mapController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    _seedCachedItems(state);
    final allItems = _visibleItems.values.toList(growable: false);
    final items = allItems
        .where((item) => hydrantMatchesMapFilter(item.hydrant, _filter))
        .toList(growable: false);
    final selected = _selection.selectedFrom(items);
    final withoutCoordinates = state.catalogHydrants.length - allItems.length;

    return Scaffold(
      appBar: AppPageHeader(
        title: 'Mapa general',
        subtitle:
            '${items.length} de ${allItems.length} hidrantes · '
            '$withoutCoordinates sin coordenadas',
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: ConnectionBadge(
              online: state.online,
              state: state.connectivityState,
              transport: state.connectivityMonitor?.transport,
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
            child: _MapFilterGrid(
              selected: _filter,
              onSelected: (filter) {
                setState(() {
                  _filter = filter;
                  final selectedId = _selection.selectedId;
                  if (selectedId != null &&
                      !allItems.any(
                        (item) =>
                            item.id == selectedId &&
                            hydrantMatchesMapFilter(item.hydrant, filter),
                      )) {
                    _selection.clear();
                  }
                });
              },
            ),
          ),
          Expanded(
            child: Stack(
              children: [
                Positioned.fill(
                  child: FlutterMap(
                    mapController: _mapController,
                    options: MapOptions(
                      initialCenter: _centerOf(items),
                      initialZoom: HydrantMapCameraPolicy.initialZoom,
                      initialCameraFit: _initialCameraFit(items),
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
                      onMapReady: () => setState(() => _mapReady = true),
                      onPositionChanged: (_, hasGesture) {
                        if (hasGesture) _scheduleRegionSearch();
                      },
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
                          TextSourceAttribution('© OpenStreetMap contributors'),
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
                  top: 12,
                  left: 12,
                  right: 78,
                  child: Column(
                    children: [
                      if (_loadingRegion)
                        const LinearProgressIndicator(
                          key: ValueKey('map-region-progress'),
                        ),
                      if (_regionDirty || _loadingRegion)
                        FilledButton.icon(
                          key: const ValueKey('map-search-region'),
                          onPressed: _loadingRegion
                              ? null
                              : () => _loadVisibleRegion(force: false),
                          icon: _loadingRegion
                              ? const SizedBox.square(
                                  dimension: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.search),
                          label: Text(
                            _loadingRegion
                                ? 'Cargando hidrantes cercanos…'
                                : 'Buscar en esta zona',
                          ),
                        ),
                      const SizedBox(height: 6),
                      OutlinedButton.icon(
                        key: const ValueKey('map-refresh-region'),
                        onPressed: _loadingRegion
                            ? null
                            : () => _loadVisibleRegion(force: true),
                        icon: const Icon(Icons.refresh),
                        label: const Text('Actualizar zona'),
                      ),
                      if (_regionError != null)
                        Material(
                          color: Theme.of(context).colorScheme.errorContainer,
                          borderRadius: BorderRadius.circular(8),
                          child: Padding(
                            padding: const EdgeInsets.all(8),
                            child: Text(_regionError!),
                          ),
                        )
                      else if (_regionUpdatedAt != null)
                        Text('Actualizado ${_relativeTime(_regionUpdatedAt!)}'),
                    ],
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
                if (items.isEmpty && !_loadingRegion)
                  const Positioned(
                    left: 24,
                    right: 24,
                    bottom: 94,
                    child: Card(
                      child: Padding(
                        padding: EdgeInsets.all(12),
                        child: Text(
                          'No hay hidrantes guardados en esta zona.',
                          textAlign: TextAlign.center,
                        ),
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

  void _seedCachedItems(AppState state) {
    final signature = Object.hash(
      state.catalogHydrants.length,
      state.hydrantsLastUpdated,
    );
    if (_catalogSignature == signature) return;
    _catalogSignature = signature;
    final all = widget.markerSource.itemsFor(state.catalogHydrants);
    _visibleItems
      ..clear()
      ..addEntries(all.map((item) => MapEntry(item.id, item)));
  }

  Future<void> _refreshInitialCatalog() async {
    if (_loadingRegion) return;
    final state = context.read<AppState>();
    final cached = widget.markerSource.itemsFor(state.catalogHydrants);
    if (cached.isNotEmpty || state.catalogHydrants.isEmpty) return;
    setState(() {
      _loadingRegion = true;
      _regionError = null;
    });
    try {
      await state.refreshMapCatalog(forceSnapshot: true);
      if (!mounted) return;
      final refreshed = widget.markerSource.itemsFor(state.catalogHydrants);
      setState(() {
        _visibleItems
          ..clear()
          ..addEntries(refreshed.map((item) => MapEntry(item.id, item)));
        _regionUpdatedAt = DateTime.now();
      });
      if (_mapReady) _showAll(refreshed);
    } on Object catch (error) {
      if (!mounted) return;
      setState(
        () => _regionError = error is ApiException
            ? error.message
            : 'No fue posible actualizar el catálogo del mapa.',
      );
    } finally {
      if (mounted) setState(() => _loadingRegion = false);
    }
  }

  Future<void> _loadVisibleRegion({required bool force}) async {
    if (_loadingRegion) return;
    final bounds = _mapController.camera.visibleBounds;
    await _loadPages(
      request: (cursor) =>
          context.read<AppState>().hydrantRepository.fetchMapPage(
            bounds: HydrantMapBounds(
              south: bounds.south,
              west: bounds.west,
              north: bounds.north,
              east: bounds.east,
            ),
            cursor: cursor,
          ),
      authoritativeBounds: bounds,
    );
  }

  Future<void> _loadPages({
    required Future<HydrantMapPage> Function(String? cursor) request,
    required LatLngBounds? authoritativeBounds,
  }) async {
    final generation = ++_requestGeneration;
    setState(() {
      _loadingRegion = true;
      _regionError = null;
    });
    final remoteIds = <String>{};
    String? cursor;
    try {
      do {
        final page = await request(cursor);
        if (!mounted || generation != _requestGeneration) return;
        final incoming = widget.markerSource.itemsFor(
          page.items.map((item) => item.toAppModel()),
        );
        remoteIds.addAll(incoming.map((item) => item.id));
        setState(() {
          for (final item in incoming) {
            _visibleItems[item.id] = item;
          }
        });
        cursor = page.hasMore ? page.nextCursor : null;
        _regionUpdatedAt = page.generatedAt;
      } while (cursor != null);
      if (authoritativeBounds != null) {
        final state = context.read<AppState>();
        final pendingIds = {
          for (final item in state.catalogHydrants)
            if (item.syncStatus != SyncStatus.synced) item.id,
        };
        _visibleItems.removeWhere(
          (id, item) =>
              authoritativeBounds.contains(item.position) &&
              !remoteIds.contains(id) &&
              !pendingIds.contains(id),
        );
      }
      if (mounted) setState(() => _regionDirty = false);
    } on Object catch (error) {
      if (mounted && generation == _requestGeneration) {
        setState(
          () => _regionError = error is ApiException
              ? switch (error.kind) {
                  ApiErrorKind.authenticationRequired ||
                  ApiErrorKind.sessionExpired =>
                    'Sin conexión. Puedes continuar trabajando; los cambios se sincronizarán después.',
                  ApiErrorKind.sessionRevoked => error.message,
                  ApiErrorKind.timeout =>
                    'El servidor tardó demasiado en actualizar esta zona.',
                  ApiErrorKind.serverUnavailable || ApiErrorKind.offline =>
                    'Sin conexión con el servidor. Se conservan los datos guardados.',
                  ApiErrorKind.serverError =>
                    'El servidor respondió con un error. Se conservan los datos guardados.',
                  _ => 'No fue posible actualizar esta zona.',
                }
              : 'No fue posible actualizar esta zona.',
        );
      }
    } finally {
      if (mounted && generation == _requestGeneration) {
        setState(() => _loadingRegion = false);
      }
    }
  }

  void _scheduleRegionSearch() {
    _cameraDebounce?.cancel();
    _cameraDebounce = Timer(const Duration(milliseconds: 550), () {
      if (mounted) setState(() => _regionDirty = true);
    });
  }

  static String _relativeTime(DateTime value) {
    final elapsed = DateTime.now().difference(value.toLocal());
    if (elapsed.inMinutes < 1) return 'hace unos segundos';
    return 'hace ${elapsed.inMinutes} min';
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
    if (items.isEmpty) return;
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

  static CameraFit? _initialCameraFit(List<HydrantMapItem> items) {
    if (items.length < 2) return null;
    return CameraFit.bounds(
      bounds: LatLngBounds.fromPoints(
        items.map((item) => item.position).toList(growable: false),
      ),
      padding: const EdgeInsets.fromLTRB(48, 72, 48, 72),
      maxZoom: 16,
    );
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
        color: hydrantMarkerColor(item.hydrant),
        shadows: const [
          Shadow(color: Colors.white, blurRadius: 3),
          Shadow(color: Colors.black38, blurRadius: 5),
        ],
      ),
    ),
  );
}

@visibleForTesting
Color hydrantMarkerColor(Hydrant hydrant) {
  return switch (hydrantMapCategory(hydrant)) {
    HydrantMapCategory.available => AppColors.brightBlue,
    HydrantMapCategory.localWork => Colors.amber.shade700,
    HydrantMapCategory.reviewed => AppColors.green,
    HydrantMapCategory.conflict => AppColors.red,
    HydrantMapCategory.inactive => Colors.grey,
  };
}

enum HydrantMapCategory { available, localWork, reviewed, conflict, inactive }

enum HydrantMapFilter {
  all,
  available,
  localWork,
  reviewed,
  conflict,
  inactive,
}

@visibleForTesting
HydrantMapCategory hydrantMapCategory(Hydrant hydrant) {
  if (hydrant.hasConflict ||
      const {'conflict', 'returned', 'rejected'}.contains(hydrant.rvStatus)) {
    return HydrantMapCategory.conflict;
  }
  if (!hydrant.isActive ||
      (!hydrant.availableForRv &&
          hydrant.officialInspectionId == null &&
          !const {
            'submitted',
            'completed',
            'validated',
          }.contains(hydrant.rvStatus))) {
    return HydrantMapCategory.inactive;
  }
  if (hydrant.officialInspectionId != null ||
      const {
        'submitted',
        'completed',
        'validated',
      }.contains(hydrant.rvStatus) ||
      const {
        InspectionStatus.completed,
        InspectionStatus.validated,
      }.contains(hydrant.f02a.status)) {
    return HydrantMapCategory.reviewed;
  }
  if (hydrant.f02a.status == InspectionStatus.inProgress ||
      const {
        SyncStatus.local,
        SyncStatus.pending,
      }.contains(hydrant.syncStatus)) {
    return HydrantMapCategory.localWork;
  }
  return HydrantMapCategory.available;
}

@visibleForTesting
bool hydrantMatchesMapFilter(Hydrant hydrant, HydrantMapFilter filter) =>
    filter == HydrantMapFilter.all ||
    hydrantMapCategory(hydrant).name == filter.name;

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
        if (hydrant.lastStatusChangedAt != null)
          Text(
            DateFormat(
              "d MMM yyyy · HH:mm",
              'es',
            ).format(hydrant.lastStatusChangedAt!.toLocal()),
          ),
        Text(
          hydrant.f02a.status == InspectionStatus.completed
              ? 'RV terminada'
              : 'RV pendiente',
        ),
        const SizedBox(height: 8),
        if (hydrant.availableForRv)
          FilledButton(
            onPressed: () => context.push(newSurveyRouteForHydrant(hydrant.id)),
            child: const Text('Iniciar nueva revisión'),
          )
        else
          FilledButton.icon(
            onPressed: () => context.push(
              '/visual-report/${Uri.encodeComponent(hydrant.code)}',
            ),
            icon: const Icon(Icons.description_outlined),
            label: const Text('Ver reporte RV'),
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

class _MapFilterGrid extends StatelessWidget {
  const _MapFilterGrid({required this.selected, required this.onSelected});

  final HydrantMapFilter selected;
  final ValueChanged<HydrantMapFilter> onSelected;

  @override
  Widget build(BuildContext context) {
    const labels = {
      HydrantMapFilter.all: 'Todo',
      HydrantMapFilter.available: 'Disponible',
      HydrantMapFilter.localWork: 'Trabajo local',
      HydrantMapFilter.reviewed: 'Revisado',
      HydrantMapFilter.conflict: 'Conflicto',
      HydrantMapFilter.inactive: 'Inactivo',
    };
    return SizedBox(
      height: 86,
      child: GridView.count(
        physics: const NeverScrollableScrollPhysics(),
        crossAxisCount: 3,
        crossAxisSpacing: 6,
        mainAxisSpacing: 6,
        mainAxisExtent: 40,
        children: [
          for (final filter in HydrantMapFilter.values)
            OutlinedButton(
              key: ValueKey('map-filter-${filter.name}'),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                backgroundColor: selected == filter
                    ? Theme.of(context).colorScheme.primaryContainer
                    : null,
                side: BorderSide(
                  color: selected == filter
                      ? Theme.of(context).colorScheme.primary
                      : Theme.of(context).colorScheme.outlineVariant,
                ),
              ),
              onPressed: () => onSelected(filter),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (filter == HydrantMapFilter.all)
                    const Icon(Icons.filter_alt_outlined, size: 14)
                  else
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: _filterColor(filter),
                        shape: BoxShape.circle,
                      ),
                    ),
                  const SizedBox(width: 5),
                  Flexible(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(labels[filter]!),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  static Color _filterColor(HydrantMapFilter filter) => switch (filter) {
    HydrantMapFilter.available => AppColors.brightBlue,
    HydrantMapFilter.localWork => Colors.amber,
    HydrantMapFilter.reviewed => AppColors.green,
    HydrantMapFilter.conflict => AppColors.red,
    HydrantMapFilter.inactive => Colors.grey,
    HydrantMapFilter.all => Colors.transparent,
  };
}
