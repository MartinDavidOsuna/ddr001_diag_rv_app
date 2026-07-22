import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../app/theme/app_theme.dart';
import '../../core/constants/report_type_labels.dart';
import '../../core/services/app_state.dart';
import '../../core/widgets/common_widgets.dart';
import '../../domain/enums/app_enums.dart';
import '../../domain/enums/hydrant_list_filter.dart';
import '../../domain/filters/hydrant_filter_request.dart';
import '../../domain/models/app_models.dart';
import '../../domain/filters/hydrant_query_projection.dart';
import '../../domain/functional/functional_models.dart';
import '../../domain/inspections/visual_inspection.dart';
import 'widgets/auto_visible_filter_bar.dart';

String statusLabel(InspectionStatus s) => switch (s) {
  InspectionStatus.pending => 'Pendiente',
  InspectionStatus.inProgress => 'En proceso',
  InspectionStatus.completed => 'Terminado',
  InspectionStatus.scheduled => 'Programado',
  InspectionStatus.notRequired => 'No requerido',
  InspectionStatus.returned => 'Devuelto',
  InspectionStatus.validated => 'Validado',
};
String syncLabel(SyncStatus s) => switch (s) {
  SyncStatus.local => 'Guardado localmente',
  SyncStatus.pending => 'Sin sincronizar',
  SyncStatus.synced => 'Sincronizado',
  SyncStatus.returned => 'Devuelto',
  SyncStatus.validated => 'Validado',
};

class HydrantsPage extends StatefulWidget {
  const HydrantsPage({super.key});
  @override
  State<HydrantsPage> createState() => _HydrantsPageState();
}

class _HydrantsPageState extends State<HydrantsPage> {
  String query = '';
  final searchController = TextEditingController();
  OverlayEntry? assignmentNotice;
  String? preparedHomeRequestId;

  @override
  void dispose() {
    assignmentNotice?.remove();
    searchController.dispose();
    super.dispose();
  }

  Future<void> syncAssignments(AppState state) async {
    if (state.assignmentSyncing) return;
    await state.synchronizeNextAssignmentScenario();
    if (!mounted) return;
    final result = state.lastAssignmentResult;
    final failed = state.assignmentError != null;
    final changed =
        result != null &&
        result.newCount + result.updatedCount + result.removedCount > 0;
    final message = failed
        ? 'No fue posible actualizar asignaciones.'
        : result?.newCount == 2
        ? '2 asignaciones nuevas.'
        : changed
        ? '1 actualizada · 1 retirada.'
        : 'Sin asignaciones nuevas.';
    showAssignmentNotice(
      '${DateTime.now().toLocal().toString().substring(0, 16)}\n$message',
      failed
          ? AppColors.red
          : changed
          ? AppColors.orange
          : AppColors.green,
    );
  }

  void showAssignmentNotice(String message, Color color) {
    assignmentNotice?.remove();
    final overlay = Overlay.of(context);
    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (context) => Positioned(
        top: MediaQuery.paddingOf(context).top + 62,
        left: 12,
        right: 12,
        child: _AssignmentNotice(message: message, color: color),
      ),
    );
    assignmentNotice = entry;
    overlay.insert(entry);
    Future<void>.delayed(const Duration(seconds: 5), () {
      if (assignmentNotice == entry) {
        entry.remove();
        assignmentNotice = null;
      }
    });
  }

  bool matchesSearch(Hydrant h) => '${h.code} ${h.locality} ${h.parcel}'
      .toLowerCase()
      .contains(query.toLowerCase());

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final request = state.hydrantFilterRequest;
    if (request?.source == HydrantFilterRequestSource.home &&
        request?.id != preparedHomeRequestId) {
      preparedHomeRequestId = request?.id;
      query = '';
      searchController.clear();
    }
    final items = state
        .hydrantsForFilter(state.hydrantListFilter)
        .where(matchesSearch)
        .toList();
    return Scaffold(
      appBar: AppPageHeader(
        title: 'Hidrantes',
        subtitle: '${state.hydrants.length} asignados',
        actions: [
          IconButton(
            constraints: const BoxConstraints.tightFor(width: 48, height: 48),
            tooltip: 'Sincronizar asignaciones',
            onPressed: state.assignmentSyncing
                ? null
                : () => syncAssignments(state),
            icon: state.assignmentSyncing
                ? const SizedBox.square(
                    dimension: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.refresh),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: ConnectionBadge(online: state.online),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: state.editingRestricted
            ? null
            : () {
                state.trace('new_survey_open', 'Abrir nuevo levantamiento');
                context.push('/hydrants/new');
              },
        icon: const Icon(Icons.add_location_alt_outlined),
        label: const Text('NUEVO LEVANTAMIENTO'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: searchController,
              onChanged: (v) => setState(() => query = v),
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Buscar código, localidad, parcela...',
              ),
            ),
          ),
          AutoVisibleFilterBar<HydrantListFilter>(
            values: HydrantQueryProjection.visibleFilters,
            selected: state.hydrantListFilter,
            labelFor: _filterLabel,
            isActive: TickerMode.valuesOf(context).enabled,
            visibilityRequestId: state.hydrantFilterRequest?.id,
            onVisibilityRequestConsumed: (requestId) {
              state.consumeHydrantFilterRequest(requestId);
              if (mounted) setState(() {});
            },
            onSelected: (filter) {
              if (filter == HydrantListFilter.all) {
                state.clearHydrantListFilter();
              } else {
                state.setHydrantListFilter(filter);
              }
            },
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '${items.length} resultados',
                style: const TextStyle(color: AppColors.muted, fontSize: 12),
              ),
            ),
          ),
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 90),
              itemCount: items.length,
              separatorBuilder: (_, _) => const SizedBox(height: 9),
              itemBuilder: (_, i) => HydrantCard(
                hydrant: items[i],
                onTap: () {
                  state.trace(
                    'hydrant_open',
                    'Abrir ficha de hidrante',
                    hydrantId: items[i].id,
                  );
                  context.push('/hydrants/${items[i].id}');
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _filterLabel(HydrantListFilter value) => switch (value) {
    HydrantListFilter.all => 'Todos',
    HydrantListFilter.visualReport => ReportTypeLabels.visualShort,
    HydrantListFilter.functionalReport => ReportTypeLabels.functionalShort,
    HydrantListFilter.inProgress => 'En proceso',
    HydrantListFilter.completed => 'Finalizado',
    HydrantListFilter.visualPending =>
      '${ReportTypeLabels.visualShort} pendiente',
    HydrantListFilter.visualInProgress =>
      '${ReportTypeLabels.visualShort} en proceso',
    HydrantListFilter.visualCompleted =>
      '${ReportTypeLabels.visualShort} finalizado',
    HydrantListFilter.functionalPending =>
      '${ReportTypeLabels.functionalShort} pendiente',
    HydrantListFilter.functionalInProgress =>
      '${ReportTypeLabels.functionalShort} en proceso',
    HydrantListFilter.functionalCompleted =>
      '${ReportTypeLabels.functionalShort} finalizado',
    HydrantListFilter.functionalRequired =>
      '${ReportTypeLabels.functionalShort} requerido',
    HydrantListFilter.functionalSuspended =>
      '${ReportTypeLabels.functionalShort} suspendido',
    HydrantListFilter.functionalFailed =>
      '${ReportTypeLabels.functionalShort} con falla',
    HydrantListFilter.pendingValidation => 'Pendiente de validación',
    HydrantListFilter.synchronizationPending => 'Sin sincronizar',
    HydrantListFilter.incidents => 'Con incidencias',
  };
}

class HydrantCard extends StatelessWidget {
  const HydrantCard({required this.hydrant, required this.onTap, super.key});
  final Hydrant hydrant;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final functional = state.functionalSummary(hydrant.id);
    final isB = functional.status != InspectionStatus.notRequired;
    final summary = isB ? functional : hydrant.f02a;
    final compactStatus = isB
        ? state.functionalStateLabel(hydrant.id)
        : statusLabel(summary.status);
    final color = isB ? AppColors.violet : AppColors.teal;
    final reviewRemoval = state.assignmentsForReview.contains(hydrant.id);
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      hydrant.code,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                  StatusBadge(
                    syncLabel(hydrant.syncStatus),
                    color:
                        hydrant.syncStatus == SyncStatus.synced ||
                            hydrant.syncStatus == SyncStatus.validated
                        ? AppColors.green
                        : AppColors.orange,
                  ),
                ],
              ),
              const SizedBox(height: 3),
              Text(
                '${hydrant.locality} · ${hydrant.parcel}',
                style: const TextStyle(color: AppColors.muted, fontSize: 12),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 5,
                children: [
                  StatusBadge(
                    isB
                        ? ReportTypeLabels.functionalShort
                        : ReportTypeLabels.visualShort,
                    color: color,
                  ),
                  StatusBadge(compactStatus, color: color),
                  StatusBadge(
                    hydrant.priority == PriorityLevel.high
                        ? 'Alta'
                        : hydrant.priority == PriorityLevel.medium
                        ? 'Media'
                        : 'Baja',
                    color: AppColors.orange,
                  ),
                  if (reviewRemoval)
                    const StatusBadge(
                      'Retirada · revisar',
                      color: AppColors.red,
                    ),
                ],
              ),
              if (summary.progress > 0 && summary.progress < 1) ...[
                const SizedBox(height: 10),
                LinearProgressIndicator(
                  value: summary.progress,
                  color: color,
                  backgroundColor: AppColors.border,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _AssignmentNotice extends StatefulWidget {
  const _AssignmentNotice({required this.message, required this.color});
  final String message;
  final Color color;
  @override
  State<_AssignmentNotice> createState() => _AssignmentNoticeState();
}

class _AssignmentNoticeState extends State<_AssignmentNotice> {
  bool visible = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => setState(() => visible = true),
    );
    Future<void>.delayed(const Duration(milliseconds: 4650), () {
      if (mounted) setState(() => visible = false);
    });
  }

  @override
  Widget build(BuildContext context) => AnimatedSlide(
    duration: const Duration(milliseconds: 300),
    offset: visible ? Offset.zero : const Offset(0, -1.2),
    child: Material(
      elevation: 8,
      color: widget.color,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Text(
          widget.message,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    ),
  );
}

class HydrantDetailPage extends StatelessWidget {
  const HydrantDetailPage({required this.id, super.key});
  final String id;
  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final h = state.hydrant(id);
    final functionalSummary = state.functionalSummary(id);
    final visualHistory = state.visualInspectionRepository.forHydrant(id);
    final functionalHistory = state.functionalInspectionRepository.forHydrant(
      id,
    );
    return Scaffold(
      appBar: AppPageHeader(title: h.code, subtitle: h.locality),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (state.editingRestricted) ...[
            const SectionCard(
              child: Row(
                children: [
                  Icon(Icons.lock_outline, color: AppColors.red),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Actualización obligatoria: puedes terminar borradores existentes, consultar y sincronizar. No puedes iniciar trabajos nuevos.',
                      style: TextStyle(
                        color: AppColors.red,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],
          SectionCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        h.code,
                        style: const TextStyle(
                          fontSize: 19,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    StatusBadge(
                      syncLabel(h.syncStatus),
                      color: AppColors.green,
                    ),
                  ],
                ),
                Text(
                  '${h.locality} · ${h.parcel} · Hidrante inteligente',
                  style: const TextStyle(color: AppColors.muted),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          DiagnosticCard(
            type: ReportTypeLabels.visualFull,
            summary: h.f02a,
            color: AppColors.teal,
            onPressed: () => _openInspection(context, state, h.f02a, 'a'),
          ),
          const SizedBox(height: 13),
          DiagnosticCard(
            type: ReportTypeLabels.functionalFull,
            summary: functionalSummary,
            color: AppColors.violet,
            forceEnabled: true,
            statusOverride: state.functionalStateLabel(id),
            onPressed: () =>
                _openFunctionalInspection(context, state, h, functionalSummary),
          ),
          if (functionalSummary.status == InspectionStatus.completed) ...[
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: state.editingRestricted
                  ? null
                  : () => _startFunctionalRepeat(context, state, h),
              icon: const Icon(Icons.replay),
              label: const Text('Iniciar nueva prueba de REPORTE FUNCIONAL'),
            ),
          ],
          const SizedBox(height: 16),
          Row(
            children: [
              Metric(value: '${h.photoCount}', label: 'Fotos'),
              Metric(value: '${h.damageCount}', label: 'Daños'),
              const Metric(value: '6', label: 'Historial'),
            ],
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () => context.push('/hydrants/$id/gallery'),
            icon: const Icon(Icons.photo_library_outlined),
            label: const Text('Abrir galería local'),
          ),
          if (visualHistory.length > 1 || functionalHistory.length > 1) ...[
            const SizedBox(height: 12),
            SectionCard(
              child: ExpansionTile(
                title: const Text('Original y revisiones'),
                children: [
                  for (final report in visualHistory)
                    ListTile(
                      title: Text(
                        'RV · ${report.revisionNumber == 0 ? 'Original' : 'Revisión ${report.revisionNumber}'}',
                      ),
                      subtitle: Text(
                        '${report.revisionReason.isEmpty ? 'Sin motivo de revisión' : report.revisionReason}\n${report.updatedAt.toLocal()}${report.activeRevision ? ' · Vigente' : ''}',
                      ),
                    ),
                  for (final report in functionalHistory)
                    ListTile(
                      title: Text(
                        'RF · ${report.revisionNumber == 0 ? 'Original' : 'Revisión ${report.revisionNumber}'}',
                      ),
                      subtitle: Text(
                        '${report.revisionReason.isEmpty ? 'Sin motivo de revisión' : report.revisionReason}\n${report.updatedAt.toLocal()}${report.activeRevision ? ' · Vigente' : ''}',
                      ),
                    ),
                ],
              ),
            ),
          ],
          if (state.user.role.toLowerCase().contains('supervisor') &&
              (visualHistory.any(
                    (report) => report.status == InspectionStatus.completed,
                  ) ||
                  functionalHistory.any(
                    (report) =>
                        report.status == FunctionalInspectionStatus.completed,
                  ))) ...[
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: () => _createRevision(
                context,
                state,
                visualHistory: visualHistory,
                functionalHistory: functionalHistory,
              ),
              icon: const Icon(Icons.history_edu_outlined),
              label: const Text('Crear revisión supervisada'),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _createRevision(
    BuildContext context,
    AppState state, {
    required List<VisualInspection> visualHistory,
    required List<FunctionalInspection> functionalHistory,
  }) async {
    String type =
        visualHistory.any(
          (report) => report.status == InspectionStatus.completed,
        )
        ? 'visual'
        : 'functional';
    final reasonController = TextEditingController();
    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (_, setLocal) => AlertDialog(
          title: const Text('Crear revisión de reporte'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                initialValue: type,
                items: [
                  if (visualHistory.any(
                    (report) => report.status == InspectionStatus.completed,
                  ))
                    const DropdownMenuItem(
                      value: 'visual',
                      child: Text('REPORTE VISUAL'),
                    ),
                  if (functionalHistory.any(
                    (report) =>
                        report.status == FunctionalInspectionStatus.completed,
                  ))
                    const DropdownMenuItem(
                      value: 'functional',
                      child: Text('REPORTE FUNCIONAL'),
                    ),
                ],
                onChanged: (value) => setLocal(() => type = value!),
              ),
              TextField(
                controller: reasonController,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Motivo obligatorio',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Crear revisión'),
            ),
          ],
        ),
      ),
    );
    final reason = reasonController.text.trim();
    reasonController.dispose();
    if (accepted != true || reason.isEmpty) return;
    if (type == 'visual') {
      final original = visualHistory.firstWhere(
        (report) => report.status == InspectionStatus.completed,
      );
      await state.visualInspectionRepository.createRevision(
        original,
        state.user,
        reason,
      );
    } else {
      final original = functionalHistory.firstWhere(
        (report) => report.status == FunctionalInspectionStatus.completed,
      );
      await state.functionalInspectionRepository.createRevision(
        original,
        state.user,
        reason,
      );
    }
    await state.trace(
      'report_revision_created',
      'Revisión supervisada creada',
      hydrantId: id,
      reason: reason,
    );
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Revisión creada como borrador independiente.'),
        ),
      );
    }
  }

  void _openInspection(
    BuildContext context,
    AppState state,
    InspectionSummary summary,
    String type,
  ) {
    if (state.editingRestricted &&
        summary.status != InspectionStatus.completed &&
        summary.status != InspectionStatus.inProgress &&
        !(type == 'a' &&
            state.visualInspectionRepository.hasLocalInspection(id))) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Actualiza la aplicación para iniciar o editar diagnósticos nuevos.',
          ),
        ),
      );
      return;
    }
    context.push('/hydrants/$id/inspection/$type');
  }

  Future<void> _openFunctionalInspection(
    BuildContext context,
    AppState state,
    Hydrant hydrant,
    InspectionSummary summary,
  ) async {
    if (state.editingRestricted &&
        !state.functionalInspectionRepository.hasActive(id)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'La actualización obligatoria bloquea nuevos reportes. Los borradores existentes siguen disponibles.',
          ),
        ),
      );
      return;
    }
    if (state.functionalEligibilityRepository.find(id)?.allowed != true &&
        !state.functionalInspectionRepository.hasActive(id)) {
      final controller = TextEditingController();
      final reason = await showDialog<String>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Habilitar REPORTE FUNCIONAL'),
          content: TextField(
            controller: controller,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'Autorización local o justificación',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.pop(dialogContext, controller.text.trim()),
              child: const Text('Habilitar localmente'),
            ),
          ],
        ),
      );
      controller.dispose();
      if (reason == null || reason.isEmpty) return;
      final now = DateTime.now().toUtc();
      await state.functionalEligibilityRepository.save(
        FunctionalReportEligibility(
          hydrantId: id,
          allowed: true,
          source: FunctionalEligibilitySource.manualAuthorization,
          reason: reason,
          authorizedBy: state.user.id,
          authorizedRole: state.user.role,
          deviceId: state.user.deviceId,
          authorizedAt: now,
          pendingValidation: true,
          supervisorValidationRequired: true,
          restrictions: const ['Autorización local pendiente de validación'],
          createdAt: now,
          updatedAt: now,
        ),
      );
      await state.enqueueSync(
        entityType: 'functionalEligibility',
        entityId: id,
        hydrantId: id,
      );
      await state.trace(
        'functional_eligibility_created',
        'Habilitación RF local pendiente de validación: $reason',
        hydrantId: id,
      );
    }
    if (!context.mounted) return;
    _openInspection(context, state, summary, 'b');
  }

  Future<void> _startFunctionalRepeat(
    BuildContext context,
    AppState state,
    Hydrant hydrant,
  ) async {
    if (state.functionalInspectionRepository.hasActive(id)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ya existe un REPORTE FUNCIONAL activo.')),
      );
      return;
    }
    final previous = state.functionalInspectionRepository
        .forHydrant(id)
        .where((value) => value.status == FunctionalInspectionStatus.completed)
        .firstOrNull;
    if (previous == null) return;
    final controller = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Repetir REPORTE FUNCIONAL'),
        content: TextField(
          controller: controller,
          maxLines: 2,
          decoration: const InputDecoration(labelText: 'Motivo obligatorio'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(dialogContext, controller.text.trim()),
            child: const Text('Crear nueva prueba'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (reason == null || reason.isEmpty) return;
    final created = await state.functionalInspectionRepository.createRepeat(
      hydrant,
      state.user,
      previous,
    );
    await state.trace(
      'functional_repeat_required',
      'Nueva prueba creada',
      hydrantId: id,
      inspectionId: created.id,
      reason: reason,
      metadata: {'repeatOfInspectionId': previous.id},
    );
    if (context.mounted) {
      context.push('/hydrants/$id/inspection/b');
    }
  }
}

class DiagnosticCard extends StatelessWidget {
  const DiagnosticCard({
    required this.type,
    required this.summary,
    required this.color,
    required this.onPressed,
    this.forceEnabled = false,
    this.statusOverride,
    super.key,
  });
  final String type;
  final InspectionSummary summary;
  final Color color;
  final VoidCallback onPressed;
  final bool forceEnabled;
  final String? statusOverride;
  @override
  Widget build(BuildContext context) {
    final disabled =
        summary.status == InspectionStatus.notRequired && !forceEnabled;
    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  type,
                  style: TextStyle(
                    fontSize: 16,
                    color: color,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              StatusBadge(
                statusOverride ?? statusLabel(summary.status),
                color: disabled ? AppColors.muted : color,
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (summary.progress > 0) ...[
            LinearProgressIndicator(value: summary.progress, color: color),
            const SizedBox(height: 12),
          ],
          Text(
            disabled
                ? 'Este hidrante no requiere este reporte actualmente.'
                : summary.status == InspectionStatus.notRequired
                ? 'Puede habilitarse localmente; quedará pendiente de validación.'
                : 'Información local disponible para consulta.',
            style: const TextStyle(color: AppColors.muted, fontSize: 12),
          ),
          if (!disabled) ...[
            const SizedBox(height: 12),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: color),
              onPressed: onPressed,
              child: Text(
                summary.status == InspectionStatus.completed
                    ? 'Ver diagnóstico'
                    : summary.status == InspectionStatus.scheduled
                    ? 'Iniciar diagnóstico'
                    : 'Continuar diagnóstico',
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class PlaceholderPage extends StatelessWidget {
  const PlaceholderPage({
    required this.title,
    required this.message,
    super.key,
  });
  final String title, message;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppPageHeader(title: title),
    body: Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: SectionCard(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.construction, color: AppColors.orange, size: 56),
              const SizedBox(height: 16),
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.muted),
              ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: () => context.pop(),
                child: const Text('Volver'),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
