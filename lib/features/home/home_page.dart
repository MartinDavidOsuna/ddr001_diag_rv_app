import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../app/theme/app_theme.dart';
import '../../core/constants/report_type_labels.dart';
import '../../core/services/app_state.dart';
import '../../core/widgets/common_widgets.dart';
import '../../domain/enums/hydrant_list_filter.dart';

class _HomeAlert {
  const _HomeAlert({
    required this.title,
    required this.description,
    required this.date,
    required this.severity,
    required this.origin,
    required this.recommendedAction,
    this.hydrantId,
  });

  final String title, description, severity, origin, recommendedAction;
  final DateTime date;
  final String? hydrantId;
}

class HomePage extends StatelessWidget {
  const HomePage({super.key});
  static final _returnedAlert = _HomeAlert(
    title: '1 registro devuelto',
    description: 'El registro requiere corrección antes de sincronizarse.',
    date: DateTime(2026, 7, 14, 9, 30),
    severity: 'Alta',
    origin: 'Revisión de supervisión',
    recommendedAction: 'Revisar las observaciones y corregir el registro.',
    hydrantId: '712',
  );
  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final date = DateFormat(
      "EEEE, d 'de' MMMM 'de' y",
      'es',
    ).format(DateTime.now());
    return Scaffold(
      appBar: AppPageHeader(
        title: 'DIAGNOSTICO HIDRANTES',
        subtitle: 'Distrito de Riego 001',
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: ConnectionBadge(online: state.online),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              'Buenas tardes, ${state.user.fullName.split(' ').first}',
              style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 5),
            Text(
              '${state.user.brigadeName} · Ruta Norte - Pabellón de Arteaga',
              style: const TextStyle(color: AppColors.muted),
            ),
            Text(
              date,
              style: const TextStyle(color: AppColors.muted, fontSize: 12),
            ),
            const SizedBox(height: 16),
            Semantics(
              button: true,
              label: 'Abrir alerta: ${_returnedAlert.title}',
              child: Card(
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: () => _openAlert(context, state, _returnedAlert),
                  child: const Padding(
                    padding: EdgeInsets.all(16),
                    child: Row(
                      children: [
                        CircleAvatar(
                          backgroundColor: Color(0xFFFFE6E6),
                          child: Icon(
                            Icons.warning_amber_rounded,
                            color: AppColors.red,
                          ),
                        ),
                        SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '1 registro devuelto',
                                style: TextStyle(
                                  color: Color(0xFFB91C1C),
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              Text(
                                'Requiere corrección',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: AppColors.red,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Icon(Icons.chevron_right, color: AppColors.red),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            SectionCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'CONTINUAR INSPECCIÓN',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.teal,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'DDR001-HID-0002',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                  ),
                  const Text(
                    'Rincón de Romos',
                    style: TextStyle(color: AppColors.muted),
                  ),
                  const SizedBox(height: 9),
                  const StatusBadge(
                    '${ReportTypeLabels.visualShort} · En proceso',
                    color: AppColors.teal,
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.teal,
                    ),
                    onPressed: () {
                      state.trace(
                        'continue_inspection',
                        'Continuar ${ReportTypeLabels.visualFull}',
                        hydrantId: '2',
                      );
                      context.push('/hydrants/2/inspection/a');
                    },
                    icon: const Icon(Icons.arrow_forward),
                    label: const Text('Continuar'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            SectionCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'RESUMEN DE JORNADA',
                    style: TextStyle(fontSize: 12, color: AppColors.muted),
                  ),
                  SizedBox(height: 18),
                  Row(
                    children: [
                      Metric(
                        value:
                            '${state.hydrantCountForFilter(HydrantListFilter.all)}',
                        label: 'Asignados',
                        onTap: () =>
                            _openFilter(context, state, HydrantListFilter.all),
                      ),
                      Metric(
                        value:
                            '${state.hydrantCountForFilter(HydrantListFilter.completed)}',
                        label: 'Terminados',
                        color: AppColors.green,
                        onTap: () => _openFilter(
                          context,
                          state,
                          HydrantListFilter.completed,
                        ),
                      ),
                      Metric(
                        value:
                            '${state.hydrantCountForFilter(HydrantListFilter.inProgress)}',
                        label: 'En proceso',
                        color: AppColors.teal,
                        onTap: () => _openFilter(
                          context,
                          state,
                          HydrantListFilter.inProgress,
                        ),
                      ),
                      Metric(
                        value:
                            '${state.hydrantCountForFilter(HydrantListFilter.synchronizationPending)}',
                        label: 'Sin sinc.',
                        color: AppColors.orange,
                        onTap: () => _openFilter(
                          context,
                          state,
                          HydrantListFilter.synchronizationPending,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () => context.go('/hydrants'),
                    icon: const Icon(Icons.assignment_outlined),
                    label: const Text('Ver hidrantes'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => context.push('/sync'),
                    icon: const Icon(Icons.sync),
                    label: const Text('Sincronizar'),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(48, 52),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _openFilter(
    BuildContext context,
    AppState state,
    HydrantListFilter filter,
  ) {
    state.requestHydrantListFilterFromHome(filter);
    context.go('/hydrants');
  }

  Future<void> _openAlert(
    BuildContext context,
    AppState state,
    _HomeAlert alert,
  ) async {
    final hydrantId = alert.hydrantId;
    if (hydrantId != null) {
      final exists = state.hydrants.any((item) => item.id == hydrantId);
      if (!exists) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('El hidrante ya no está disponible localmente.'),
          ),
        );
        return;
      }
      state.requestHydrantListFilterFromHome(HydrantListFilter.all);
      context.go('/hydrants/$hydrantId');
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(alert.title, style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 12),
              Text(alert.description),
              const SizedBox(height: 16),
              _AlertDetail(
                label: 'Fecha',
                value: DateFormat('dd/MM/yyyy HH:mm').format(alert.date),
              ),
              _AlertDetail(label: 'Severidad', value: alert.severity),
              _AlertDetail(label: 'Origen', value: alert.origin),
              _AlertDetail(
                label: 'Acción recomendada',
                value: alert.recommendedAction,
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => Navigator.pop(sheetContext),
                  child: const Text('Cerrar'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AlertDetail extends StatelessWidget {
  const _AlertDetail({required this.label, required this.value});
  final String label, value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 128,
          child: Text(
            label,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
        Expanded(child: Text(value)),
      ],
    ),
  );
}
