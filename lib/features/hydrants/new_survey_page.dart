import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../app/theme/app_theme.dart';
import '../../core/services/app_state.dart';
import '../../core/widgets/common_widgets.dart';
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
    final filtered = state.catalogHydrants
        .where(
          (hydrant) =>
              normalized.isEmpty ||
              hydrant.code.toLowerCase().contains(normalized) ||
              hydrant.locality.toLowerCase().contains(normalized) ||
              hydrant.parcel.toLowerCase().contains(normalized),
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
          for (final hydrant in matches)
            Card(
              child: ListTile(
                title: Text('Cuenta ${hydrant.code}'),
                subtitle: Text('${hydrant.locality} · ${hydrant.parcel}'),
                trailing: startingId == hydrant.id
                    ? const SizedBox.square(
                        dimension: 24,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.chevron_right),
                onTap: startingId == null
                    ? () => _confirmAndStart(state, hydrant)
                    : null,
              ),
            ),
        ],
      ),
    );
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
