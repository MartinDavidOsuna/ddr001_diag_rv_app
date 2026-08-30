import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../app/theme/app_theme.dart';
import '../../core/services/app_state.dart';
import '../../core/widgets/common_widgets.dart';
import '../inspections/domain/rv_draft.dart';
import 'rv_work_dashboard.dart';

class AllReviewsPage extends StatelessWidget {
  const AllReviewsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final drafts = RvWorkDashboardProjection.allReviews(
      state.rvDraftRepository.all(),
    );
    final visibleHydrantIds = state.hydrants.map((item) => item.id).toSet();

    return Scaffold(
      appBar: const AppPageHeader(
        title: 'Todas mis revisiones',
        subtitle: 'Historial local completo',
      ),
      body: AllReviewsList(
        drafts: drafts,
        visibleHydrantIds: visibleHydrantIds,
        onOpen: (draft) => context.push(historyReviewLocation(draft)),
      ),
    );
  }
}

String historyReviewLocation(RvDraft draft) =>
    '/reviews/${Uri.encodeComponent(draft.clientInspectionId)}';

class AllReviewsList extends StatelessWidget {
  const AllReviewsList({
    required this.drafts,
    required this.visibleHydrantIds,
    this.onOpen,
    super.key,
  });

  final List<RvDraft> drafts;
  final Set<String> visibleHydrantIds;
  final ValueChanged<RvDraft>? onOpen;

  @override
  Widget build(BuildContext context) {
    if (drafts.isEmpty) {
      return const Center(child: Text('No hay revisiones guardadas.'));
    }
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: drafts.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final draft = drafts[index];
        final canOpen = visibleHydrantIds.contains(draft.hydrantId);
        return Card(
          key: ValueKey('review-${draft.clientInspectionId}'),
          child: ListTile(
            leading: Icon(
              draft.isReadOnly ? Icons.history : Icons.assignment_outlined,
              color: draft.lastSyncError == null
                  ? AppColors.blue
                  : AppColors.orange,
            ),
            title: Text('Cuenta ${draft.accountNumber}'),
            subtitle: Text(
              '${_statusLabel(draft)}\n'
              'Revisión ${_shortId(draft.clientInspectionId)}'
              '${canOpen ? '' : ' · fuera del catálogo actual'}',
            ),
            isThreeLine: true,
            trailing: onOpen != null
                ? const Icon(Icons.chevron_right)
                : const Icon(Icons.lock_outline),
            onTap: onOpen != null ? () => onOpen!(draft) : null,
          ),
        );
      },
    );
  }

  static String _shortId(String value) =>
      value.length <= 8 ? value : value.substring(0, 8);

  static String _statusLabel(RvDraft draft) {
    if (draft.isInactive) {
      return draft.inactiveClosure?.syncStatus ==
              RvInactiveClosureSyncStatus.remoteVerified
          ? 'Inactivo · confirmado remotamente'
          : 'Inactivo · pendiente de contrato de sincronización';
    }
    if (draft.lastSyncError != null) {
      return 'Requiere atención · evidencia local';
    }
    if (draft.isReadOnly) return 'Historial · solo lectura';
    final remote = draft.remoteStatus.trim();
    if (remote.isNotEmpty) return 'Remoto: $remote';
    return 'Local: ${draft.localStatus.name}';
  }
}
