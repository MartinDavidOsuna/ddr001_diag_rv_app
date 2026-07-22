import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../app/theme/app_theme.dart';
import '../../../core/services/app_state.dart';
import '../../../core/widgets/common_widgets.dart';
import '../domain/rv_sync_state.dart';
import '../domain/rv_validator.dart';

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

class _RvSummaryPageState extends State<RvSummaryPage> {
  bool busy = false;
  String? message;

  @override
  Widget build(BuildContext context) {
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
                _row('Inspector', state.user.fullName),
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
                _row('Fotografías', '${draft.photos.length}/7'),
                _row('Sincronización', draft.localStatus.name),
              ],
            ),
          ),
          if (validation.issues.isNotEmpty) ...[
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
                      onTap: () => context.pop(),
                    ),
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
          FilledButton.icon(
            onPressed: busy || draft.isReadOnly || !validation.isValid
                ? null
                : () async {
                    setState(() => busy = true);
                    final result = await state.inspectionSyncCoordinator
                        .synchronize(draft, submit: true);
                    if (!mounted) return;
                    setState(() {
                      busy = false;
                      message = result.lastSyncError;
                    });
                  },
            icon: const Icon(Icons.send_outlined),
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
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: busy || draft.isReadOnly
                ? null
                : () => _cancel(context, state),
            icon: const Icon(Icons.cancel_outlined),
            label: const Text('Cancelar inspección'),
          ),
        ],
      ),
    );
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

  Future<void> _cancel(BuildContext context, AppState state) async {
    final reason = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cancelar inspección'),
        content: TextField(
          controller: reason,
          minLines: 2,
          maxLines: 4,
          decoration: const InputDecoration(
            labelText: 'Motivo',
            hintText: 'Mínimo 3 caracteres',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Volver'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Cancelar inspección'),
          ),
        ],
      ),
    );
    if (confirmed != true || reason.text.trim().length < 3) return;
    setState(() => busy = true);
    await state.inspectionSyncCoordinator.cancel(
      state.rvDraftRepository.find(widget.clientInspectionId)!,
      reason.text,
    );
    if (mounted) setState(() => busy = false);
  }
}

// ignore_for_file: curly_braces_in_flow_control_structures
