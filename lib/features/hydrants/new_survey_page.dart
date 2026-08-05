import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../app/theme/app_theme.dart';
import '../../core/services/app_state.dart';
import '../../core/widgets/common_widgets.dart';
import '../../domain/enums/app_enums.dart';
import '../../domain/models/app_models.dart';
import 'new_survey_route.dart';

class NewSurveyPage extends StatefulWidget {
  const NewSurveyPage({super.key, this.selectedHydrantId});

  final String? selectedHydrantId;

  @override
  State<NewSurveyPage> createState() => _NewSurveyPageState();
}

class _NewSurveyPageState extends State<NewSurveyPage> {
  String query = '';
  String? startingId;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final normalized = query.trim().toLowerCase();
    final localIds = state.hydrants
        .where((hydrant) => hydrant.syncStatus != SyncStatus.synced)
        .map((hydrant) => hydrant.id)
        .toSet();
    final filtered = state.catalogHydrants
        .where(
          (hydrant) => hydrantVisibleForNewRv(
            hydrant,
            normalizedQuery: normalized,
            hasLocalWork: localIds.contains(hydrant.id),
          ),
        )
        .toList();
    final matches = prioritizeSelectedHydrant(
      filtered,
      widget.selectedHydrantId,
    ).take(100).toList();
    final selectedFromMap = containsSelectedHydrant(
      state.catalogHydrants,
      widget.selectedHydrantId,
    );
    return Scaffold(
      appBar: const AppPageHeader(
        title: 'Nueva revisión visual',
        subtitle: 'Selecciona un hidrante del catálogo general',
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            autofocus: true,
            onChanged: (value) => setState(() => query = value),
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              labelText: 'Número de cuenta, localidad o municipio',
              helperText: 'La búsqueda admite cuenta exacta o parcial.',
            ),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: () => context.go('/map'),
            icon: const Icon(Icons.map_outlined),
            label: const Text('Seleccionar desde el mapa'),
          ),
          const SizedBox(height: 14),
          if (selectedFromMap)
            const Padding(
              padding: EdgeInsets.only(bottom: 10),
              child: Text(
                'Hidrante seleccionado desde el mapa',
                style: TextStyle(
                  color: AppColors.green,
                  fontWeight: FontWeight.w700,
                ),
              ),
            )
          else if (widget.selectedHydrantId?.isNotEmpty ?? false)
            const Padding(
              padding: EdgeInsets.only(bottom: 10),
              child: Text(
                'El hidrante seleccionado ya no está disponible en el catálogo.',
                style: TextStyle(color: AppColors.orange),
              ),
            ),
          Text(
            '${matches.length} resultados visibles',
            style: const TextStyle(color: AppColors.muted),
          ),
          if (state.catalogHydrants.isEmpty)
            SectionCard(
              child: Column(
                children: [
                  const Text('No hay catálogo general disponible localmente.'),
                  const SizedBox(height: 8),
                  FilledButton.icon(
                    onPressed: state.assignmentSyncing
                        ? null
                        : state.synchronizeAssignments,
                    icon: const Icon(Icons.sync),
                    label: const Text('Descargar catálogo'),
                  ),
                ],
              ),
            ),
          if (matches.isEmpty || normalized.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 12, bottom: 8),
              child: FilledButton.icon(
                key: const ValueKey('register-manual-hydrant'),
                onPressed: startingId == null
                    ? () => _registerManual(state)
                    : null,
                icon: const Icon(Icons.add_location_alt_outlined),
                label: const Text('Registrar hidrante no encontrado'),
              ),
            ),
          for (final hydrant in matches)
            Builder(
              builder: (context) {
                final canStart = hydrantAvailableForNewRv(hydrant);
                return Card(
                  child: ListTile(
                    title: Text('Cuenta ${hydrant.code}'),
                    subtitle: Text(
                      canStart
                          ? 'Disponible para revisión'
                          : '${hydrant.rvStatus == 'validated' ? 'Validado' : 'Ya revisado'}${hydrant.lastStatusChangedAt == null ? '' : ' · ${hydrant.lastStatusChangedAt!.toLocal()}'}',
                    ),
                    trailing: startingId == hydrant.id
                        ? const SizedBox.square(
                            dimension: 24,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.chevron_right),
                    onTap: startingId == null
                        ? () => canStart
                              ? _confirmAndStart(state, hydrant)
                              : context.push(
                                  '/visual-report/${Uri.encodeComponent(hydrant.code)}',
                                )
                        : null,
                  ),
                );
              },
            ),
        ],
      ),
    );
  }

  Future<void> _registerManual(AppState state) async {
    final account = TextEditingController(text: query.trim());
    final locality = TextEditingController();
    final municipality = TextEditingController();
    final reason = TextEditingController();
    final formKey = GlobalKey<FormState>();
    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Registrar hidrante no encontrado'),
        content: Form(
          key: formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  key: const ValueKey('manual-hydrant-account'),
                  controller: account,
                  decoration: const InputDecoration(
                    labelText: 'Número o clave visible',
                  ),
                  validator: (value) => value?.trim().isEmpty == true
                      ? 'Captura una clave visible.'
                      : null,
                ),
                TextFormField(
                  controller: locality,
                  decoration: const InputDecoration(labelText: 'Localidad'),
                ),
                TextFormField(
                  controller: municipality,
                  decoration: const InputDecoration(
                    labelText: 'Municipio o módulo',
                  ),
                ),
                TextFormField(
                  key: const ValueKey('manual-hydrant-reason'),
                  controller: reason,
                  minLines: 2,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    labelText: 'Motivo del alta manual',
                  ),
                  validator: (value) => value?.trim().isEmpty == true
                      ? 'Describe por qué no está en el catálogo.'
                      : null,
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () {
              if (formKey.currentState?.validate() == true) {
                Navigator.pop(dialogContext, true);
              }
            },
            child: const Text('Guardar localmente'),
          ),
        ],
      ),
    );
    if (accepted != true || !mounted) {
      account.dispose();
      locality.dispose();
      municipality.dispose();
      reason.dispose();
      return;
    }
    setState(() => startingId = 'manual');
    try {
      final hydrant = await state.createManualHydrant(
        accountNumber: account.text,
        locality: locality.text,
        municipality: municipality.text,
        reason: reason.text,
      );
      if (!mounted) return;
      await _confirmAndStart(state, hydrant);
    } finally {
      account.dispose();
      locality.dispose();
      municipality.dispose();
      reason.dispose();
      if (mounted) setState(() => startingId = null);
    }
  }

  Future<void> _confirmAndStart(AppState state, Hydrant hydrant) async {
    final existing = state.rvDraftRepository.activeFor(hydrant.id);
    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(
          existing == null
              ? 'Confirmar hidrante'
              : 'Continuar revisión existente',
        ),
        content: Text(
          'Cuenta: ${hydrant.code}\nLocalidad: ${hydrant.locality}\nMunicipio: ${hydrant.parcel}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(existing == null ? 'Crear borrador' : 'Continuar'),
          ),
        ],
      ),
    );
    if (accepted != true || !mounted) return;
    final checklist = state.activeChecklist;
    if (checklist == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Sin checklist RV disponible. Sincroniza primero.'),
        ),
      );
      return;
    }
    setState(() => startingId = hydrant.id);
    try {
      await state.rvDraftRepository.openOrCreate(
        hydrant: hydrant,
        user: state.user,
        checklist: checklist,
      );
      state.includeLocalHydrant(hydrant);
      if (mounted) context.go('/hydrants/${hydrant.id}/inspection/a');
    } finally {
      if (mounted) setState(() => startingId = null);
    }
  }
}

@visibleForTesting
bool hydrantVisibleForNewRv(
  Hydrant hydrant, {
  required String normalizedQuery,
  required bool hasLocalWork,
}) {
  final code = hydrant.code.trim().toLowerCase();
  final exactAccountMatch =
      normalizedQuery.isNotEmpty && code == normalizedQuery;
  final alreadyReviewed = !hydrantAvailableForNewRv(hydrant);
  final matchesQuery =
      normalizedQuery.isEmpty ||
      code.contains(normalizedQuery) ||
      hydrant.locality.toLowerCase().contains(normalizedQuery) ||
      hydrant.parcel.toLowerCase().contains(normalizedQuery);
  if (!matchesQuery) return false;
  if (exactAccountMatch) return true;
  return hasLocalWork ||
      (hydrant.isActive && hydrant.availableForRv && !alreadyReviewed);
}

@visibleForTesting
bool hydrantAvailableForNewRv(Hydrant hydrant) =>
    hydrant.availableForRv &&
    hydrant.f02a.status != InspectionStatus.completed &&
    hydrant.f02a.status != InspectionStatus.validated;
