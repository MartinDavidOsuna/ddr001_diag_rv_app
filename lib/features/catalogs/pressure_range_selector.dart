import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/services/app_state.dart';
import 'dynamic_catalog_repository.dart';

class PressureRangeSelector extends StatelessWidget {
  const PressureRangeSelector({
    required this.value,
    required this.onChanged,
    this.enabled = true,
    super.key,
  });
  final Map<String, dynamic>? value;
  final ValueChanged<Map<String, dynamic>> onChanged;
  final bool enabled;
  @override
  Widget build(BuildContext context) {
    final selected = value?['displayName']?.toString();
    return Semantics(
      label: 'Seleccionar rango de manómetro',
      button: true,
      child: ListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('Rango de manómetro'),
        subtitle: Text(selected ?? 'No capturado'),
        trailing: const Icon(Icons.arrow_drop_down),
        enabled: enabled,
        onTap: enabled ? () => _open(context) : null,
      ),
    );
  }

  Future<void> _open(BuildContext context) async {
    final state = context.read<AppState>(),
        repo = state.dynamicCatalogRepository!;
    final selected = await showModalBottomSheet<PressureRangeOption>(
      context: context,
      isScrollControlled: true,
      builder: (context) =>
          _PressureRangeSheet(repository: repo, userId: state.user.id),
    );
    if (selected != null) {
      onChanged({
        'catalogId': selected.remoteId,
        'localCatalogId': selected.localId,
        'pressureRangeId': selected.remoteId,
        'clientPressureRangeId': selected.localId,
        'minimum': selected.minimum,
        'maximum': selected.maximum,
        'unit': selected.unit,
        'displayName': selected.display,
        'displayValue': selected.display,
        'isPendingSync': selected.status != CatalogSyncStatus.synced,
      });
    }
  }
}

class _PressureRangeSheet extends StatefulWidget {
  const _PressureRangeSheet({required this.repository, required this.userId});
  final DynamicCatalogRepository repository;
  final String userId;
  @override
  State<_PressureRangeSheet> createState() => _PressureRangeSheetState();
}

class _PressureRangeSheetState extends State<_PressureRangeSheet> {
  String query = '';
  @override
  Widget build(BuildContext context) {
    final items = widget.repository.pressureRanges
        .where((x) => x.display.toLowerCase().contains(query.toLowerCase()))
        .toList();
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 16,
          bottom: MediaQuery.viewInsetsOf(context).bottom + 16,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              decoration: const InputDecoration(
                labelText: 'Buscar rango',
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: (v) => setState(() => query = v),
            ),
            const SizedBox(height: 8),
            Flexible(
              child: ListView(
                children: [
                  for (final item in items)
                    ListTile(
                      title: Text(item.display),
                      subtitle: item.status == CatalogSyncStatus.synced
                          ? null
                          : const Text('Pendiente de sincronización'),
                      onTap: () => Navigator.pop(context, item),
                    ),
                ],
              ),
            ),
            FilledButton.icon(
              onPressed: _add,
              icon: const Icon(Icons.add),
              label: const Text('Agregar rango'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _add() async {
    // The dialog must not inherit from the bottom sheet: after choosing a
    // range the sheet closes too, while the dialog route is still unmounting.
    // Anchoring it to the root navigator keeps those element trees independent.
    final rootContext = Navigator.of(context, rootNavigator: true).context;
    final result = await showDialog<PressureRangeOption>(
      context: rootContext,
      builder: (context) => _NewPressureRangeDialog(
        repository: widget.repository,
        userId: widget.userId,
      ),
    );
    if (!mounted) return;
    if (result != null) Navigator.pop(context, result);
  }
}

class _NewPressureRangeDialog extends StatefulWidget {
  const _NewPressureRangeDialog({
    required this.repository,
    required this.userId,
  });

  final DynamicCatalogRepository repository;
  final String userId;

  @override
  State<_NewPressureRangeDialog> createState() =>
      _NewPressureRangeDialogState();
}

class _NewPressureRangeDialogState extends State<_NewPressureRangeDialog> {
  final minimumController = TextEditingController();
  final maximumController = TextEditingController();
  String unit = 'psi';

  @override
  void dispose() {
    minimumController.dispose();
    maximumController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Nuevo rango'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(
          controller: minimumController,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(labelText: 'Mínimo'),
        ),
        TextField(
          controller: maximumController,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(labelText: 'Máximo'),
        ),
        DropdownButtonFormField(
          initialValue: unit,
          items: const [
            DropdownMenuItem(value: 'psi', child: Text('psi')),
            DropdownMenuItem(value: 'bar', child: Text('bar')),
          ],
          onChanged: (value) => setState(() => unit = value!),
          decoration: const InputDecoration(labelText: 'Unidad'),
        ),
      ],
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancelar'),
      ),
      FilledButton(onPressed: _submit, child: const Text('Agregar')),
    ],
  );

  Future<void> _submit() async {
    try {
      final item = await widget.repository.createPressureRange(
        double.parse(minimumController.text.replaceAll(',', '.')),
        double.parse(maximumController.text.replaceAll(',', '.')),
        unit,
        ownerUserId: widget.userId,
      );
      if (mounted) Navigator.pop(context, item);
    } on Object catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            error is FormatException ? error.message : 'El rango no es válido.',
          ),
        ),
      );
    }
  }
}
