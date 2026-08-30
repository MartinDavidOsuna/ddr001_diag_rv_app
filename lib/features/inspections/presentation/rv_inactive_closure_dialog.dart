import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/media/image_decode_policy.dart';
import '../../../domain/media/inspection_photo.dart';
import '../domain/rv_draft.dart';
import 'inspection_photo_projection.dart';
import 'rv_inspection_controller.dart';

String? inactiveClosureCommentError(String? value) {
  final normalized = (value ?? '').trim();
  if (normalized.length < inactiveClosureCommentMinLength) {
    return 'Describe lo observado con al menos '
        '$inactiveClosureCommentMinLength caracteres.';
  }
  if (normalized.length > inactiveClosureCommentMaxLength) {
    return 'El comentario no puede exceder '
        '$inactiveClosureCommentMaxLength caracteres.';
  }
  return null;
}

Future<bool> showRvInactiveClosureDialog(
  BuildContext context,
  RvInspectionController controller,
) async =>
    await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => RvInactiveClosureDialog(controller: controller),
    ) ??
    false;

class RvInactiveClosureDialog extends StatefulWidget {
  const RvInactiveClosureDialog({
    required this.controller,
    this.photoProjection,
    this.onBuild,
    super.key,
  });

  final RvInspectionController controller;
  @visibleForTesting
  final InspectionPhotoDocumentProjection? photoProjection;
  @visibleForTesting
  final VoidCallback? onBuild;

  @override
  State<RvInactiveClosureDialog> createState() =>
      _RvInactiveClosureDialogState();
}

class _RvInactiveClosureDialogState extends State<RvInactiveClosureDialog> {
  final _formKey = GlobalKey<FormState>();
  final _comment = TextEditingController();
  late final InspectionPhotoDocumentProjection _previews;
  late final InspectionPhotoProjectionBinding _previewBinding;
  bool _closing = false;
  late String _viewSignature;

  @override
  void initState() {
    super.initState();
    _previews = widget.photoProjection ?? InspectionPhotoDocumentProjection();
    _previewBinding = InspectionPhotoProjectionBinding(
      projection: _previews,
      onChanged: _rebuildAfterPhotoDocumentChange,
    );
    _comment.text =
        widget.controller.draft?.inactiveClosureDraft?.comment ?? '';
    _retainCurrentPreviews();
    _viewSignature = _controllerViewSignature();
    widget.controller.addListener(_onControllerChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChanged);
    _previewBinding.dispose();
    _comment.dispose();
    super.dispose();
  }

  void _retainCurrentPreviews() {
    _previewBinding.retain(
      widget.controller.draft
              ?.photosFor(noHydrantAtLocationPhotoSlot)
              .map((reference) => reference.photoId) ??
          const <String>[],
    );
  }

  void _rebuildAfterPhotoDocumentChange() {
    if (mounted) setState(() {});
  }

  void _onControllerChanged() {
    final next = _controllerViewSignature();
    if (next == _viewSignature) return;
    _viewSignature = next;
    _retainCurrentPreviews();
    if (mounted) setState(() {});
  }

  String _controllerViewSignature() {
    final controller = widget.controller;
    final draft = controller.draft;
    final photoIds =
        draft
            ?.photosFor(noHydrantAtLocationPhotoSlot)
            .map((reference) => reference.photoId)
            .join('\u0000') ??
        '';
    return '${draft?.updatedAt.microsecondsSinceEpoch}|'
        '${draft?.location?.capturedAt.microsecondsSinceEpoch}|'
        '${draft?.isReadOnly}|$photoIds|${controller.busy}|'
        '${controller.processingPhoto}|${controller.message}|$_closing';
  }

  @override
  void didUpdateWidget(covariant RvInactiveClosureDialog oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, widget.controller)) {
      oldWidget.controller.removeListener(_onControllerChanged);
      widget.controller.addListener(_onControllerChanged);
      _comment.text =
          widget.controller.draft?.inactiveClosureDraft?.comment ?? '';
    }
    _retainCurrentPreviews();
    _viewSignature = _controllerViewSignature();
  }

  Future<void> _closeReview() async {
    if (_closing || _formKey.currentState?.validate() != true) return;
    setState(() => _closing = true);
    final closed = await widget.controller.closeAsInactive(_comment.text);
    if (!mounted) return;
    if (closed) {
      Navigator.pop(context, true);
    } else {
      setState(() => _closing = false);
    }
  }

  Future<void> _requestExit() async {
    if (_closing ||
        widget.controller.busy ||
        widget.controller.processingPhoto) {
      return;
    }
    final draft = widget.controller.draft!;
    final hasEvidence = draft
        .photosFor(noHydrantAtLocationPhotoSlot)
        .isNotEmpty;
    final hasUsefulComment = _comment.text.trim().isNotEmpty;
    if (!hasEvidence &&
        !hasUsefulComment &&
        draft.inactiveClosureDraft == null) {
      Navigator.pop(context, false);
      return;
    }
    final action = await showDialog<InactiveDraftExitAction>(
      context: context,
      builder: (_) => const InactiveDraftExitDialog(),
    );
    if (!mounted ||
        action == null ||
        action == InactiveDraftExitAction.continueEditing) {
      return;
    }
    setState(() => _closing = true);
    final completed = switch (action) {
      InactiveDraftExitAction.save =>
        await widget.controller.saveInactiveClosureDraft(_comment.text),
      InactiveDraftExitAction.discard =>
        await widget.controller.discardInactiveClosureDraft(),
      InactiveDraftExitAction.continueEditing => false,
    };
    if (!mounted) return;
    if (completed) {
      Navigator.pop(context, false);
    } else {
      setState(() => _closing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    widget.onBuild?.call();
    final draft = widget.controller.draft!;
    final location = draft.location;
    final references = draft.photosFor(noHydrantAtLocationPhotoSlot);
    final processing = widget.controller.processingPhoto;
    final blocked = widget.controller.busy || processing || _closing;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && !blocked) _requestExit();
      },
      child: AlertDialog(
        title: const Text('No hay hidrante en esta ubicación'),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const RepaintBoundary(
                    key: ValueKey('inactive-static-repaint-boundary'),
                    child: Text(
                      'Se conservarán la coordenada, el comentario y la '
                      'fotografía. La revisión quedará cerrada como Inactiva '
                      'y no se enviará como una revisión normal.',
                    ),
                  ),
                  const SizedBox(height: 16),
                  Semantics(
                    label: 'Coordenada capturada de solo lectura',
                    readOnly: true,
                    child: Text(
                      location == null
                          ? 'Coordenada no disponible'
                          : '${location.latitude.toStringAsFixed(7)}, '
                                '${location.longitude.toStringAsFixed(7)}\n'
                                'Precisión: '
                                '${location.horizontalAccuracy?.toStringAsFixed(1) ?? 'no disponible'} m\n'
                                'Capturada: ${location.capturedAt.toLocal()}',
                      key: const ValueKey('inactive-location-readonly'),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    key: const ValueKey('inactive-comment'),
                    controller: _comment,
                    enabled: !blocked,
                    minLines: 3,
                    maxLines: 5,
                    maxLength: inactiveClosureCommentMaxLength,
                    validator: inactiveClosureCommentError,
                    decoration: const InputDecoration(
                      labelText: 'Comentario obligatorio',
                      hintText: 'Describe lo observado en el sitio.',
                    ),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    key: const ValueKey('capture-inactive-photo'),
                    onPressed: blocked || draft.isReadOnly
                        ? null
                        : () => widget.controller.addInactiveEvidencePhoto(
                            ImageSource.camera,
                            comment: _comment.text,
                          ),
                    icon: processing
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.camera_alt_outlined),
                    label: Text(
                      processing
                          ? 'Procesando fotografía…'
                          : 'Tomar fotografía del lugar',
                    ),
                  ),
                  if (references.isEmpty)
                    const Padding(
                      padding: EdgeInsets.only(top: 8),
                      child: Text(
                        'Se requiere al menos una fotografía guardada.',
                        key: ValueKey('inactive-photo-required'),
                      ),
                    )
                  else ...[
                    const SizedBox(height: 12),
                    Text(
                      '${references.length} fotografía(s) guardada(s)',
                      key: const ValueKey('inactive-photo-count'),
                    ),
                    const SizedBox(height: 8),
                    RepaintBoundary(
                      key: const ValueKey('inactive-previews-repaint-boundary'),
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final reference in references)
                            _InactiveEvidencePreview(
                              photoId: reference.photoId,
                              photo: _previews.photo(reference.photoId),
                            ),
                        ],
                      ),
                    ),
                    const Padding(
                      padding: EdgeInsets.only(top: 8),
                      child: Text(
                        'Si sales ahora, podrás guardar el reporte para '
                        'continuarlo o descartarlo de forma segura.',
                      ),
                    ),
                  ],
                  if (widget.controller.message case final message?) ...[
                    const SizedBox(height: 10),
                    Text(message, key: const ValueKey('inactive-message')),
                  ],
                ],
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            key: const ValueKey('cancel-inactive-closure'),
            onPressed: blocked ? null : _requestExit,
            child: const Text('Cancelar'),
          ),
          FilledButton(
            key: const ValueKey('confirm-inactive-closure'),
            onPressed:
                blocked || location?.isValid != true || references.isEmpty
                ? null
                : _closeReview,
            child: const Text('Cerrar revisión como Inactiva'),
          ),
        ],
      ),
    );
  }
}

enum InactiveDraftExitAction { save, discard, continueEditing }

class InactiveDraftExitDialog extends StatelessWidget {
  const InactiveDraftExitDialog({super.key});

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('¿Qué deseas hacer con este reporte?'),
    content: const Text(
      'Se retirará únicamente la evidencia tomada para este reporte de “No '
      'hay hidrante”. Las demás respuestas y fotografías de la revisión no '
      'cambiarán si eliges descartarlo.',
      key: ValueKey('inactive-discard-warning'),
    ),
    actions: [
      TextButton(
        key: const ValueKey('continue-editing-inactive-draft'),
        onPressed: () =>
            Navigator.pop(context, InactiveDraftExitAction.continueEditing),
        child: const Text('Seguir editando'),
      ),
      OutlinedButton(
        key: const ValueKey('discard-inactive-draft'),
        onPressed: () =>
            Navigator.pop(context, InactiveDraftExitAction.discard),
        child: const Text('Descartar este reporte'),
      ),
      FilledButton(
        key: const ValueKey('save-inactive-draft'),
        onPressed: () => Navigator.pop(context, InactiveDraftExitAction.save),
        child: const Text('Guardar para continuar después'),
      ),
    ],
  );
}

Future<bool> confirmDiscardInactiveClosureDraft(BuildContext context) async =>
    await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Descartar reporte pendiente'),
        content: const Text(
          'Se retirará únicamente la evidencia tomada para este reporte de '
          '“No hay hidrante”. Las demás respuestas y fotografías de la '
          'revisión no cambiarán.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Conservar reporte'),
          ),
          FilledButton(
            key: const ValueKey('confirm-discard-inactive-draft'),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Descartar este reporte'),
          ),
        ],
      ),
    ) ??
    false;

class _InactiveEvidencePreview extends StatelessWidget {
  const _InactiveEvidencePreview({required this.photoId, required this.photo});

  final String photoId;
  final InspectionPhoto? photo;

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Vista previa de evidencia del lugar',
    image: true,
    child: SizedBox.square(
      key: ValueKey('inactive-preview-$photoId'),
      dimension: 88,
      child: photo == null
          ? const DecoratedBox(
              decoration: BoxDecoration(color: Color(0xFFE5E7EB)),
              child: Icon(Icons.broken_image_outlined),
            )
          : Image.file(
              File(photo!.thumbnailPath),
              cacheWidth: evidenceThumbnailDecodePixels,
              cacheHeight: evidenceThumbnailDecodePixels,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) =>
                  const Icon(Icons.broken_image_outlined),
            ),
    ),
  );
}
