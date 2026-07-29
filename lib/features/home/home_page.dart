import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../app/theme/app_theme.dart';
import '../../core/services/app_state.dart';
import '../../core/widgets/common_widgets.dart';
import '../../domain/enums/app_enums.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final drafts = state.rvDraftRepository.pending();
    final submitted = state.hydrants
        .where((item) => item.f02a.status == InspectionStatus.completed)
        .length;
    final inProgress = state.hydrants
        .where((item) => item.f02a.status == InspectionStatus.inProgress)
        .length;
    return Scaffold(
      appBar: AppPageHeader(
        title: 'DIAGNOSTICO HIDRANTES',
        subtitle: 'Revisión visual',
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
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _Count(
                label: 'Borradores',
                value: drafts.length,
                color: AppColors.blue,
              ),
              _Count(
                label: 'En proceso',
                value: inProgress,
                color: AppColors.teal,
              ),
              _Count(
                label: 'Enviadas',
                value: submitted,
                color: AppColors.green,
              ),
              _Count(
                label: 'Con error',
                value: state.syncErrors,
                color: AppColors.red,
              ),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => context.go('/hydrants'),
                  icon: const Icon(Icons.water_drop_outlined),
                  label: const Text('Mis hidrantes'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => context.go('/map'),
                  icon: const Icon(Icons.map_outlined),
                  label: const Text('Mapa general'),
                ),
              ),
            ],
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
          if (state.hydrants.isEmpty)
            const SectionCard(
              child: Text('Todavía no has creado revisiones visuales.'),
            ),
          for (final hydrant in state.hydrants.take(5))
            Card(
              child: ListTile(
                leading: const Icon(Icons.assignment_outlined),
                title: Text('Cuenta ${hydrant.code}'),
                subtitle: Text(
                  '${hydrant.locality} · ${_status(hydrant.f02a.status)}',
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
  const _Count({required this.label, required this.value, required this.color});
  final String label;
  final int value;
  final Color color;
  @override
  Widget build(BuildContext context) => Container(
    width: 150,
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: color.withValues(alpha: .1),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '$value',
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w900,
            color: color,
          ),
        ),
        Text(label),
      ],
    ),
  );
}
