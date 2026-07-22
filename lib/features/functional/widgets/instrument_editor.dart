import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../../../data/catalogs/functional_catalogs.dart';
import '../../../domain/functional/functional_models.dart';

class InstrumentEditor {
  const InstrumentEditor._();

  static Future<InstrumentRecord?> show(
    BuildContext context, {
    required String inspectionId,
    required String operatorId,
    InstrumentRecord? existing,
  }) {
    var type = existing?.type ?? FunctionalCatalogs.instrumentTypes.first;
    var asset = existing?.assetCode ?? '';
    var brand = existing?.brandText ?? '';
    var model = existing?.modelText ?? '';
    var serial = existing?.serialNumber ?? '';
    var identification =
        existing?.identificationStatus ??
        InstrumentIdentificationStatus.identified;
    var range = existing?.measurementRange ?? '';
    var unit = existing?.unit ?? '';
    var accuracy = existing?.accuracyClass ?? '';
    var calibrationDate =
        existing?.calibrationDate?.toIso8601String().split('T').first ?? '';
    var dueDate =
        existing?.calibrationDueDate?.toIso8601String().split('T').first ?? '';
    var certificate = existing?.calibrationCertificate ?? '';
    var calibration = existing?.calibrationStatus ?? CalibrationStatus.unknown;
    var condition = existing?.condition ?? '';
    var comments = existing?.comments ?? '';
    return showDialog<InstrumentRecord>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (_, setLocal) => AlertDialog(
          title: Text(
            existing == null ? 'Agregar instrumento' : 'Editar instrumento',
          ),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: Column(
                children: [
                  DropdownButtonFormField<String>(
                    initialValue: type,
                    items: [
                      for (final value in FunctionalCatalogs.instrumentTypes)
                        DropdownMenuItem(value: value, child: Text(value)),
                    ],
                    onChanged: (value) => setLocal(() => type = value!),
                    decoration: const InputDecoration(labelText: 'Tipo'),
                  ),
                  _field('Código de activo', asset, (v) => asset = v),
                  _field('Marca', brand, (v) => brand = v),
                  _field('Modelo', model, (v) => model = v),
                  _field('Número de serie', serial, (v) => serial = v),
                  DropdownButtonFormField<InstrumentIdentificationStatus>(
                    initialValue: identification,
                    items: [
                      for (final value in InstrumentIdentificationStatus.values)
                        DropdownMenuItem(
                          value: value,
                          child: Text(_identificationLabel(value)),
                        ),
                    ],
                    onChanged: (value) =>
                        setLocal(() => identification = value!),
                    decoration: const InputDecoration(
                      labelText: 'Estado de identificación',
                    ),
                  ),
                  _field('Rango de medición', range, (v) => range = v),
                  _field('Unidad', unit, (v) => unit = v),
                  _field('Clase de precisión', accuracy, (v) => accuracy = v),
                  _field(
                    'Fecha de calibración (AAAA-MM-DD)',
                    calibrationDate,
                    (v) => calibrationDate = v,
                  ),
                  _field(
                    'Vencimiento (AAAA-MM-DD)',
                    dueDate,
                    (v) => dueDate = v,
                  ),
                  _field(
                    'Certificado o referencia',
                    certificate,
                    (v) => certificate = v,
                  ),
                  DropdownButtonFormField<CalibrationStatus>(
                    initialValue: calibration,
                    items: [
                      for (final value in CalibrationStatus.values)
                        DropdownMenuItem(value: value, child: Text(value.name)),
                    ],
                    onChanged: (value) => setLocal(() => calibration = value!),
                    decoration: const InputDecoration(labelText: 'Calibración'),
                  ),
                  _field('Condición', condition, (v) => condition = v),
                  _field(
                    'Comentarios',
                    comments,
                    (v) => comments = v,
                    lines: 3,
                  ),
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
                Navigator.pop(
                  dialogContext,
                  InstrumentRecord(
                    id: existing?.id ?? const Uuid().v4(),
                    inspectionId: inspectionId,
                    type: type,
                    assetCode: asset.trim(),
                    brandText: brand.trim(),
                    modelText: model.trim(),
                    serialNumber: serial.trim(),
                    identificationStatus: identification,
                    measurementRange: range.trim(),
                    unit: unit.trim(),
                    accuracyClass: accuracy.trim(),
                    calibrationDate: DateTime.tryParse(
                      calibrationDate,
                    )?.toUtc(),
                    calibrationDueDate: DateTime.tryParse(dueDate)?.toUtc(),
                    calibrationCertificate: certificate.trim(),
                    calibrationStatus: calibration,
                    condition: condition.trim(),
                    operatorId: operatorId,
                    comments: comments.trim(),
                    photoIds: existing?.photoIds ?? const [],
                    deletedAt: existing?.deletedAt,
                    lifecycleStatus:
                        existing?.lifecycleStatus ??
                        InstrumentLifecycleStatus.active,
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

  static Widget _field(
    String label,
    String value,
    ValueChanged<String> changed, {
    int lines = 1,
  }) => TextFormField(
    initialValue: value,
    maxLines: lines,
    decoration: InputDecoration(labelText: label),
    onChanged: changed,
  );

  static String _identificationLabel(InstrumentIdentificationStatus value) =>
      switch (value) {
        InstrumentIdentificationStatus.identified => 'Identificado',
        InstrumentIdentificationStatus.notIdentifiable => 'No identificable',
        InstrumentIdentificationStatus.unreadable => 'No legible',
        InstrumentIdentificationStatus.noPlate => 'Sin placa',
        InstrumentIdentificationStatus.notIdentified => 'No identificado',
      };
}
