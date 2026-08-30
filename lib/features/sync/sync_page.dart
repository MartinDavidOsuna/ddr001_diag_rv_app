import 'package:flutter/material.dart';
import '../../data/local/media_work_item_codec.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../app/theme/app_theme.dart';
import '../../core/services/app_state.dart';
import '../../core/widgets/common_widgets.dart';
import '../../domain/sync/sync_queue_item.dart';

String syncConnectionMessage(bool online) => online
    ? 'Conectado a la API; cada elemento requiere confirmación remota'
    : 'Los cambios permanecen guardados hasta recuperar la conexión';

@visibleForTesting
String mediaSyncStatusForUi(String? persistedStatus) =>
    switch (persistedStatus) {
      'verified' => 'Sincronizado',
      'uploading' => 'Sincronizando',
      'requiresReview' => 'Requiere revisión',
      'failedRetryable' ||
      'failedPermanent' ||
      'missingLocal' ||
      'remoteMissing' => 'Requiere reintento',
      _ => 'Información pendiente',
    };

class SyncPage extends StatefulWidget {
  const SyncPage({required this.returnLocation, super.key});
  final String returnLocation;
  @override
  State<SyncPage> createState() => _SyncPageState();
}

class _SyncPageState extends State<SyncPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) =>
          context.read<AppState>().trace('sync_open', 'Abrir sincronización'),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final diagnostics = <({String id, String label, String status})>[];
    for (final item in state.syncQueueRepository.all()) {
      if (item.status == SyncQueueStatus.synced) continue;
      diagnostics.add((
        id: item.id,
        label: '${item.entityType} · ${item.entityId}',
        status: item.status.name,
      ));
    }
    final photoSummary = state.photoSyncSummary;
    final photos = photoSummary.pendingIds.toList();
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (context.canPop()) {
          context.pop();
        } else {
          context.go(widget.returnLocation);
        }
      },
      child: Scaffold(
        appBar: AppPageHeader(
          title: 'Sincronización',
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
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: (state.online ? AppColors.green : AppColors.orange)
                    .withValues(alpha: .1),
                border: Border.all(
                  color: (state.online ? AppColors.green : AppColors.orange)
                      .withValues(alpha: .35),
                ),
                borderRadius: BorderRadius.circular(13),
              ),
              child: Row(
                children: [
                  Icon(
                    state.online
                        ? Icons.check_circle_outline
                        : Icons.cloud_off_outlined,
                    color: state.online ? AppColors.green : AppColors.orange,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          state.online ? 'Conexión disponible' : 'Sin conexión',
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                        Text(
                          syncConnectionMessage(state.online),
                          style: const TextStyle(
                            fontSize: 11,
                            color: AppColors.muted,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            SectionCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'ESTADO GLOBAL',
                    style: TextStyle(fontSize: 12, color: AppColors.muted),
                  ),
                  const SizedBox(height: 14),
                  SyncCount(
                    label: 'Diagnósticos',
                    value: state.pendingDiagnostics,
                  ),
                  SyncCount(
                    label: 'Fotografías',
                    value: photoSummary.pendingIds.length,
                    detail: '${photoSummary.verified} verificadas',
                  ),
                  SyncCount(
                    label: 'Errores',
                    value: photoSummary.errors,
                    color: photoSummary.errors > 0
                        ? AppColors.red
                        : AppColors.green,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            if (state.pendingDiagnostics == 0 &&
                photoSummary.pendingIds.isEmpty &&
                photoSummary.errors == 0)
              SectionCard(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Column(
                    children: [
                      const Icon(
                        Icons.check_circle_outline,
                        color: AppColors.green,
                        size: 54,
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'Todo sincronizado',
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
                      Text(
                        'Fotografías verificadas: ${photoSummary.verified}',
                        style: const TextStyle(color: AppColors.muted),
                      ),
                    ],
                  ),
                ),
              )
            else ...[
              if (diagnostics.isNotEmpty)
                PendingGroup(
                  title: 'DIAGNÓSTICOS PENDIENTES',
                  children: [
                    for (final item in diagnostics)
                      ListTile(
                        title: Text(
                          item.label,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        subtitle: Text(item.status),
                        trailing: const StatusBadge(
                          'Pendiente',
                          color: AppColors.orange,
                        ),
                      ),
                  ],
                ),
              if (photos.isNotEmpty) ...[
                const SizedBox(height: 12),
                PendingGroup(
                  title: 'FOTOGRAFÍAS',
                  children: [
                    for (final id in photos)
                      PhotoRow(
                        id: id,
                        status: mediaSyncStatusForUi(
                          MediaWorkItemCodec.statusOf(
                            id,
                            state.mediaBox.get(id),
                          ),
                        ),
                        error: photoSummary.errorById[id],
                        onRetry: () => state.retryMedia(id),
                      ),
                  ],
                ),
              ],
            ],
            if (state.syncing) ...[
              const SizedBox(height: 18),
              LinearProgressIndicator(value: state.syncProgress),
              const SizedBox(height: 7),
              Text(
                '${state.syncCompleted} de ${state.syncTotal} · ${_stageLabel(state.syncStage)}${state.syncingReport == null ? '' : ' · hidrante ${state.syncingReport}'}',
                textAlign: TextAlign.center,
              ),
            ],
            if (state.syncPauseMessage != null) ...[
              const SizedBox(height: 12),
              Text(
                state.syncPauseMessage!,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AppColors.orange,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed:
                  (state.pendingDiagnostics == 0 &&
                          photoSummary.pendingIds.isEmpty &&
                          photoSummary.errors == 0) ||
                      !state.online ||
                      state.syncing
                  ? null
                  : state.synchronize,
              icon: const Icon(Icons.sync),
              label: Text(
                state.syncing ? 'Sincronizando...' : 'Sincronizar todo',
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Una fotografía cuenta como sincronizada únicamente después de la confirmación del servidor.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 11, color: AppColors.muted),
            ),
          ],
        ),
      ),
    );
  }

  String _stageLabel(GlobalSyncStage stage) => switch (stage) {
    GlobalSyncStage.idle => 'En espera',
    GlobalSyncStage.waitingConnection => 'Esperando conexión',
    GlobalSyncStage.preparing => 'Preparando',
    GlobalSyncStage.catalogs => 'Sincronizando catálogos',
    GlobalSyncStage.reports => 'Enviando revisiones y fotografías',
    GlobalSyncStage.projections => 'Actualizando hidrantes',
    GlobalSyncStage.completed => 'Completado',
    GlobalSyncStage.completedWithWarnings => 'Completado con advertencias',
    GlobalSyncStage.paused => 'Pausado por red',
  };
}

class SyncCount extends StatelessWidget {
  const SyncCount({
    required this.label,
    required this.value,
    this.detail,
    this.color = AppColors.ink,
    super.key,
  });
  final String label;
  final int value;
  final String? detail;
  final Color color;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Row(
      children: [
        Icon(Icons.upload_outlined, color: color, size: 20),
        const SizedBox(width: 10),
        Text(label),
        if (detail != null)
          Text(
            ' · $detail',
            style: const TextStyle(fontSize: 11, color: AppColors.muted),
          ),
        const Spacer(),
        Text(
          '$value',
          style: TextStyle(fontWeight: FontWeight.w800, color: color),
        ),
      ],
    ),
  );
}

class PendingGroup extends StatelessWidget {
  const PendingGroup({required this.title, required this.children, super.key});
  final String title;
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => SectionCard(
    padding: EdgeInsets.zero,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            title,
            style: const TextStyle(fontSize: 12, color: AppColors.muted),
          ),
        ),
        ...children,
      ],
    ),
  );
}

class PhotoRow extends StatelessWidget {
  const PhotoRow({
    required this.id,
    required this.status,
    this.error,
    required this.onRetry,
    super.key,
  });
  final String id, status;
  final String? error;
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) {
    final failed =
        status == 'Requiere reintento' || status == 'Requiere revisión';
    return ListTile(
      title: const Text(
        'Fotografía',
        style: TextStyle(fontWeight: FontWeight.w700),
      ),
      subtitle: Text(
        failed
            ? error?.trim().isNotEmpty == true
                  ? error!
                  : '$status · Requiere atención'
            : status,
      ),
      trailing: failed
          ? TextButton(onPressed: onRetry, child: const Text('Reintentar'))
          : const StatusBadge('Pendiente', color: AppColors.orange),
    );
  }
}
