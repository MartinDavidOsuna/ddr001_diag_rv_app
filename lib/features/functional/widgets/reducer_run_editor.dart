import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../../../domain/functional/functional_collection_models.dart';

class ReducerRunEditor {
  const ReducerRunEditor._();

  static Future<ReducerRun?> show(
    BuildContext context, {
    required String inspectionId,
    required int order,
    ReducerRun? existing,
    bool duplicate = false,
  }) {
    var condition = existing?.conditionKey ?? 'default';
    var min = existing?.flowRangeMin?.toString() ?? '';
    var max = existing?.flowRangeMax?.toString() ?? '';
    var inlet = existing?.inletPressure ?? '';
    var target = existing?.targetPressure ?? '';
    var outlet = existing?.outletPressure ?? '';
    var flow = existing?.flow ?? '';
    var stability = existing?.stability ?? '';
    var adjustment = existing?.adjustment ?? '';
    var result = duplicate ? '' : existing?.result ?? '';
    var instruments = duplicate ? '' : existing?.instrumentIds.join(', ') ?? '';
    var series = duplicate
        ? ''
        : existing?.measurementSeriesIds.join(', ') ?? '';
    return showDialog<ReducerRun>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(
          existing == null
              ? 'Nueva corrida de reductora'
              : duplicate
              ? 'Duplicar corrida'
              : 'Editar corrida ${existing.order}',
        ),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Column(
              children: [
                _field(
                  'Condición o rango equivalente',
                  condition,
                  (v) => condition = v,
                ),
                Row(
                  children: [
                    Expanded(
                      child: _field(
                        'Caudal mínimo',
                        min,
                        (v) => min = v,
                        numeric: true,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _field(
                        'Caudal máximo',
                        max,
                        (v) => max = v,
                        numeric: true,
                      ),
                    ),
                  ],
                ),
                _field(
                  'Presión de entrada (kPa)',
                  inlet,
                  (v) => inlet = v,
                  numeric: true,
                ),
                _field(
                  'Presión objetivo (kPa)',
                  target,
                  (v) => target = v,
                  numeric: true,
                ),
                _field(
                  'Presión de salida (kPa)',
                  outlet,
                  (v) => outlet = v,
                  numeric: true,
                ),
                _field('Caudal (L/s)', flow, (v) => flow = v, numeric: true),
                _field('Estabilidad', stability, (v) => stability = v),
                _field('Ajuste', adjustment, (v) => adjustment = v),
                _field(
                  'Instrumentos (IDs separados por coma)',
                  instruments,
                  (v) => instruments = v,
                ),
                _field(
                  'Series (IDs separados por coma)',
                  series,
                  (v) => series = v,
                ),
                _field('Resultado', result, (v) => result = v),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () {
              final now = DateTime.now().toUtc();
              Navigator.pop(
                dialogContext,
                ReducerRun(
                  reducerRunId: existing == null || duplicate
                      ? const Uuid().v4()
                      : existing.reducerRunId,
                  reducerId: existing?.reducerId ?? 'reducer:$inspectionId',
                  inspectionId: inspectionId,
                  order: existing == null || duplicate ? order : existing.order,
                  conditionKey: condition.trim().isEmpty
                      ? 'default'
                      : condition.trim(),
                  flowRangeMin: double.tryParse(min),
                  flowRangeMax: double.tryParse(max),
                  inletPressure: inlet.trim(),
                  targetPressure: target.trim(),
                  outletPressure: outlet.trim(),
                  flow: flow.trim(),
                  stability: stability.trim(),
                  adjustment: adjustment.trim(),
                  instrumentIds: _ids(instruments),
                  measurementSeriesIds: _ids(series),
                  photoIds: duplicate
                      ? const []
                      : existing?.photoIds ?? const [],
                  result: result.trim(),
                  accepted: duplicate ? false : existing?.accepted ?? false,
                  invalidatedAt: duplicate ? null : existing?.invalidatedAt,
                  invalidatedBy: duplicate ? null : existing?.invalidatedBy,
                  invalidationReason: duplicate
                      ? null
                      : existing?.invalidationReason,
                  createdAt: existing == null || duplicate
                      ? now
                      : existing.createdAt,
                  updatedAt: now,
                  schemaVersion: 2,
                ),
              );
            },
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
  }

  static Widget _field(
    String label,
    String value,
    ValueChanged<String> changed, {
    bool numeric = false,
  }) => TextFormField(
    initialValue: value,
    keyboardType: numeric
        ? const TextInputType.numberWithOptions(decimal: true)
        : TextInputType.text,
    decoration: InputDecoration(labelText: label),
    onChanged: changed,
  );

  static List<String> _ids(String value) =>
      value.split(',').map((v) => v.trim()).where((v) => v.isNotEmpty).toList();
}

class ReducerRunComparison extends StatelessWidget {
  const ReducerRunComparison({required this.runs, super.key});
  final List<ReducerRun> runs;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    child: DataTable(
      columns: const [
        DataColumn(label: Text('Corrida')),
        DataColumn(label: Text('Rango')),
        DataColumn(label: Text('Entrada')),
        DataColumn(label: Text('Objetivo')),
        DataColumn(label: Text('Salida')),
        DataColumn(label: Text('Caudal')),
        DataColumn(label: Text('Estabilidad')),
        DataColumn(label: Text('Ajuste')),
        DataColumn(label: Text('Resultado')),
        DataColumn(label: Text('Aceptada')),
        DataColumn(label: Text('Fecha')),
      ],
      rows: [
        for (final run in runs)
          DataRow(
            cells: [
              DataCell(Text('${run.order}')),
              DataCell(
                Text(
                  '${run.flowRangeMin ?? '—'}–${run.flowRangeMax ?? '—'} ${run.flowUnit}',
                ),
              ),
              DataCell(Text(run.inletPressure)),
              DataCell(Text(run.targetPressure)),
              DataCell(Text(run.outletPressure)),
              DataCell(Text(run.flow)),
              DataCell(Text(run.stability)),
              DataCell(Text(run.adjustment)),
              DataCell(Text(run.result.isEmpty ? 'Borrador' : run.result)),
              DataCell(Text(run.accepted ? 'Sí' : 'No')),
              DataCell(
                Text(run.createdAt.toLocal().toString().substring(0, 16)),
              ),
            ],
          ),
      ],
    ),
  );
}
