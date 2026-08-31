import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../app/theme/app_theme.dart';
import '../../core/services/app_state.dart';
import '../../core/widgets/common_widgets.dart';
import '../../domain/enums/app_enums.dart';
import 'rv_work_dashboard.dart';
import 'rv_work_group_presentation.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final drafts = state.rvDraftRepository.all();
    final grouped = RvWorkDashboardProjection.byHydrant(
      drafts: drafts,
      hydrants: state.hydrants,
    );
    final recent = RvWorkDashboardProjection.recent(
      drafts: drafts,
      hydrants: state.hydrants,
    );
    return Scaffold(
      appBar: AppPageHeader(
        title: 'DIAGNOSTICO HIDRANTES',
        subtitle: 'Revisión visual',
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
          Text(
            'Hola, ${state.user.fullName}',
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
          ),
          Text(
            state.user.brigadeName.isEmpty
                ? 'Inspector de campo'
                : state.user.brigadeName,
            style: const TextStyle(color: AppColors.muted),
          ),
          const SizedBox(height: 18),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(60),
              textStyle: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w800,
              ),
            ),
            onPressed: () => context.push('/hydrants/new'),
            icon: const Icon(Icons.add_circle_outline),
            label: const Text('Nueva revisión visual'),
          ),
          const SizedBox(height: 18),
          const Text(
            'MI TRABAJO',
            style: TextStyle(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 10),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: RvWorkGroup.values.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
              mainAxisExtent: 82,
            ),
            itemBuilder: (context, index) {
              final group = RvWorkGroup.values[index];
              return _Count(
                key: ValueKey('dashboard-${group.name}'),
                label: group.label,
                value: grouped[group]!.length,
                color: group.color,
                onTap: () => context.go('/hydrants?workGroup=${group.name}'),
              );
            },
          ),
          const SizedBox(height: 18),
          OutlinedButton.icon(
            onPressed: () => context.push('/reviews'),
            icon: const Icon(Icons.history),
            label: const Text('Todas mis revisiones'),
          ),
          OutlinedButton.icon(
            onPressed: () => context.push('/sync'),
            icon: const Icon(Icons.sync),
            label: const Text('Sincronización'),
          ),
          const SizedBox(height: 18),
          const Text(
            'REVISIONES RECIENTES',
            style: TextStyle(fontWeight: FontWeight.w800),
          ),
          if (recent.isEmpty)
            const SectionCard(
              child: Text('Todavía no has creado revisiones visuales.'),
            ),
          for (final hydrant in recent)
            Card(
              child: ListTile(
                leading: const Icon(Icons.assignment_outlined),
                title: Text('Cuenta ${hydrant.code}'),
                subtitle: Text(
                  '${_status(hydrant.f02a.status)} · ${hydrant.lastStatusChangedAt?.toLocal().toString().substring(0, 16) ?? 'Sin fecha remota'}',
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push('/hydrants/${hydrant.id}'),
              ),
            ),
        ],
      ),
    );
  }

  static String _status(InspectionStatus status) => switch (status) {
    InspectionStatus.completed => 'Terminada',
    InspectionStatus.inProgress => 'Borrador o en proceso',
    _ => 'Pendiente',
  };
}

class _Count extends StatelessWidget {
  const _Count({
    super.key,
    required this.label,
    required this.value,
    required this.color,
    required this.onTap,
  });
  final String label;
  final int value;
  final Color color;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(12),
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                '$value',
                maxLines: 1,
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                  color: color,
                ),
              ),
            ),
          ),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(label, maxLines: 1, softWrap: false),
          ),
        ],
      ),
    ),
  );
}
