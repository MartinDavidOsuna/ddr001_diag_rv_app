import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../app/theme/app_theme.dart';
import '../../../core/services/app_state.dart';
import '../../../core/widgets/common_widgets.dart';
import '../../checklist/presentation/dynamic_checklist_renderer.dart';
import '../domain/rv_draft.dart';
import '../domain/rv_sync_state.dart';
import 'rv_inspection_controller.dart';

class RvInspectionPage extends StatefulWidget {
  const RvInspectionPage({required this.hydrantId, super.key});
  final String hydrantId;
  @override
  State<RvInspectionPage> createState() => _RvInspectionPageState();
}

class _RvInspectionPageState extends State<RvInspectionPage> {
  RvInspectionController? controller;
  String? startupError;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (controller != null || startupError != null) return;
    final state = context.read<AppState>();
    final checklist = state.activeChecklist;
    if (checklist == null) {
      startupError =
          state.checklistError ??
          'No existe un checklist RV disponible. Sincroniza primero.';
      return;
    }
    controller = RvInspectionController(
      drafts: state.rvDraftRepository,
      coordinator: state.inspectionSyncCoordinator,
      hydrant: state.hydrant(widget.hydrantId),
      user: state.user,
      checklist: checklist,
    )..initialize();
  }

  @override
  void dispose() {
    controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (startupError != null) {
      return Scaffold(
        appBar: const AppPageHeader(title: 'Revisión visual'),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(startupError!, textAlign: TextAlign.center),
          ),
        ),
      );
    }
    return AnimatedBuilder(
      animation: controller!,
      builder: (context, _) {
        final draft = controller!.draft;
        if (draft == null)
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        final validation = controller!.validator.validate(draft);
        return Scaffold(
          appBar: AppPageHeader(
            title: 'Revisión visual',
            subtitle: draft.accountNumber,
          ),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _Status(draft: draft),
              if (controller!.message != null) ...[
                const SizedBox(height: 8),
                Text(
                  controller!.message!,
                  style: TextStyle(
                    color: draft.lastSyncError == null
                        ? AppColors.green
                        : AppColors.red,
                  ),
                ),
              ],
              const SizedBox(height: 14),
              DynamicChecklistRenderer(controller: controller!),
              _Evidence(controller: controller!),
              const SizedBox(height: 14),
              FilledButton.icon(
                onPressed: controller!.busy || draft.isReadOnly
                    ? null
                    : () => controller!.synchronize(),
                icon: const Icon(Icons.sync),
                label: const Text('Sincronizar ahora'),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () => context.push(
                  '/hydrants/${widget.hydrantId}/inspection/a/summary/${draft.clientInspectionId}',
                ),
                icon: const Icon(Icons.fact_check_outlined),
                label: Text('Resumen · ${validation.issues.length} pendientes'),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => context.pop(),
                child: const Text('Continuar después'),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _Status extends StatelessWidget {
  const _Status({required this.draft});
  final RvDraft draft;
  @override
  Widget build(BuildContext context) => SectionCard(
    child: Row(
      children: [
        const Icon(Icons.assignment_outlined, color: AppColors.teal),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _label(draft.localStatus),
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              Text(
                'Checklist ${draft.checklistVersion} · ${draft.clientInspectionId.substring(0, 8)}',
                style: const TextStyle(color: AppColors.muted, fontSize: 12),
              ),
            ],
          ),
        ),
      ],
    ),
  );
  String _label(RvLocalStatus status) => switch (status) {
    RvLocalStatus.draft => 'Borrador local',
    RvLocalStatus.pendingCreate => 'Pendiente de crear',
    RvLocalStatus.creating => 'Creando inspección',
    RvLocalStatus.pendingAnswers => 'Sincronizando respuestas',
    RvLocalStatus.pendingLocation => 'Sincronizando ubicación',
    RvLocalStatus.pendingSignal => 'Sincronizando señal',
    RvLocalStatus.pendingPhotos => 'Subiendo fotografías',
    RvLocalStatus.readyToSubmit => 'Lista para enviar',
    RvLocalStatus.submitting => 'Enviando',
    RvLocalStatus.submitted => 'Enviada',
    RvLocalStatus.cancelled => 'Cancelada',
    RvLocalStatus.syncError => 'Error de sincronización',
    _ => 'Pendiente de sincronización',
  };
}

class _Evidence extends StatelessWidget {
  const _Evidence({required this.controller});
  final RvInspectionController controller;
  @override
  Widget build(BuildContext context) {
    final draft = controller.draft!;
    return Column(
      children: [
        SectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'UBICACIÓN Y CONECTIVIDAD',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.location_on_outlined),
                title: Text(
                  draft.location == null
                      ? 'Sin ubicación disponible'
                      : 'Ubicación capturada',
                ),
                subtitle: draft.location == null
                    ? null
                    : Text(
                        'Precisión aproximada: ${draft.location!.horizontalAccuracy?.toStringAsFixed(1) ?? 'no disponible'} m\n${draft.location!.capturedAt.toLocal()}',
                      ),
                trailing: TextButton(
                  onPressed: draft.isReadOnly
                      ? null
                      : controller.captureLocation,
                  child: const Text('Capturar'),
                ),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.signal_cellular_alt),
                title: Text(
                  draft.signal == null
                      ? 'Señal no capturada'
                      : 'Conectividad capturada',
                ),
                subtitle: draft.signal == null
                    ? null
                    : Text(
                        '${draft.signal!.networkType ?? draft.signal!.generation} · ${draft.signal!.capturedAt.toLocal()}',
                      ),
                trailing: TextButton(
                  onPressed: draft.isReadOnly ? null : controller.captureSignal,
                  child: const Text('Capturar'),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        SectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'FOTOGRAFÍAS OBLIGATORIAS',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
              for (final slot in requiredRvPhotoSlots)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    draft.photos.containsKey(slot)
                        ? Icons.check_circle
                        : Icons.camera_alt_outlined,
                    color: draft.photos.containsKey(slot)
                        ? AppColors.green
                        : AppColors.orange,
                  ),
                  title: Text(rvPhotoSlotLabels[slot]!),
                  subtitle: Text(_photoLabel(draft.photos[slot]?.status)),
                  trailing: Wrap(
                    children: [
                      if (draft.photos.containsKey(slot))
                        IconButton(
                          tooltip: 'Eliminar',
                          onPressed: draft.isReadOnly
                              ? null
                              : () => controller.removePhoto(slot),
                          icon: const Icon(Icons.delete_outline),
                        ),
                      TextButton(
                        onPressed: draft.isReadOnly
                            ? null
                            : () => controller.capturePhoto(slot),
                        child: Text(
                          draft.photos.containsKey(slot)
                              ? 'Reemplazar'
                              : 'Capturar',
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  String _photoLabel(RvPhotoUploadStatus? status) => switch (status) {
    null => 'Fotografía pendiente',
    RvPhotoUploadStatus.pending => 'Pendiente de subir',
    RvPhotoUploadStatus.uploading => 'Subiendo',
    RvPhotoUploadStatus.verified => 'Subida',
    RvPhotoUploadStatus.error => 'Error · Reintentar',
    RvPhotoUploadStatus.missingLocal => 'Archivo inexistente',
  };
}

// ignore_for_file: curly_braces_in_flow_control_structures
