import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as p;

import '../app/theme/app_theme.dart';
import '../features/inspections/presentation/rv_inactive_closure_dialog.dart';
import '../features/inspections/presentation/rv_inspection_controller.dart';
import '../features/inspections/presentation/rv_summary_page.dart';
import 'qa_fixture_catalog.dart';
import 'qa_fixture_harness.dart';
import 'qa_bootstrap_lab.dart';
import 'qa_frame_telemetry.dart';

const _qaDiagnosticReportChannel = MethodChannel(
  'com.aquafim.ddr001diag/diagnostic_report',
);

class QaApp extends StatefulWidget {
  const QaApp({required this.harness, required this.packageInfo, super.key});

  final QaFixtureHarness harness;
  final PackageInfo packageInfo;

  @override
  State<QaApp> createState() => _QaAppState();
}

class _QaAppState extends State<QaApp> {
  RvInspectionController? _controller;
  Object? _error;
  final _frameTelemetry = QaFrameTelemetryController();
  QaFrameTelemetryReport? _lastFrameReport;
  QaBootstrapRunReport? _lastBootstrapReport;
  String? _labMessage;

  @override
  void initState() {
    super.initState();
    unawaited(_loadController());
  }

  Future<void> _loadController({bool next = false}) async {
    try {
      final previous = _controller;
      final controller = next
          ? await widget.harness.createNextController()
          : await widget.harness.activeController();
      if (!mounted) {
        controller.dispose();
        return;
      }
      setState(() {
        _controller = controller;
        _error = null;
      });
      previous?.dispose();
    } on Object catch (error) {
      if (mounted) setState(() => _error = error);
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    _frameTelemetry.dispose();
    super.dispose();
  }

  Future<void> _runBootstrap(String label) async {
    try {
      final report = await widget.harness.bootstrapLab.run(label);
      if (!mounted) return;
      setState(() {
        _lastBootstrapReport = report;
        _labMessage = '$label: ${report.totalWrites} escrituras observadas';
      });
    } on Object {
      if (mounted) setState(() => _labMessage = 'Bootstrap QA bloqueado.');
    }
  }

  void _toggleFrameSegment(String segment) {
    if (_frameTelemetry.isRecording) {
      final report = _frameTelemetry.stop();
      setState(() {
        _lastFrameReport = report;
        _labMessage = '${report.segment}: ${report.frames} frames';
      });
    } else {
      _frameTelemetry.start(segment);
      setState(() => _labMessage = 'Midiendo $segment');
    }
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'DDR001 RV QA',
    debugShowCheckedModeBanner: false,
    theme: AppTheme.light,
    home: Scaffold(
      appBar: AppBar(title: const Text('DDR001 RV QA')),
      body: Column(
        children: [
          const Material(
            color: Color(0xFF8A2BE2),
            child: SafeArea(
              bottom: false,
              child: SizedBox(
                width: double.infinity,
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  child: Text(
                    'QA · NO PRODUCCIÓN · SIN SINCRONIZACIÓN',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ),
            ),
          ),
          Expanded(child: _content()),
        ],
      ),
    ),
  );

  Widget _content() {
    if (_error != null) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'El laboratorio QA no pudo preparar su almacenamiento aislado.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    final controller = _controller;
    if (controller == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final fixtures = widget.harness.catalog.records();
    final draft = controller.draft!;
    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          sliver: SliverList.list(
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'AISLAMIENTO ACTIVO',
                        style: TextStyle(fontWeight: FontWeight.w900),
                      ),
                      const SizedBox(height: 8),
                      Text('Package: ${widget.packageInfo.packageName}'),
                      Text(
                        'Build: ${widget.packageInfo.version}+'
                        '${widget.packageInfo.buildNumber}',
                      ),
                      const Text('Endpoint: .invalid · requests bloqueados'),
                      const Text('Credenciales: ninguna'),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text(
                        'PRUEBA FÍSICA DE CÁMARA Y CIERRE INACTIVO',
                        style: TextStyle(fontWeight: FontWeight.w900),
                      ),
                      const SizedBox(height: 8),
                      Text('Revisión: ${draft.clientInspectionId}'),
                      Text('Estado: ${draft.localStatus.name}'),
                      Text(
                        'Fotos dedicadas: '
                        '${draft.photosFor('no_hydrant_at_location').length}',
                      ),
                      const SizedBox(height: 12),
                      Builder(
                        builder: (navigatorContext) => FilledButton.icon(
                          key: const ValueKey('qa-open-inactive-flow'),
                          onPressed: draft.isReadOnly
                              ? null
                              : () async {
                                  await showRvInactiveClosureDialog(
                                    navigatorContext,
                                    controller,
                                  );
                                  if (mounted) setState(() {});
                                },
                          icon: const Icon(Icons.camera_alt_outlined),
                          label: const Text(
                            'Abrir flujo real “No hay hidrante”',
                          ),
                        ),
                      ),
                      if (draft.isReadOnly)
                        OutlinedButton.icon(
                          key: const ValueKey('qa-create-next-review'),
                          onPressed: () => _loadController(next: true),
                          icon: const Icon(Icons.add_circle_outline),
                          label: const Text(
                            'Crear otra revisión QA conservando ésta',
                          ),
                        ),
                      OutlinedButton.icon(
                        onPressed: null,
                        icon: const Icon(Icons.sync_disabled),
                        label: const Text('Sincronización bloqueada en QA'),
                      ),
                      Builder(
                        builder: (navigatorContext) => OutlinedButton.icon(
                          key: const ValueKey('qa-open-historical-summary'),
                          onPressed: () {
                            final references = draft.photos.values
                                .expand((items) => items)
                                .toList(growable: false);
                            Navigator.of(navigatorContext).push<void>(
                              MaterialPageRoute(
                                builder: (_) => Scaffold(
                                  appBar: AppBar(
                                    title: const Text(
                                      'Historial QA · solo lectura',
                                    ),
                                  ),
                                  body: ListView(
                                    padding: const EdgeInsets.all(16),
                                    children: [
                                      Text(
                                        'Revisión ${draft.clientInspectionId}',
                                        key: const ValueKey(
                                          'qa-historical-review-id',
                                        ),
                                      ),
                                      const SizedBox(height: 12),
                                      if (references.isEmpty)
                                        const Text(
                                          'Sin fotografías de evidencia',
                                        )
                                      else
                                        RvHistoricalPhotoSummary(
                                          references: references,
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                          icon: const Icon(Icons.history),
                          label: const Text(
                            'Abrir historial QA · solo lectura',
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text(
                        'BOOTSTRAP REAL Y FRAMES FLUTTER',
                        style: TextStyle(fontWeight: FontWeight.w900),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          OutlinedButton(
                            onPressed: () async {
                              await widget.harness.bootstrapLab
                                  .createLegacyRecoveryWithoutFingerprint();
                              if (mounted) {
                                setState(
                                  () =>
                                      _labMessage = 'Fixture legacy preparado',
                                );
                              }
                            },
                            child: const Text('Crear legacy sin fingerprint'),
                          ),
                          for (var run = 1; run <= 3; run++)
                            OutlinedButton(
                              onPressed: () => _runBootstrap('bootstrap-$run'),
                              child: Text('Bootstrap $run'),
                            ),
                          OutlinedButton(
                            onPressed: () async {
                              final file = await widget.harness.bootstrapLab
                                  .exportComparison();
                              await _qaDiagnosticReportChannel
                                  .invokeMethod<void>('share', {
                                    'path': file.path,
                                  });
                              if (mounted) {
                                setState(
                                  () => _labMessage =
                                      'Exportado: ${p.basename(file.path)}',
                                );
                              }
                            },
                            child: const Text('Exportar comparación'),
                          ),
                          OutlinedButton(
                            onPressed: () async {
                              await widget.harness.catalog
                                  .replaceSyntheticPhoto();
                              if (mounted) {
                                setState(
                                  () => _labMessage =
                                      'Foto QA reemplazada conservando photoId',
                                );
                              }
                            },
                            child: const Text('Reemplazar foto sintética'),
                          ),
                          OutlinedButton(
                            onPressed: _frameTelemetry.isRecording
                                ? null
                                : () async {
                                    final confirmed = await showDialog<bool>(
                                      context: context,
                                      builder: (dialogContext) => AlertDialog(
                                        title: const Text(
                                          'Restablecer sólo fixtures QA',
                                        ),
                                        content: const Text(
                                          'Se retirarán únicamente revisiones, fotos y '
                                          'telemetría del sandbox QA. Producción no es accesible.',
                                        ),
                                        actions: [
                                          TextButton(
                                            onPressed: () => Navigator.pop(
                                              dialogContext,
                                              false,
                                            ),
                                            child: const Text('Cancelar'),
                                          ),
                                          FilledButton(
                                            onPressed: () => Navigator.pop(
                                              dialogContext,
                                              true,
                                            ),
                                            child: const Text('Restablecer QA'),
                                          ),
                                        ],
                                      ),
                                    );
                                    if (confirmed != true || !mounted) return;
                                    final previous = _controller;
                                    setState(() => _controller = null);
                                    previous?.dispose();
                                    await widget.harness.resetQaFixtures();
                                    await _loadController();
                                  },
                            child: const Text('Restablecer sólo QA'),
                          ),
                        ],
                      ),
                      const Divider(),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final segment in const [
                            'ui-without-camera',
                            'gallery',
                            'camera-open',
                            'camera-return',
                            'process-death-recovery',
                          ])
                            FilledButton.tonal(
                              onPressed: () => _toggleFrameSegment(segment),
                              child: Text(
                                _frameTelemetry.isRecording
                                    ? 'Detener segmento'
                                    : segment,
                              ),
                            ),
                        ],
                      ),
                      if (_labMessage != null) Text(_labMessage!),
                      if (_lastBootstrapReport != null)
                        Text(
                          'Fingerprint: '
                          '${_lastBootstrapReport!.fingerprintAfter.substring(0, 12)} · '
                          'writes=${_lastBootstrapReport!.totalWrites}',
                        ),
                      if (_lastFrameReport != null)
                        Text(
                          const JsonEncoder().convert(
                            _lastFrameReport!.toJson(),
                          ),
                          maxLines: 4,
                          overflow: TextOverflow.ellipsis,
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Fixtures sintéticos (${fixtures.length})',
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
              Text(
                'Documentos corruptos controlados: '
                '${widget.harness.catalog.controlledCorruptCount}',
              ),
            ],
          ),
        ),
        QaFixtureSliver(fixtures: fixtures),
        const SliverPadding(padding: EdgeInsets.only(bottom: 16)),
      ],
    );
  }
}

class QaFixtureSliver extends StatelessWidget {
  const QaFixtureSliver({required this.fixtures, this.onTileBuilt, super.key});

  final List<QaFixtureRecord> fixtures;
  @visibleForTesting
  final ValueChanged<String>? onTileBuilt;

  @override
  Widget build(BuildContext context) => SliverPadding(
    padding: const EdgeInsets.symmetric(horizontal: 16),
    sliver: SliverList.builder(
      itemCount: fixtures.length,
      itemBuilder: (context, index) {
        final fixture = fixtures[index];
        onTileBuilt?.call(fixture.id);
        return RepaintBoundary(child: _FixtureTile(fixture: fixture));
      },
    ),
  );
}

class _FixtureTile extends StatelessWidget {
  const _FixtureTile({required this.fixture});

  final QaFixtureRecord fixture;

  @override
  Widget build(BuildContext context) => Card(
    child: ListTile(
      leading: const Icon(Icons.science_outlined),
      title: Text(fixture.account),
      subtitle: Text('${fixture.id}\n${fixture.state.name}'),
      isThreeLine: true,
      trailing: const Chip(label: Text('QA')),
    ),
  );
}
