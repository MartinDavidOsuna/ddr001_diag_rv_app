import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/services/app_state.dart';
import '../domain/visual_report.dart';

String rvReportTitle(String accountNumber) =>
    'Reporte RV - Hidrante ${accountNumber.trim()}';

class RvVisualReportPage extends StatefulWidget {
  const RvVisualReportPage({required this.accountNumber, super.key});
  final String accountNumber;
  @override
  State<RvVisualReportPage> createState() => _RvVisualReportPageState();
}

class _RvVisualReportPageState extends State<RvVisualReportPage> {
  late Future<VisualReport> _future;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _future = _load();
  }

  Future<VisualReport> _load() {
    final state = context.read<AppState>();
    return state.visualReportRepository!.byAccount(
      widget.accountNumber,
      userId: state.user.id,
      online: state.online,
    );
  }

  void _retry() => setState(() => _future = _load());
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(rvReportTitle(widget.accountNumber))),
    body: SafeArea(
      child: FutureBuilder<VisualReport>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return Center(
              child: Semantics(
                label: 'Cargando reporte',
                child: CircularProgressIndicator(),
              ),
            );
          }
          if (snapshot.hasError) {
            return _ReportError(error: snapshot.error, onRetry: _retry);
          }
          return _ReportBody(report: snapshot.requireData);
        },
      ),
    ),
  );
}

class _ReportError extends StatelessWidget {
  const _ReportError({required this.error, required this.onRetry});
  final Object? error;
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) {
    final text = error is ApiException
        ? (error as ApiException).message
        : 'No fue posible abrir el reporte.';
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_outlined, size: 48),
            const SizedBox(height: 12),
            Text(text, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Reintentar'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReportBody extends StatelessWidget {
  const _ReportBody({required this.report});
  final VisualReport report;
  static String status(String value) => switch (value) {
    'validated' => 'Validado',
    'returned' => 'Devuelto para corrección',
    'conflict' => 'Conflicto',
    'submitted' => 'Pendiente de validación',
    'reopened' => 'En proceso',
    _ => 'Sincronizado',
  };
  @override
  Widget build(BuildContext context) {
    final all = report.photos.all;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 840),
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Semantics(
              header: true,
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Hidrante ${report.accountNumber}',
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          Chip(label: Text(status(report.status))),
                          Chip(
                            label: Text(
                              'Versión actual: ${report.versionNumber}',
                            ),
                          ),
                          Chip(label: Text('Ronda RV ${report.roundNumber}')),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(_date(report.lastStatusChangedAt)),
                      Text(
                        '${report.reviewer.displayName} · ${report.reviewer.crewName}',
                      ),
                      if (report.hasPendingChanges)
                        const Text('Cambios pendientes de sincronizar'),
                    ],
                  ),
                ),
              ),
            ),
            if (report.conflict != null)
              _ConflictCard(conflict: report.conflict!),
            _SummaryCard(
              title: 'Ubicación',
              icon: Icons.location_on_outlined,
              lines: report.location == null
                  ? const ['No capturado']
                  : [
                      'Latitud: ${report.location!.latitude}',
                      'Longitud: ${report.location!.longitude}',
                      'Altitud: ${report.location!.altitude}',
                      'Precisión: ${report.location!.accuracy}',
                      'Fuente: ${report.location!.source}',
                    ],
            ),
            _SummaryCard(
              title: 'Señal',
              icon: Icons.signal_cellular_alt,
              lines: report.signal == null
                  ? const ['No capturado']
                  : [
                      'Generación: ${report.signal!.generation}',
                      'Red: ${report.signal!.networkType}',
                      'Operador: ${report.signal!.carrier}',
                      'Intensidad: ${report.signal!.dbm} dBm',
                      'Conectado: ${report.signal!.connected}',
                    ],
            ),
            for (final section in report.sections)
              Card(
                child: ExpansionTile(
                  initiallyExpanded: report.sections.length < 4,
                  title: Text(section.title),
                  children: [
                    for (final item in section.items)
                      ListTile(
                        title: Text(item.label),
                        subtitle: item.notes == null ? null : Text(item.notes!),
                        trailing: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 260),
                          child: Text(
                            item.displayValue,
                            textAlign: TextAlign.end,
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: item.notApplicable ? Colors.grey : null,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            if (all.isNotEmpty)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Fotografías (${all.length})',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      GridView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        gridDelegate:
                            const SliverGridDelegateWithMaxCrossAxisExtent(
                              maxCrossAxisExtent: 180,
                              childAspectRatio: .9,
                              crossAxisSpacing: 8,
                              mainAxisSpacing: 8,
                            ),
                        itemCount: all.length,
                        itemBuilder: (context, index) => _PhotoTile(
                          photo: all[index],
                          all: all,
                          index: index,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            _SummaryCard(
              title: 'Observaciones',
              icon: Icons.notes,
              lines: report.observations.isEmpty
                  ? const ['No capturado']
                  : [for (final x in report.observations) x.text],
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  static String _date(DateTime? value) => value == null
      ? 'No capturado'
      : DateFormat("d MMM yyyy · HH:mm", 'es').format(value);
}

class _ConflictCard extends StatelessWidget {
  const _ConflictCard({required this.conflict});
  final ReportConflict conflict;
  @override
  Widget build(BuildContext context) => Card(
    color: Theme.of(context).colorScheme.errorContainer,
    child: ListTile(
      leading: const Icon(Icons.warning_amber),
      title: Text(
        conflict.type == 'concurrent_edit'
            ? 'Conflicto de edición'
            : 'Conflicto de revisión',
      ),
      subtitle: Text(conflict.message),
    ),
  );
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.title,
    required this.icon,
    required this.lines,
  });
  final String title;
  final IconData icon;
  final List<String> lines;
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon),
              const SizedBox(width: 8),
              Text(title, style: Theme.of(context).textTheme.titleMedium),
            ],
          ),
          const SizedBox(height: 8),
          for (final line in lines) Text(line),
        ],
      ),
    ),
  );
}

class _PhotoTile extends StatelessWidget {
  const _PhotoTile({
    required this.photo,
    required this.all,
    required this.index,
  });
  final ReportPhoto photo;
  final List<ReportPhoto> all;
  final int index;
  @override
  Widget build(BuildContext context) {
    final repo = context.read<AppState>().visualReportRepository!;
    return Semantics(
      label: 'Abrir ${photo.title}',
      button: true,
      child: InkWell(
        onTap: photo.available
            ? () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) =>
                      RvPhotoViewer(photos: all, initialIndex: index),
                ),
              )
            : null,
        child: Card(
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              Expanded(
                child: FutureBuilder<List<int>>(
                  future: repo.photo(photo.thumbnailUrl),
                  builder: (context, s) => s.hasData
                      ? Image.memory(
                          Uint8List.fromList(s.data!),
                          fit: BoxFit.cover,
                          width: double.infinity,
                        )
                      : s.hasError
                      ? const Icon(Icons.broken_image_outlined)
                      : const Center(child: CircularProgressIndicator()),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(6),
                child: Text(
                  photo.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class RvPhotoViewer extends StatefulWidget {
  const RvPhotoViewer({required this.photos, this.initialIndex = 0, super.key});
  final List<ReportPhoto> photos;
  final int initialIndex;
  @override
  State<RvPhotoViewer> createState() => _RvPhotoViewerState();
}

class _RvPhotoViewerState extends State<RvPhotoViewer> {
  late final PageController controller = PageController(
    initialPage: widget.initialIndex,
  );
  late int index = widget.initialIndex;
  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final photo = widget.photos[index];
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text('${index + 1} de ${widget.photos.length} · ${photo.title}'),
      ),
      body: PageView.builder(
        controller: controller,
        onPageChanged: (v) => setState(() => index = v),
        itemCount: widget.photos.length,
        itemBuilder: (context, i) => _FullPhoto(photo: widget.photos[i]),
      ),
    );
  }
}

class _FullPhoto extends StatefulWidget {
  const _FullPhoto({required this.photo});
  final ReportPhoto photo;
  @override
  State<_FullPhoto> createState() => _FullPhotoState();
}

class _FullPhotoState extends State<_FullPhoto> {
  late Future<List<int>> future;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    future = context.read<AppState>().visualReportRepository!.photo(
      widget.photo.viewerUrl,
    );
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<List<int>>(
    future: future,
    builder: (context, s) {
      if (s.hasData) {
        return Semantics(
          label: widget.photo.title,
          image: true,
          child: InteractiveViewer(
            minScale: 1,
            maxScale: 5,
            child: Center(
              child: Image.memory(
                Uint8List.fromList(s.data!),
                fit: BoxFit.contain,
              ),
            ),
          ),
        );
      }
      if (s.hasError) {
        return Center(
          child: FilledButton.icon(
            onPressed: () => setState(
              () => future = context
                  .read<AppState>()
                  .visualReportRepository!
                  .photo(widget.photo.viewerUrl),
            ),
            icon: const Icon(Icons.refresh),
            label: const Text('Reintentar fotografía'),
          ),
        );
      }
      return const Center(child: CircularProgressIndicator());
    },
  );
}
