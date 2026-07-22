import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../app/theme/app_theme.dart';
import '../../core/services/app_state.dart';
import '../../core/widgets/common_widgets.dart';
import '../../domain/media/media_sync_status.dart';
import '../../domain/sync/sync_queue_item.dart';

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
    for (final key in state.syncBox.keys) {
      final raw = state.syncBox.get(key);
      if (raw == null || raw == 'Sincronizado') continue;
      try {
        final item = SyncQueueItem.fromJson(
          Map<String, dynamic>.from(jsonDecode(raw) as Map),
        );
        if (item.status == SyncQueueStatus.synced) continue;
        diagnostics.add((
          id: item.id,
          label: '${item.entityType} · ${item.entityId}',
          status: item.status.name,
        ));
      } on Object {
        diagnostics.add((id: '$key', label: '$key', status: raw));
      }
    }
    final photos = state.mediaBox.keys
        .where(
          (key) => state.mediaBox.get(key) != MediaSyncStatus.verified.name,
        )
        .map((e) => '$e')
        .toList();
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
              child: ConnectionBadge(online: state.online),
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
                        const Text(
                          'Simulación local: la verificación remota es obligatoria',
                          style: TextStyle(
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
                    value: state.pendingPhotos,
                    detail: '${state.verifiedPhotos} verificadas',
                  ),
                  SyncCount(label: 'Trazabilidad', value: state.pendingTrace),
                  SyncCount(
                    label: 'Errores',
                    value: state.syncErrors,
                    color: state.syncErrors > 0
                        ? AppColors.red
                        : AppColors.green,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            if (state.allSynchronized)
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
                        'Fotografías verificadas: ${state.verifiedPhotos}',
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
                        status: state.mediaBox.get(id)!,
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
                '${(state.syncProgress * 100).round()}% · procesando diagnósticos, fotografías y trazabilidad',
                textAlign: TextAlign.center,
              ),
            ],
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: state.allSynchronized || !state.online || state.syncing
                  ? null
                  : state.synchronize,
              icon: const Icon(Icons.sync),
              label: Text(
                state.syncing
                    ? 'Sincronizando...'
                    : 'Sincronizar ${state.pendingCount} elementos',
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Solo MediaSyncStatus.verified cuenta como fotografía sincronizada. uploadedUnverified permanece pendiente.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 11, color: AppColors.muted),
            ),
          ],
        ),
      ),
    );
  }
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
    required this.onRetry,
    super.key,
  });
  final String id, status;
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) {
    final failed =
        status == MediaSyncStatus.failedRetryable.name ||
        status == MediaSyncStatus.failedPermanent.name ||
        status == MediaSyncStatus.missingLocal.name ||
        status == MediaSyncStatus.remoteMissing.name;
    return ListTile(
      title: Text(id, style: const TextStyle(fontWeight: FontWeight.w700)),
      subtitle: Text(failed ? '$status · Requiere atención' : status),
      trailing: failed
          ? TextButton(onPressed: onRetry, child: const Text('Reintentar'))
          : const StatusBadge('Pendiente', color: AppColors.orange),
    );
  }
}
