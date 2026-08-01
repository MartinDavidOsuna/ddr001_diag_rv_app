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
    final min = TextEditingController(), max = TextEditingController();
    String unit = 'psi';
    final result = await showDialog<PressureRangeOption>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: const Text('Nuevo rango'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: min,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(labelText: 'Mínimo'),
              ),
              TextField(
                controller: max,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(labelText: 'Máximo'),
              ),
              DropdownButtonFormField(
                initialValue: unit,
                items: const [
                  DropdownMenuItem(value: 'psi', child: Text('psi')),
                  DropdownMenuItem(value: 'bar', child: Text('bar')),
                ],
                onChanged: (v) => setLocal(() => unit = v!),
                decoration: const InputDecoration(labelText: 'Unidad'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () async {
                try {
                  final item = await widget.repository.createPressureRange(
                    double.parse(min.text.replaceAll(',', '.')),
                    double.parse(max.text.replaceAll(',', '.')),
                    unit,
                    ownerUserId: widget.userId,
                  );
                  if (context.mounted) Navigator.pop(context, item);
                } on Object catch (e) {
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        e is FormatException
                            ? e.message
                            : 'El rango no es válido.',
                      ),
                    ),
                  );
                }
              },
              child: const Text('Agregar'),
            ),
          ],
        ),
      ),
    );
    min.dispose();
    max.dispose();
    if (!mounted) return;
    if (result != null) Navigator.pop(context, result);
  }
}
