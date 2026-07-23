import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../app/theme/app_theme.dart';
import '../../core/services/app_state.dart';
import '../../core/widgets/common_widgets.dart';
import '../../domain/enums/app_enums.dart';
import '../../domain/models/app_models.dart';

class MapPage extends StatefulWidget {
  const MapPage({super.key});
  @override
  State<MapPage> createState() => _MapPageState();
}

class _MapPageState extends State<MapPage> {
  Hydrant? selected;
  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final valid = state.catalogHydrants
        .where(
          (item) =>
              item.latitude.abs() <= 90 &&
              item.longitude.abs() <= 180 &&
              (item.latitude != 0 || item.longitude != 0),
        )
        .toList();
    final withoutCoordinates = state.catalogHydrants.length - valid.length;
    return Scaffold(
      appBar: AppPageHeader(
        title: 'Mapa general',
        subtitle:
            '${valid.length} hidrantes · $withoutCoordinates sin coordenadas',
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
            child: valid.isEmpty
                ? const Center(
                    child: Text(
                      'No hay hidrantes con coordenadas WGS84 válidas.',
                    ),
                  )
                : LayoutBuilder(
                    builder: (context, bounds) {
                      final minLat = valid
                          .map((e) => e.latitude)
                          .reduce((a, b) => a < b ? a : b);
                      final maxLat = valid
                          .map((e) => e.latitude)
                          .reduce((a, b) => a > b ? a : b);
                      final minLng = valid
                          .map((e) => e.longitude)
                          .reduce((a, b) => a < b ? a : b);
                      final maxLng = valid
                          .map((e) => e.longitude)
                          .reduce((a, b) => a > b ? a : b);
                      double x(Hydrant h) =>
                          16 +
                          (h.longitude - minLng) /
                              ((maxLng - minLng).abs() < .000001
                                  ? 1
                                  : maxLng - minLng) *
                              (bounds.maxWidth - 60);
                      double y(Hydrant h) =>
                          16 +
                          (maxLat - h.latitude) /
                              ((maxLat - minLat).abs() < .000001
                                  ? 1
                                  : maxLat - minLat) *
                              (bounds.maxHeight - 150);
                      return Stack(
                        children: [
                          const Positioned.fill(
                            child: ColoredBox(color: Color(0xFFEAF2E4)),
                          ),
                          for (final hydrant in valid)
                            Positioned(
                              left: x(hydrant),
                              top: y(hydrant),
                              child: Semantics(
                                label:
                                    'Cuenta ${hydrant.code}, ${_completed(hydrant) ? 'RV terminada' : 'RV pendiente'}',
                                button: true,
                                child: GestureDetector(
                                  onTap: () =>
                                      setState(() => selected = hydrant),
                                  child: Icon(
                                    Icons.location_on,
                                    size: selected?.id == hydrant.id ? 40 : 30,
                                    color: _completed(hydrant)
                                        ? AppColors.green
                                        : AppColors.brightBlue,
                                  ),
                                ),
                              ),
                            ),
                          if (selected != null)
                            Positioned(
                              left: 12,
                              right: 12,
                              bottom: 12,
                              child: _HydrantSheet(
                                hydrant: selected!,
                                hasMine: state.hydrants.any(
                                  (item) => item.id == selected!.id,
                                ),
                              ),
                            ),
                        ],
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  static bool _completed(Hydrant hydrant) =>
      hydrant.f02a.status == InspectionStatus.completed;
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
          onPressed: () => context.push('/hydrants/new'),
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
