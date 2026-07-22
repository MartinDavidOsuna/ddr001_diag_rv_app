import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../app/theme/app_theme.dart';
import '../../core/constants/report_type_labels.dart';
import '../../core/services/app_state.dart';
import '../../core/widgets/common_widgets.dart';
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
    return Scaffold(
      appBar: AppPageHeader(
        title: 'Mapa',
        subtitle: 'Ubicación de hidrantes',
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: ConnectionBadge(online: state.online),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Container(
              color: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: const Row(
                children: [
                  Icon(Icons.gps_fixed, size: 17, color: AppColors.green),
                  SizedBox(width: 6),
                  Text(
                    'MAPA DEMO · GPS SIMULADO',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                  ),
                  SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      'RTK SIMULADO · ±0.03 m',
                      style: TextStyle(fontSize: 12, color: AppColors.teal),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: LayoutBuilder(
                builder: (context, box) => Stack(
                  children: [
                    Positioned.fill(
                      child: CustomPaint(painter: MockMapPainter()),
                    ),
                    const Positioned(
                      left: 12,
                      top: 12,
                      child: SectionCard(
                        padding: EdgeInsets.all(10),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'LEYENDA',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            Legend(
                              color: AppColors.brightBlue,
                              label:
                                  '${ReportTypeLabels.visualShort} pendiente',
                            ),
                            Legend(
                              color: AppColors.teal,
                              label:
                                  '${ReportTypeLabels.visualShort} terminado',
                            ),
                            Legend(
                              color: AppColors.violet,
                              label: ReportTypeLabels.functionalShort,
                            ),
                            Legend(color: AppColors.green, label: 'Validado'),
                          ],
                        ),
                      ),
                    ),
                    ...state.hydrants.map(
                      (h) => Positioned(
                        left: 12 + h.latitude * (box.maxWidth - 55),
                        top: 70 + h.longitude * (box.maxHeight - 150),
                        child: GestureDetector(
                          onTap: () => setState(() => selected = h),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 5,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(0xEFFFFFFF),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(
                                    color: AppColors.navy.withValues(
                                      alpha: .25,
                                    ),
                                  ),
                                ),
                                child: Text(
                                  h.displayShortId,
                                  style: const TextStyle(
                                    fontSize: 9,
                                    fontWeight: FontWeight.w800,
                                    color: AppColors.navy,
                                  ),
                                ),
                              ),
                              Icon(
                                Icons.location_on,
                                size: selected?.id == h.id ? 40 : 32,
                                color: h.f02b.progress > 0
                                    ? AppColors.violet
                                    : h.f02a.progress == 1
                                    ? AppColors.green
                                    : AppColors.brightBlue,
                                shadows: const [
                                  Shadow(color: Colors.white, blurRadius: 4),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      left: box.maxWidth * .5 - 13,
                      top: box.maxHeight * .42,
                      child: const Icon(
                        Icons.my_location,
                        color: AppColors.red,
                        size: 27,
                      ),
                    ),
                    if (selected != null)
                      Positioned(
                        left: 12,
                        right: 12,
                        bottom: 12,
                        child: SectionCard(
                          child: Row(
                            children: [
                              const Icon(
                                Icons.water_drop,
                                color: AppColors.blue,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      selected!.code,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                    Text(
                                      '${selected!.locality} · ${selected!.parcel}',
                                      style: const TextStyle(
                                        color: AppColors.muted,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              FilledButton(
                                onPressed: () =>
                                    context.push('/hydrants/${selected!.id}'),
                                child: const Text('Ver ficha'),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class Legend extends StatelessWidget {
  const Legend({required this.color, required this.label, super.key});
  final Color color;
  final String label;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 5),
    child: Row(
      children: [
        Container(
          width: 9,
          height: 9,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(label, style: const TextStyle(fontSize: 10)),
      ],
    ),
  );
}

class MockMapPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = const Color(0xFFEAF2E4),
    );
    final parcel = Paint()..color = const Color(0x55A3B77B);
    for (var i = 0; i < 6; i++) {
      final x = (i % 3) * size.width / 3;
      final y = (i ~/ 3) * size.height / 2;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(
            x + 6,
            y + 6,
            size.width / 3 - 12,
            size.height / 2 - 12,
          ),
          const Radius.circular(8),
        ),
        parcel,
      );
    }
    final route = Path()
      ..moveTo(-20, size.height * .75)
      ..quadraticBezierTo(
        size.width * .42,
        size.height * .55,
        size.width + 20,
        size.height * .25,
      );
    canvas.drawPath(
      route,
      Paint()
        ..color = const Color(0xFFF8F5E9)
        ..strokeWidth = 18
        ..style = PaintingStyle.stroke,
    );
    canvas.drawPath(
      route,
      Paint()
        ..color = const Color(0xFFCFBE98)
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke,
    );
    final canal = Path()
      ..moveTo(size.width * .1, -10)
      ..cubicTo(
        size.width * .3,
        size.height * .25,
        size.width * .2,
        size.height * .65,
        size.width * .45,
        size.height + 10,
      );
    canvas.drawPath(
      canal,
      Paint()
        ..color = const Color(0xFF8FC5D8)
        ..strokeWidth = 7
        ..style = PaintingStyle.stroke,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
