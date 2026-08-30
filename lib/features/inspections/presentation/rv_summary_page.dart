import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../app/theme/app_theme.dart';
import '../../../core/services/app_state.dart';
import '../../../core/media/image_decode_policy.dart';
import '../../../core/formatters/person_name_formatter.dart';
import '../../../core/widgets/common_widgets.dart';
import '../../../domain/media/inspection_photo.dart';
import '../domain/rv_sync_state.dart';
import '../domain/rv_validator.dart';
import '../domain/rv_draft.dart';
import 'inspection_photo_projection.dart';
import 'rv_review_navigation.dart';

class RvSummaryPage extends StatefulWidget {
  const RvSummaryPage({
    required this.hydrantId,
    required this.clientInspectionId,
    super.key,
  });
  final String hydrantId, clientInspectionId;
  @override
  State<RvSummaryPage> createState() => _RvSummaryPageState();
}

class _RvSummaryPageState extends State<RvSummaryPage>
    with SingleTickerProviderStateMixin {
  bool busy = false;
  String? message;
  final _submissionGate = RvSubmissionCompletionGate();
  late final AnimationController _sendingAnimation;

  @override
  void initState() {
    super.initState();
    _sendingAnimation = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );
  }

  @override
  void dispose() {
    _sendingAnimation.dispose();
    super.dispose();
  }

  void _setBusy(bool value) {
    setState(() => busy = value);
    value ? _sendingAnimation.repeat() : _sendingAnimation.stop();
  }

  @override
  Widget build(BuildContext context) => RvSummaryFailureBoundary(
    hydrantId: widget.hydrantId,
    clientInspectionId: widget.clientInspectionId,
    builder: _buildSummary,
  );

  Widget _buildSummary(BuildContext context) {
    final state = context.watch<AppState>();
    final draft = state.rvDraftRepository.find(widget.clientInspectionId);
    if (draft == null)
      return const Scaffold(
        body: Center(child: Text('No se encontró el borrador.')),
      );
    final validation = const RvValidator().validate(draft);
    final syncedValidation = const RvValidator().validate(
      draft,
      requireSynced: true,
    );
    final totalQuestions = draft.checklist.sections
        .expand((e) => e.items)
        .where(
          (e) => !const {
            'photo',
            'coordinates',
            'signal',
            'readonly',
          }.contains(e.type),
        )
        .length;
    final photoReferences = draft.photos.values
        .expand((references) => references)
        .toList(growable: false);
    final questionLabels = {
      for (final section in draft.checklist.sections)
        for (final item in section.items) item.id: item.label,
    };
    return Scaffold(
      appBar: AppPageHeader(
        title: 'Resumen de inspección',
        subtitle: draft.accountNumber,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SectionCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _row('Hidrante', draft.accountNumber),
                _row('Inspector', formatPersonName(state.user.fullName)),
                _row('Cuadrilla', state.user.brigadeName),
                _row(
                  'Checklist',
                  '${draft.checklist.title} v${draft.checklistVersion}',
                ),
                _row('Inicio', '${draft.createdAt.toLocal()}'),
                _row(
                  'Progreso',
                  '${draft.answers.length}/$totalQuestions respuestas',
                ),
                _row('GPS', draft.location == null ? 'Pendiente' : 'Capturado'),
                _row('Señal', draft.signal == null ? 'Pendiente' : 'Capturada'),
                _row('Fotografías', '${draft.photoCount} capturadas'),
                _row('Fotografías generales', '${draft.generalPhotos.length}'),
                _row(
                  'Observaciones generales',
                  draft.generalObservations?.trim().isNotEmpty == true
                      ? 'Capturadas'
                      : 'No agregadas',
                ),
                _row('Sincronización', draft.localStatus.name),
              ],
            ),
          ),
          if (draft.answers.isNotEmpty) ...[
            const SizedBox(height: 14),
            SectionCard(
              child: ExpansionTile(
                key: const ValueKey('historical-answer-summary'),
                tilePadding: EdgeInsets.zero,
                childrenPadding: EdgeInsets.zero,
                title: Text(
                  'RESPUESTAS REGISTRADAS (${draft.answers.length})',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                children: [
                  for (final answer in draft.answers.values)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        questionLabels[answer.questionId] ?? answer.questionId,
                      ),
                      subtitle: Text(_answerValue(answer)),
                    ),
                ],
              ),
            ),
          ],
          if (!draft.isInactive && photoReferences.isNotEmpty) ...[
            const SizedBox(height: 14),
            RvHistoricalPhotoSummary(references: photoReferences),
          ],
          if (draft.inactiveClosure case final closure?) ...[
            const SizedBox(height: 14),
            RvInactiveClosureSummary(closure: closure),
          ],
          if (!draft.isInactive && validation.issues.isNotEmpty) ...[
            const SizedBox(height: 14),
            SectionCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'PENDIENTES',
                    style: TextStyle(
                      color: AppColors.red,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  for (final issue in validation.issues)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(
                        Icons.error_outline,
                        color: AppColors.red,
                      ),
                      title: Text(issue.message),
                      onTap: () => context.pop(issue),
                    ),
                ],
              ),
            ),
          ],
          if (draft.parcelValveConfiguration case final config?) ...[
            const SizedBox(height: 14),
            SectionCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Válvulas parcelarias',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                  _row('Configuración', config.type.label),
                  for (final valve in config.valves) ...[
                    const Divider(),
                    Text(
                      'Válvula ${valve.index}',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    _row(
                      'Marca',
                      valve.valveBrand?['displayValue']?.toString() ??
                          'Pendiente',
                    ),
                    _row(
                      'Diámetro',
                      valve.diameter?['displayValue']?.toString() ??
                          'Pendiente',
                    ),
                    _row(
                      'Solenoide',
                      valve.hasSolenoid
                          ? 'Sí · ${valve.solenoidBrand?['displayValue'] ?? 'Pendiente'}'
                          : 'No',
                    ),
                    _row(
                      'Piloto',
                      valve.hasPilot
                          ? 'Sí · ${valve.pilotBrand?['displayValue'] ?? 'Pendiente'}'
                          : 'No',
                    ),
                    if (valve.hasPilot)
                      _row(
                        'Piloto conectado',
                        valve.pilotConnected == null
                            ? 'No capturado'
                            : valve.pilotConnected!
                            ? 'Sí'
                            : 'No',
                      ),
                    _row(
                      'Manómetro',
                      valve.hasPressureGauge
                          ? 'Sí · ${valve.pressureGaugeBrand?['displayValue'] ?? 'Pendiente'}'
                          : 'No',
                    ),
                  ],
                ],
              ),
            ),
          ],
          if (message != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                message!,
                style: const TextStyle(color: AppColors.red),
              ),
            ),
          const SizedBox(height: 16),
          if (!draft.isInactive &&
              state.canDeleteUnsyncedLocalDraft(draft.clientInspectionId)) ...[
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(foregroundColor: AppColors.red),
              onPressed: busy ? null : () => _deleteLocalDraft(state, draft),
              icon: const Icon(Icons.delete_outline),
              label: const Text('Archivar revisión local'),
            ),
            const SizedBox(height: 10),
          ],
          if (!draft.isInactive)
            AnimatedBuilder(
              animation: _sendingAnimation,
              builder: (context, child) => CustomPaint(
                foregroundPainter: busy
                    ? _SendingBorderPainter(_sendingAnimation.value)
                    : null,
                child: child,
              ),
              child: FilledButton.icon(
                onPressed: busy || draft.isReadOnly || !validation.isValid
                    ? null
                    : () => _confirmAndSubmit(context, state, draft),
                icon: busy
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.send_outlined),
                label: Text(
                  busy
                      ? 'Enviando...'
                      : draft.localStatus == RvLocalStatus.submitted
                      ? 'Inspección enviada'
                      : syncedValidation.isValid
                      ? 'Enviar inspección'
                      : 'Sincronizar y enviar',
                ),
              ),
            ),
          if (!draft.isInactive && validation.issues.isNotEmpty) ...[
            const SizedBox(height: 10),
            TextButton.icon(
              onPressed: busy
                  ? null
                  : () => context.go('/hydrants/${widget.hydrantId}'),
              icon: const Icon(Icons.schedule_outlined),
              label: const Text('Continuar después'),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _deleteLocalDraft(AppState state, RvDraft draft) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Archivar revisión local'),
        content: const Text(
          'La revisión dejará de mostrarse como activa. El documento, sus '
          'fotografías y evidencias se conservarán para recuperación y auditoría.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Archivar'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    _setBusy(true);
    try {
      await state.deleteUnsyncedLocalDraft(draft.clientInspectionId);
      if (mounted) context.go('/home');
    } on Object catch (error) {
      if (mounted)
        setState(() => message = '$error'.replaceFirst('Bad state: ', ''));
    } finally {
      if (mounted) _setBusy(false);
    }
  }

  Widget _row(String label, String value) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 120,
          child: Text(label, style: const TextStyle(color: AppColors.muted)),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
      ],
    ),
  );

  String _answerValue(RvAnswer answer) {
    if (answer.notApplicable) return 'No aplica';
    if (answer.selectedOptions.isNotEmpty) {
      return answer.selectedOptions.join(', ');
    }
    final value = answer.value;
    if (value == null || '$value'.trim().isEmpty) return 'Sin valor';
    return '$value';
  }

  Future<void> _confirmAndSubmit(
    BuildContext context,
    AppState state,
    RvDraft draft,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirmar envío'),
        content: const Text(
          '¿Confirmas el envío de la revisión visual?\n\n'
          'Después de enviarla no podrás modificarla, salvo mediante el '
          'procedimiento autorizado.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Enviar revisión'),
          ),
        ],
      ),
    );
    if (confirmed != true || busy) return;
    _setBusy(true);
    late final RvDraft result;
    try {
      final queued = draft.copyWith(
        localStatus: RvLocalStatus.submitPending,
        submitStatus: RvPartStatus.pending,
        remoteMutationAuthorization: RvDraft.technicianSubmitAuthorization,
        remoteMutationAuthorizedAt: DateTime.now().toUtc(),
        clearError: true,
        updatedAt: DateTime.now().toUtc(),
      );
      await state.rvDraftRepository.save(queued);
      result = await state.inspectionSyncCoordinator.synchronize(
        queued,
        submit: true,
      );
    } finally {
      if (mounted) _setBusy(false);
    }
    if (!mounted || !context.mounted) return;
    if (result.localStatus == RvLocalStatus.submitted ||
        result.localStatus == RvLocalStatus.conflict) {
      state.reconcileLocalWorkProjection();
      unawaited(state.synchronizeAssignments());
    }
    if (result.localStatus == RvLocalStatus.conflict) {
      await RvReviewNavigation.showConflictAndReturnHome(context);
      return;
    }
    if (_submissionGate.consumeIfComplete(result)) {
      await RvReviewNavigation.showSubmissionSuccessAndReturnHome(context);
      return;
    }
    setState(() {
      message =
          result.lastSyncError ??
          'No fue posible confirmar el envío. La revisión permanece '
              'guardada en el dispositivo.';
    });
  }
}

class RvHistoricalPhotoSummary extends StatefulWidget {
  const RvHistoricalPhotoSummary({
    required this.references,
    this.photoProjection,
    this.thumbnailBuilder,
    this.onOpenPhoto,
    super.key,
  });

  final List<RvPhotoReference> references;
  @visibleForTesting
  final InspectionPhotoDocumentProjection? photoProjection;
  @visibleForTesting
  final Widget Function(BuildContext, InspectionPhoto)? thumbnailBuilder;
  @visibleForTesting
  final ValueChanged<InspectionPhoto>? onOpenPhoto;

  @override
  State<RvHistoricalPhotoSummary> createState() =>
      _RvHistoricalPhotoSummaryState();
}

class _RvHistoricalPhotoSummaryState extends State<RvHistoricalPhotoSummary> {
  late final InspectionPhotoDocumentProjection _photos;
  InspectionPhotoProjectionBinding? _photoBinding;

  Iterable<String> get _photoIds =>
      widget.references.map((reference) => reference.photoId);

  @override
  void initState() {
    super.initState();
    _photos = widget.photoProjection ?? InspectionPhotoDocumentProjection();
    if (widget.photoProjection == null) {
      _photoBinding = InspectionPhotoProjectionBinding(
        projection: _photos,
        onChanged: _onPhotoChanged,
      )..retain(_photoIds);
    } else {
      _photos.retain(_photoIds);
    }
  }

  @override
  void didUpdateWidget(covariant RvHistoricalPhotoSummary oldWidget) {
    super.didUpdateWidget(oldWidget);
    _photoBinding?.retain(_photoIds);
    if (_photoBinding == null) _photos.retain(_photoIds);
  }

  void _onPhotoChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _photoBinding?.dispose();
    if (_photoBinding == null) _photos.clear();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SectionCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'FOTOGRAFÍAS DE EVIDENCIA (${widget.references.length})',
          key: const ValueKey('historical-photo-summary'),
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final reference in widget.references)
              _HistoricalPhotoTile(
                reference: reference,
                photo: _photos.photo(reference.photoId),
                thumbnailBuilder: widget.thumbnailBuilder,
                onOpenPhoto: widget.onOpenPhoto,
              ),
          ],
        ),
      ],
    ),
  );
}

class _HistoricalPhotoTile extends StatelessWidget {
  const _HistoricalPhotoTile({
    required this.reference,
    required this.photo,
    this.thumbnailBuilder,
    this.onOpenPhoto,
  });

  final RvPhotoReference reference;
  final InspectionPhoto? photo;
  final Widget Function(BuildContext, InspectionPhoto)? thumbnailBuilder;
  final ValueChanged<InspectionPhoto>? onOpenPhoto;

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Fotografía ${reference.slotCode}',
    button: photo != null,
    child: InkWell(
      key: ValueKey('historical-photo-${reference.photoId}'),
      onTap: photo == null
          ? null
          : () {
              if (onOpenPhoto case final callback?) {
                callback(photo!);
              } else {
                _showOriginal(context, photo!);
              }
            },
      child: SizedBox.square(
        dimension: 96,
        child: photo == null
            ? const DecoratedBox(
                decoration: BoxDecoration(color: Color(0xFFE5E7EB)),
                child: Icon(Icons.broken_image_outlined),
              )
            : thumbnailBuilder?.call(context, photo!) ??
                  Image.file(
                    File(photo!.thumbnailPath),
                    cacheWidth: evidenceThumbnailDecodePixels,
                    cacheHeight: evidenceThumbnailDecodePixels,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) =>
                        const Icon(Icons.broken_image_outlined),
                  ),
      ),
    ),
  );

  Future<void> _showOriginal(BuildContext context, InspectionPhoto selected) =>
      showDialog<void>(
        context: context,
        builder: (dialogContext) => Dialog.fullscreen(
          child: Scaffold(
            appBar: AppBar(
              title: const Text('Evidencia fotográfica'),
              leading: IconButton(
                tooltip: 'Cerrar',
                onPressed: () => Navigator.pop(dialogContext),
                icon: const Icon(Icons.close),
              ),
            ),
            body: InteractiveViewer(
              child: Center(
                child: Image.file(
                  File(selected.localPath),
                  cacheWidth: evidenceViewerDecodeWidth(dialogContext),
                  fit: BoxFit.contain,
                  errorBuilder: (_, _, _) => const Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      'El archivo original no está disponible. La referencia '
                      'local se conserva para diagnóstico y recuperación.',
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
}

class RvInactiveClosureSummary extends StatefulWidget {
  const RvInactiveClosureSummary({
    required this.closure,
    this.photoProjection,
    super.key,
  });

  final RvInactiveClosure closure;
  @visibleForTesting
  final InspectionPhotoDocumentProjection? photoProjection;

  @override
  State<RvInactiveClosureSummary> createState() =>
      _InactiveClosureSummaryState();
}

class _InactiveClosureSummaryState extends State<RvInactiveClosureSummary> {
  late final InspectionPhotoDocumentProjection _photos;
  late final InspectionPhotoProjectionBinding _photoBinding;

  @override
  void initState() {
    super.initState();
    _photos = widget.photoProjection ?? InspectionPhotoDocumentProjection();
    _photoBinding = InspectionPhotoProjectionBinding(
      projection: _photos,
      onChanged: _rebuildAfterPhotoDocumentChange,
    )..retain(widget.closure.photoIds);
  }

  @override
  void didUpdateWidget(covariant RvInactiveClosureSummary oldWidget) {
    super.didUpdateWidget(oldWidget);
    _photoBinding.retain(widget.closure.photoIds);
  }

  @override
  void dispose() {
    _photoBinding.dispose();
    super.dispose();
  }

  void _rebuildAfterPhotoDocumentChange() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) => SectionCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'INACTIVO · NO HAY HIDRANTE EN LA UBICACIÓN',
          key: ValueKey('inactive-summary-status'),
          style: TextStyle(
            fontWeight: FontWeight.w800,
            color: AppColors.orange,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          widget.closure.comment,
          key: const ValueKey('inactive-summary-comment'),
        ),
        const SizedBox(height: 8),
        Text(
          '${widget.closure.location.latitude.toStringAsFixed(7)}, '
          '${widget.closure.location.longitude.toStringAsFixed(7)}',
          key: const ValueKey('inactive-summary-location'),
        ),
        Text(
          'Coordenada capturada: '
          '${widget.closure.location.capturedAt.toLocal()}',
        ),
        Text('Cierre local: ${widget.closure.closedAt.toLocal()}'),
        Text('Técnico: ${widget.closure.closedByName}'),
        Text('Dispositivo: ${widget.closure.deviceId}'),
        const SizedBox(height: 8),
        const Text(
          'Pendiente de contrato de sincronización. No se enviará como una '
          'revisión normal ni cambiará el hidrante maestro.',
          key: ValueKey('inactive-summary-pending-contract'),
          style: TextStyle(color: AppColors.muted),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final id in widget.closure.photoIds)
              _InactiveSummaryPhoto(photoId: id, photo: _photos.photo(id)),
          ],
        ),
      ],
    ),
  );
}

class _InactiveSummaryPhoto extends StatelessWidget {
  const _InactiveSummaryPhoto({required this.photoId, required this.photo});

  final String photoId;
  final InspectionPhoto? photo;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    key: ValueKey('inactive-summary-photo-$photoId'),
    dimension: 96,
    child: photo == null
        ? const DecoratedBox(
            decoration: BoxDecoration(color: Color(0xFFE5E7EB)),
            child: Icon(Icons.broken_image_outlined),
          )
        : Image.file(
            key: ValueKey(
              'inactive-summary-thumbnail-${photo!.id}-${photo!.thumbnailPath}',
            ),
            File(photo!.thumbnailPath),
            cacheWidth: evidenceThumbnailDecodePixels,
            cacheHeight: evidenceThumbnailDecodePixels,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => const Icon(Icons.broken_image_outlined),
          ),
  );
}

class RvSummaryErrorView extends StatelessWidget {
  const RvSummaryErrorView({required this.hydrantId, super.key});

  final String hydrantId;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: const AppPageHeader(title: 'Resumen de inspección'),
    body: Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: SectionCard(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.error_outline,
                color: AppColors.orange,
                size: 48,
              ),
              const SizedBox(height: 14),
              const Text(
                'No fue posible mostrar esta revisión.',
                textAlign: TextAlign.center,
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              const Text(
                'La información local permanece guardada. Puedes volver o '
                'abrir la ficha del hidrante para intentarlo nuevamente.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.muted),
              ),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: () =>
                    context.canPop() ? context.pop() : context.go('/reviews'),
                icon: const Icon(Icons.arrow_back),
                label: const Text('Volver'),
              ),
              const SizedBox(height: 8),
              FilledButton.icon(
                onPressed: () => context.go('/hydrants/$hydrantId'),
                icon: const Icon(Icons.water_drop_outlined),
                label: const Text('Abrir desde Hidrantes'),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class RvSummaryFailureBoundary extends StatelessWidget {
  const RvSummaryFailureBoundary({
    required this.hydrantId,
    required this.clientInspectionId,
    required this.builder,
    super.key,
  });

  final String hydrantId, clientInspectionId;
  final WidgetBuilder builder;

  @override
  Widget build(BuildContext context) {
    try {
      return builder(context);
    } on Object catch (error, stackTrace) {
      FlutterError.reportError(
        FlutterErrorDetails(
          // Do not forward an arbitrary exception message: platform/file
          // errors can contain local paths or request details. The stack and
          // runtime type are sufficient to locate the failing code safely.
          exception: StateError('RV summary rendering failed'),
          stack: stackTrace,
          library: 'DDR001 RV summary',
          context: ErrorDescription('while opening a local RV summary'),
          informationCollector: () => [
            DiagnosticsProperty<String>(
              'errorType',
              error.runtimeType.toString(),
            ),
          ],
        ),
      );
      return RvSummaryErrorView(hydrantId: hydrantId);
    }
  }
}

class _SendingBorderPainter extends CustomPainter {
  const _SendingBorderPainter(this.progress);
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..addRRect(
        RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(20)),
      );
    final metric = path.computeMetrics().first;
    final start = metric.length * progress;
    final segment = metric.length * .28;
    final paint = Paint()
      ..color = Colors.lightBlueAccent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    final end = start + segment;
    canvas.drawPath(
      metric.extractPath(start, math.min(end, metric.length)),
      paint,
    );
    if (end > metric.length) {
      canvas.drawPath(metric.extractPath(0, end - metric.length), paint);
    }
  }

  @override
  bool shouldRepaint(_SendingBorderPainter oldDelegate) =>
      oldDelegate.progress != progress;
}

// ignore_for_file: curly_braces_in_flow_control_structures
