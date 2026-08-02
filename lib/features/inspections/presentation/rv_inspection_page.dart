import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../../app/theme/app_theme.dart';
import '../../../core/services/app_state.dart';
import '../../../core/widgets/common_widgets.dart';
import '../../checklist/presentation/dynamic_checklist_renderer.dart';
import '../domain/rv_draft.dart';
import '../domain/rv_sync_state.dart';
import 'rv_inspection_controller.dart';
import 'rv_review_navigation.dart';
import 'rv_steps_one_two.dart';

class RvInspectionPage extends StatefulWidget {
  const RvInspectionPage({required this.hydrantId, super.key});
  final String hydrantId;
  @override
  State<RvInspectionPage> createState() => _RvInspectionPageState();
}

class _RvInspectionPageState extends State<RvInspectionPage> {
  RvInspectionController? controller;
  String? startupError;
  bool _allowPop = false;

  Future<void> _leaveFlow() async {
    if (!mounted) return;
    setState(() => _allowPop = true);
    await WidgetsBinding.instance.endOfFrame;
    if (mounted) context.pop();
  }

  Future<void> _handleBack() async {
    final activeController = controller;
    final draft = activeController?.draft;
    if (draft == null || activeController!.busy) return;
    if (draft.activeFormStep > 0) {
      await activeController.goToPreviousStep();
      return;
    }
    final hasRelevantChanges =
        draft.answers.isNotEmpty ||
        draft.location != null ||
        draft.signal != null ||
        draft.photos.values.any((items) => items.isNotEmpty) ||
        draft.parcelValveConfiguration != null ||
        (draft.generalObservations?.trim().isNotEmpty ?? false);
    if (!hasRelevantChanges) {
      await _leaveFlow();
      return;
    }
    final exit = await RvReviewNavigation.requestExitReview(context);
    if (!exit || !mounted) return;
    await _leaveFlow();
  }

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
      catalogs: state.dynamicCatalogRepository,
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
    return PopScope(
      canPop: _allowPop,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _handleBack();
      },
      child: AnimatedBuilder(
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
              automaticallyImplyLeading: false,
              leading: IconButton(
                key: const ValueKey('rv-header-back'),
                tooltip: 'Atrás',
                onPressed: controller!.busy ? null : _handleBack,
                icon: const Icon(Icons.arrow_back),
              ),
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
                DynamicChecklistRenderer(
                  controller: controller!,
                  stepOne: RvStepOnePanel(controller: controller!),
                  stepTwo: RvStepTwoPhotoPanel(controller: controller!),
                  onExitRequested: _handleBack,
                  onSummary: () => context.push(
                    '/hydrants/${widget.hydrantId}/inspection/a/summary/${draft.clientInspectionId}',
                  ),
                ),
                if (draft.returnToSummary) ...[
                  const SizedBox(height: 10),
                  FilledButton.tonalIcon(
                    onPressed: () async {
                      await controller!.clearSummaryReturn();
                      if (context.mounted) {
                        context.push(
                          '/hydrants/${widget.hydrantId}/inspection/a/summary/${draft.clientInspectionId}',
                        );
                      }
                    },
                    icon: const Icon(Icons.arrow_back),
                    label: const Text('Volver al resumen'),
                  ),
                ],
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
                  label: Text(
                    'Resumen · ${validation.issues.length} pendientes',
                  ),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: _leaveFlow,
                  child: const Text('Continuar después'),
                ),
              ],
            ),
          );
        },
      ),
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
    RvLocalStatus.conflict => 'Conflicto',
    RvLocalStatus.requiresAuthentication => 'Requiere autenticación',
    RvLocalStatus.cancelled => 'Cancelada',
    RvLocalStatus.syncError => 'Error de sincronización',
    _ => 'Pendiente de sincronización',
  };
}

// Kept temporarily as a reference while the pattern remains limited to steps 1–2.
// ignore: unused_element
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
                      : controller.captureLocationAndSignal,
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
                  onPressed: draft.isReadOnly
                      ? null
                      : controller.captureLocationAndSignal,
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
                    draft.photosFor(slot).isNotEmpty
                        ? Icons.check_circle
                        : Icons.camera_alt_outlined,
                    color: draft.photosFor(slot).isNotEmpty
                        ? AppColors.green
                        : AppColors.orange,
                  ),
                  title: Text(rvPhotoSlotLabels[slot]!),
                  subtitle: Text(
                    _photoLabel(
                      draft.photosFor(slot).isEmpty
                          ? null
                          : draft.photosFor(slot).first.status,
                    ),
                  ),
                  trailing: Wrap(
                    children: [
                      if (draft.photosFor(slot).isNotEmpty)
                        IconButton(
                          tooltip: 'Eliminar',
                          onPressed: draft.isReadOnly
                              ? null
                              : () => controller.removePhoto(
                                  slot,
                                  draft.photosFor(slot).first.photoId,
                                ),
                          icon: const Icon(Icons.delete_outline),
                        ),
                      TextButton(
                        onPressed: draft.isReadOnly
                            ? null
                            : () =>
                                  controller.addPhoto(slot, ImageSource.camera),
                        child: Text(
                          draft.photosFor(slot).isNotEmpty
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
