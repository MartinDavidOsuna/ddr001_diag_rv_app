import 'dart:math';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hive_ce/hive.dart';
import 'package:provider/provider.dart';

import '../../core/services/app_state.dart';
import '../../core/location/location_service.dart';
import '../../core/widgets/common_widgets.dart';
import '../../data/catalogs/f02a_catalogs.dart';
import '../../domain/enums/app_enums.dart';
import '../../domain/inspections/inspection_entities.dart';
import '../../domain/models/app_models.dart';
import '../../domain/functional/functional_models.dart';
import '../../core/constants/report_type_labels.dart';
import '../../data/local/operation_journal_repository.dart';
import '../../data/local/work_creation_coordinator.dart';

class NewSurveyPage extends StatefulWidget {
  const NewSurveyPage({super.key});
  @override
  State<NewSurveyPage> createState() => _NewSurveyPageState();
}

class _NewSurveyPageState extends State<NewSurveyPage> {
  String query = '';
  String? reason = F02aCatalogs.unassignedReasons.isEmpty
      ? null
      : F02aCatalogs.unassignedReasons.first;
  WorkSelection workSelection = WorkSelection.visualOnly;
  bool treatExistingAsUnassigned = false;
  final authorizationController = TextEditingController();
  @override
  void dispose() {
    authorizationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final matches = state.hydrants
        .where(
          (h) =>
              h.code.toLowerCase().contains(query.toLowerCase()) ||
              h.locality.toLowerCase().contains(query.toLowerCase()) ||
              h.parcel.toLowerCase().contains(query.toLowerCase()),
        )
        .take(5);
    return Scaffold(
      appBar: const AppPageHeader(title: 'Nuevo levantamiento'),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'Tipo de trabajo',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          SegmentedButton<WorkSelection>(
            segments: const [
              ButtonSegment(
                value: WorkSelection.visualOnly,
                label: Text(ReportTypeLabels.visualShort),
              ),
              ButtonSegment(
                value: WorkSelection.functionalOnly,
                label: Text(ReportTypeLabels.functionalShort),
              ),
              ButtonSegment(
                value: WorkSelection.visualAndFunctional,
                label: Text(ReportTypeLabels.combinedShort),
              ),
            ],
            selected: {workSelection},
            onSelectionChanged: (value) =>
                setState(() => workSelection = value.first),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: authorizationController,
            maxLines: 2,
            decoration: const InputDecoration(
              labelText: 'Autorización local o justificación',
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'Buscar hidrante existente',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: treatExistingAsUnassigned,
            title: const Text('Trabajo fuera de asignación'),
            subtitle: const Text(
              'Actívalo solo si el hidrante no está asignado formalmente.',
            ),
            onChanged: (value) =>
                setState(() => treatExistingAsUnassigned = value),
          ),
          const SizedBox(height: 10),
          TextField(
            onChanged: (v) => setState(() => query = v),
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              hintText: 'Código, localidad, municipio o parcela',
            ),
          ),
          const SizedBox(height: 10),
          if (F02aCatalogs.unassignedReasons.isNotEmpty)
            DropdownButtonFormField<String>(
              initialValue: reason,
              items: F02aCatalogs.unassignedReasons
                  .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                  .toList(),
              onChanged: (v) => setState(() => reason = v),
              decoration: const InputDecoration(labelText: 'Motivo'),
            ),
          if (state.hydrants.isEmpty)
            SectionCard(
              child: Column(
                children: [
                  const Text(
                    'No hay hidrantes disponibles en el catálogo local.',
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: () => context.push('/sync?return=/hydrants/new'),
                    icon: const Icon(Icons.sync),
                    label: const Text('Sincronizar asignaciones'),
                  ),
                  TextButton(
                    onPressed: () => context.pop(),
                    child: const Text('Volver'),
                  ),
                ],
              ),
            ),
          ...matches.map(
            (h) => ListTile(
              title: Text(h.code),
              subtitle: Text('${h.locality} · ${h.parcel}'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () async {
                final selectedSource = treatExistingAsUnassigned
                    ? HydrantSource.unassigned
                    : h.source;
                if (treatExistingAsUnassigned) {
                  state.markHydrantUnassigned(h.id);
                  final now = DateTime.now().toUtc();
                  final localRecord = LocalHydrantRecord(
                    id: h.id,
                    code: h.code,
                    source: HydrantSource.unassigned.name,
                    pendingValidation: false,
                    createdBy: state.user.id,
                    brigadeId: state.user.brigadeId,
                    deviceId: state.user.deviceId,
                    createdAt: now,
                    reason: reason ?? 'Sin motivo catalogado',
                    workSelection: workSelection.name,
                    authorizationReason: authorizationController.text.trim(),
                    pendingSupervisorValidation: true,
                    latitude: h.latitude,
                    longitude: h.longitude,
                  );
                  await Hive.box<String>(
                    'local_hydrants_v1',
                  ).put(h.id, jsonEncode(localRecord.toJson()));
                  await state.enqueueSync(
                    entityType: 'localHydrant',
                    entityId: h.id,
                    hydrantId: h.id,
                  );
                  await state.trace(
                    'unassigned_hydrant_selected',
                    'Hidrante no asignado: ${reason ?? 'Sin motivo catalogado'}',
                    hydrantId: h.id,
                  );
                }
                await _startSelectedWork(
                  state,
                  state.hydrant(h.id),
                  source: selectedSource,
                );
              },
            ),
          ),
          const SizedBox(height: 24),
          SectionCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Hidrante encontrado en campo',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
                const Text(
                  'Genera un código provisional, queda pendiente de validación y permite configuración desde cero.',
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: () => _createFieldHydrant(state),
                  icon: const Icon(Icons.add_location_alt),
                  label: const Text('Registrar encontrado en campo'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          const SectionCard(
            child: Text(
              'Configuración desde cero: salidas, válvulas, medidores, reductoras, filtros, solenoides, gabinete, controlador, energía, módem y antena se guardarán como componentes observados.',
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _createFieldHydrant(AppState state) async {
    if (workSelection != WorkSelection.visualOnly &&
        authorizationController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Captura la autorización local o justificación para REPORTE FUNCIONAL.',
          ),
        ),
      );
      return;
    }
    double latitude;
    double longitude;
    try {
      final position = await LocationService().capture();
      latitude = position.latitude;
      longitude = position.longitude;
    } on Object catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'No fue posible registrar el hidrante sin ubicación: $error',
            ),
          ),
        );
      }
      return;
    }
    final now = DateTime.now().toUtc();
    String code;
    do {
      final suffix = Random.secure().nextInt(10000).toString().padLeft(4, '0');
      code =
          'TMP-DDR001-${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}-$suffix';
    } while (state.hydrants.any((item) => item.code == code));
    final record = LocalHydrantRecord(
      id: code,
      code: code,
      source: HydrantSource.fieldCreated.name,
      pendingValidation: true,
      createdBy: state.user.id,
      brigadeId: state.user.brigadeId,
      deviceId: state.user.deviceId,
      createdAt: now,
      reason: reason ?? 'Sin motivo catalogado',
      workSelection: workSelection.name,
      authorizationReason: authorizationController.text.trim(),
      pendingSupervisorValidation: workSelection != WorkSelection.visualOnly,
      latitude: latitude,
      longitude: longitude,
    );
    await Hive.box<String>(
      'local_hydrants_v1',
    ).put(code, jsonEncode(record.toJson()));
    state.addFieldHydrant(
      Hydrant(
        id: code,
        code: code,
        locality: 'Por confirmar',
        parcel: 'Por confirmar',
        priority: PriorityLevel.high,
        access: AccessType.walking,
        syncStatus: SyncStatus.local,
        f02a: const InspectionSummary(
          type: InspectionType.f02A,
          status: InspectionStatus.pending,
          progress: 0,
        ),
        f02b: InspectionSummary(
          type: InspectionType.f02B,
          status: workSelection == WorkSelection.visualOnly
              ? InspectionStatus.notRequired
              : InspectionStatus.pending,
          progress: 0,
        ),
        latitude: latitude,
        longitude: longitude,
        source: HydrantSource.fieldCreated,
      ),
    );
    await state.trace(
      'field_hydrant_created',
      'Hidrante provisional $code',
      hydrantId: code,
    );
    final hydrant = state.hydrant(code);
    await _startSelectedWork(
      state,
      hydrant,
      source: HydrantSource.fieldCreated,
    );
  }

  Future<void> _startSelectedWork(
    AppState state,
    Hydrant hydrant, {
    required HydrantSource source,
  }) async {
    if (workSelection != WorkSelection.visualOnly &&
        authorizationController.text.trim().isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Captura la autorización local o justificación para REPORTE FUNCIONAL.',
            ),
          ),
        );
      }
      return;
    }
    try {
      if (workSelection != WorkSelection.visualOnly) {
        final now = DateTime.now().toUtc();
        await state.functionalEligibilityRepository.save(
          FunctionalReportEligibility(
            hydrantId: hydrant.id,
            allowed: true,
            source: FunctionalEligibilitySource.selectedInNewSurvey,
            reason: reason ?? 'Nuevo levantamiento',
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
          entityId: hydrant.id,
          hydrantId: hydrant.id,
        );
        await state.trace(
          'functional_eligibility_created',
          'Habilitación RF local pendiente de validación: ${authorizationController.text.trim()}',
          hydrantId: hydrant.id,
        );
      }
      if (workSelection == WorkSelection.visualAndFunctional) {
        final result = await WorkCreationCoordinator(
          visual: state.visualInspectionRepository,
          functional: state.functionalInspectionRepository,
          journal: OperationJournalRepository(
            Hive.box<String>('operation_journal_v1'),
          ),
        ).createVisualAndFunctional(hydrant: hydrant, user: state.user);
        if (result.status != WorkCreationStatus.committed) {
          throw StateError(
            result.status == WorkCreationStatus.needsRecovery
                ? 'La operación quedó pendiente de recuperación.'
                : result.error ?? 'No fue posible crear ambos trabajos.',
          );
        }
      } else if (workSelection == WorkSelection.visualOnly) {
        await state.visualInspectionRepository.openOrCreate(
          hydrant,
          state.user,
        );
      } else {
        await state.functionalInspectionRepository.openOrCreate(
          hydrant,
          state.user,
        );
      }
      await state.trace(
        'survey_work_selected',
        'Tipo de trabajo: ${workSelection.name}; fuente: ${source.name}',
        hydrantId: hydrant.id,
      );
    } catch (error) {
      await state.trace(
        'survey_work_creation_failed',
        'Creación recuperable incompleta: $error',
        hydrantId: hydrant.id,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'No se crearon todos los trabajos. La operación quedó registrada para recuperación: $error',
            ),
          ),
        );
      }
      return;
    }
    if (!mounted) return;
    var routeType = workSelection == WorkSelection.functionalOnly ? 'b' : 'a';
    if (workSelection == WorkSelection.visualAndFunctional) {
      routeType =
          await showDialog<String>(
            context: context,
            builder: (c) => AlertDialog(
              title: const Text('Elegir reporte inicial'),
              content: const Text(
                'Ambos trabajos quedaron creados con IDs y estados independientes.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(c, 'a'),
                  child: const Text('Iniciar REPORTE VISUAL'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(c, 'b'),
                  child: const Text('Iniciar REPORTE FUNCIONAL'),
                ),
              ],
            ),
          ) ??
          'a';
    }
    if (mounted) context.push('/hydrants/${hydrant.id}/inspection/$routeType');
  }
}
