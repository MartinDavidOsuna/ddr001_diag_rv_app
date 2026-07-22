import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../../../data/catalogs/functional_catalogs.dart';
import '../../../domain/functional/functional_collection_models.dart';

class AlarmAttemptEditor {
  const AlarmAttemptEditor._();

  static Future<AlarmAttemptRecord?> show(
    BuildContext context, {
    required String inspectionId,
    required int Function(String type) nextAttempt,
    AlarmAttemptRecord? existing,
    bool repeat = false,
  }) {
    var type = existing?.alarmType ?? FunctionalCatalogs.alarmTypes.first;
    var description = existing?.otherDescription ?? '';
    var generated = repeat ? false : existing?.generated ?? false;
    var detected = repeat ? false : existing?.detectedLocally ?? false;
    var reported = repeat ? false : existing?.reported ?? false;
    var acknowledged = repeat ? false : existing?.acknowledged ?? false;
    var result = repeat ? '' : existing?.result ?? '';
    var comments = repeat ? '' : existing?.comments ?? '';
    final formKey = GlobalKey<FormState>();
    return showDialog<AlarmAttemptRecord>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (_, setLocal) => AlertDialog(
          title: Text(
            repeat
                ? 'Repetir alarma'
                : existing == null
                ? 'Nuevo intento de alarma'
                : 'Editar intento ${existing.attemptNumber}',
          ),
          content: SizedBox(
            width: 500,
            child: Form(
              key: formKey,
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    DropdownButtonFormField<String>(
                      initialValue: type,
                      items: [
                        for (final value in FunctionalCatalogs.alarmTypes)
                          DropdownMenuItem(value: value, child: Text(value)),
                      ],
                      onChanged: existing == null || repeat
                          ? (value) => setLocal(() => type = value!)
                          : null,
                      decoration: const InputDecoration(labelText: 'Tipo'),
                    ),
                    if (type.toLowerCase() == 'otra')
                      TextFormField(
                        initialValue: description,
                        decoration: const InputDecoration(
                          labelText: 'Descripción de otra alarma',
                        ),
                        validator: (value) =>
                            value == null || value.trim().isEmpty
                            ? 'La descripción es obligatoria.'
                            : null,
                        onChanged: (value) => description = value,
                      ),
                    CheckboxListTile(
                      value: generated,
                      title: const Text('Generada'),
                      onChanged: (v) => setLocal(() => generated = v ?? false),
                    ),
                    CheckboxListTile(
                      value: detected,
                      title: const Text('Detectada localmente'),
                      onChanged: (v) => setLocal(() => detected = v ?? false),
                    ),
                    CheckboxListTile(
                      value: reported,
                      title: const Text('Reportada'),
                      onChanged: (v) => setLocal(() => reported = v ?? false),
                    ),
                    CheckboxListTile(
                      value: acknowledged,
                      title: const Text('Reconocida'),
                      onChanged: (v) =>
                          setLocal(() => acknowledged = v ?? false),
                    ),
                    TextFormField(
                      initialValue: result,
                      decoration: const InputDecoration(labelText: 'Resultado'),
                      onChanged: (v) => result = v,
                    ),
                    TextFormField(
                      initialValue: comments,
                      maxLines: 3,
                      decoration: const InputDecoration(
                        labelText: 'Comentarios',
                      ),
                      onChanged: (v) => comments = v,
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
                final generatedAt = generated
                    ? existing?.generatedAt ?? now
                    : null;
                final detectedAt = detected
                    ? existing?.detectedAt ?? now
                    : null;
                final reportedAt = reported
                    ? existing?.reportedAt ?? now
                    : null;
                final latency = generatedAt != null && reportedAt != null
                    ? reportedAt
                          .difference(generatedAt)
                          .inMilliseconds
                          .clamp(0, 1 << 31)
                    : null;
                Navigator.pop(
                  dialogContext,
                  AlarmAttemptRecord(
                    id: existing == null || repeat
                        ? const Uuid().v4()
                        : existing.id,
                    inspectionId: inspectionId,
                    alarmType: type,
                    otherDescription: description.trim(),
                    attemptNumber: existing == null || repeat
                        ? nextAttempt(type)
                        : existing.attemptNumber,
                    generated: generated,
                    detectedLocally: detected,
                    reported: reported,
                    generatedAt: generatedAt,
                    detectedAt: detectedAt,
                    reportedAt: reportedAt,
                    latencyMs: latency,
                    acknowledged: acknowledged,
                    acknowledgedAt: acknowledged
                        ? existing?.acknowledgedAt ?? now
                        : null,
                    result: result.trim(),
                    comments: comments.trim(),
                    photoIds: repeat
                        ? const []
                        : existing?.photoIds ?? const [],
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
}
