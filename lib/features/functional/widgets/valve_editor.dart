import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../../../domain/functional/functional_collection_models.dart';
import '../../../domain/functional/functional_models.dart';

class ValveEditor {
  const ValveEditor._();

  static Future<ValveRecord?> show(
    BuildContext context, {
    required String inspectionId,
    required int suggestedOrder,
    ValveRecord? existing,
    bool duplicate = false,
  }) {
    var label = duplicate
        ? 'V$suggestedOrder'
        : existing?.label ?? 'V$suggestedOrder';
    var type = existing?.type ?? '';
    var diameter = existing?.diameter ?? '';
    var position = existing?.initialPosition ?? '';
    var configuration = '${existing?.configuration['notes'] ?? ''}';
    final formKey = GlobalKey<FormState>();
    return showDialog<ValveRecord>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(
          existing == null
              ? 'Agregar válvula'
              : duplicate
              ? 'Duplicar configuración'
              : 'Editar ${existing.label}',
        ),
        content: SizedBox(
          width: 480,
          child: Form(
            key: formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    initialValue: label,
                    decoration: const InputDecoration(
                      labelText: 'Etiqueta visible',
                    ),
                    maxLength: 30,
                    validator: (value) => value == null || value.trim().isEmpty
                        ? 'La etiqueta es obligatoria.'
                        : null,
                    onChanged: (value) => label = value,
                  ),
                  TextFormField(
                    initialValue: type,
                    decoration: const InputDecoration(labelText: 'Tipo'),
                    onChanged: (value) => type = value,
                  ),
                  TextFormField(
                    initialValue: diameter,
                    decoration: const InputDecoration(labelText: 'Diámetro'),
                    onChanged: (value) => diameter = value,
                  ),
                  TextFormField(
                    initialValue: position,
                    decoration: const InputDecoration(
                      labelText: 'Posición inicial',
                    ),
                    onChanged: (value) => position = value,
                  ),
                  TextFormField(
                    initialValue: configuration,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      labelText: 'Configuración',
                    ),
                    onChanged: (value) => configuration = value,
                  ),
                ],
              ),
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
              if (!formKey.currentState!.validate()) return;
              final now = DateTime.now().toUtc();
              Navigator.pop(
                dialogContext,
                ValveRecord(
                  id: existing == null || duplicate
                      ? const Uuid().v4()
                      : existing.id,
                  inspectionId: inspectionId,
                  order: existing == null || duplicate
                      ? suggestedOrder
                      : existing.order,
                  label: label.trim(),
                  type: type.trim(),
                  diameter: diameter.trim(),
                  initialPosition: position.trim(),
                  configuration: {
                    ...?existing?.configuration,
                    'notes': configuration.trim(),
                  },
                  testIds: duplicate ? const [] : existing?.testIds ?? const [],
                  photoIds: duplicate
                      ? const []
                      : existing?.photoIds ?? const [],
                  seriesIds: duplicate
                      ? const []
                      : existing?.seriesIds ?? const [],
                  instrumentIds: duplicate
                      ? const []
                      : existing?.instrumentIds ?? const [],
                  result: duplicate ? '' : existing?.result ?? '',
                  retiredAt: duplicate ? null : existing?.retiredAt,
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
}

class ValveTestEditor {
  const ValveTestEditor._();

  static Future<FunctionalValveTest?> show(
    BuildContext context, {
    required String inspectionId,
    required ValveRecord valve,
    required int sequence,
    FunctionalValveTest? existing,
    bool repeat = false,
  }) {
    var opening = repeat ? '' : existing?.openingTimeSeconds ?? '';
    var closing = repeat ? '' : existing?.closingTimeSeconds ?? '';
    var cycles = repeat ? 1 : existing?.numberOfCycles ?? 1;
    var manual = repeat ? '' : existing?.manualOperation ?? '';
    var automatic = repeat ? '' : existing?.automaticOperation ?? '';
    var effort = repeat ? '' : existing?.effort ?? '';
    var blockage = repeat ? false : existing?.blockage ?? false;
    var noise = repeat ? false : existing?.noise ?? false;
    var vibration = repeat ? false : existing?.vibration ?? false;
    var leakage = repeat ? '' : existing?.leakageLevel ?? '';
    var pressure = repeat ? '' : existing?.pressureBehavior ?? '';
    var result = repeat ? '' : existing?.result ?? '';
    var comments = repeat ? '' : existing?.comments ?? '';
    var instrumentIds = repeat
        ? ''
        : (existing?.instrumentIds.join(', ') ?? '');
    var seriesIds = repeat
        ? ''
        : (existing?.measurementSeriesIds.join(', ') ?? '');
    return showDialog<FunctionalValveTest>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (_, setLocal) => AlertDialog(
          title: Text(
            '${repeat
                ? 'Repetir'
                : existing == null
                ? 'Nueva'
                : 'Editar'} prueba · ${valve.label}',
          ),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: Column(
                children: [
                  _text(
                    'Tiempo de apertura (s)',
                    opening,
                    (v) => opening = v,
                    numeric: true,
                  ),
                  _text(
                    'Tiempo de cierre (s)',
                    closing,
                    (v) => closing = v,
                    numeric: true,
                  ),
                  _text(
                    'Número de ciclos',
                    '$cycles',
                    (v) => cycles = int.tryParse(v) ?? 1,
                    numeric: true,
                  ),
                  _text('Operación manual', manual, (v) => manual = v),
                  _text(
                    'Operación automática',
                    automatic,
                    (v) => automatic = v,
                  ),
                  _text('Esfuerzo', effort, (v) => effort = v),
                  SwitchListTile(
                    value: blockage,
                    title: const Text('Bloqueo'),
                    onChanged: (v) => setLocal(() => blockage = v),
                  ),
                  SwitchListTile(
                    value: noise,
                    title: const Text('Ruido'),
                    onChanged: (v) => setLocal(() => noise = v),
                  ),
                  SwitchListTile(
                    value: vibration,
                    title: const Text('Vibración'),
                    onChanged: (v) => setLocal(() => vibration = v),
                  ),
                  _text('Nivel de fuga', leakage, (v) => leakage = v),
                  _text(
                    'Comportamiento de presión',
                    pressure,
                    (v) => pressure = v,
                  ),
                  _text(
                    'Instrumentos relacionados (IDs separados por coma)',
                    instrumentIds,
                    (v) => instrumentIds = v,
                  ),
                  _text(
                    'Series relacionadas (IDs separados por coma)',
                    seriesIds,
                    (v) => seriesIds = v,
                  ),
                  _text('Resultado', result, (v) => result = v),
                  _text('Comentarios', comments, (v) => comments = v, lines: 3),
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
                  FunctionalValveTest(
                    id: existing == null || repeat
                        ? const Uuid().v4()
                        : existing.id,
                    inspectionId: inspectionId,
                    valveId: valve.id,
                    diameter: valve.diameter,
                    testSequence: existing == null || repeat
                        ? sequence
                        : existing.testSequence,
                    openingTimeSeconds: opening.trim(),
                    closingTimeSeconds: closing.trim(),
                    numberOfCycles: cycles,
                    manualOperation: manual.trim(),
                    automaticOperation: automatic.trim(),
                    effort: effort.trim(),
                    blockage: blockage,
                    noise: noise,
                    vibration: vibration,
                    leakageLevel: leakage.trim(),
                    pressureBehavior: pressure.trim(),
                    photoIds: repeat
                        ? const []
                        : existing?.photoIds ?? const [],
                    instrumentIds: _ids(instrumentIds),
                    measurementSeriesIds: _ids(seriesIds),
                    result: result.trim(),
                    comments: comments.trim(),
                    createdAt: existing == null || repeat
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
      ),
    );
  }

  static Widget _text(
    String label,
    String value,
    ValueChanged<String> changed, {
    bool numeric = false,
    int lines = 1,
  }) => TextFormField(
    initialValue: value,
    keyboardType: numeric ? TextInputType.number : TextInputType.text,
    maxLines: lines,
    decoration: InputDecoration(labelText: label),
    onChanged: changed,
  );

  static List<String> _ids(String value) =>
      value.split(',').map((v) => v.trim()).where((v) => v.isNotEmpty).toList();
}
