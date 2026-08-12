import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:hive_ce/hive.dart';
import 'package:image_picker/image_picker.dart';

import '../../../app/theme/app_theme.dart';
import '../../../core/widgets/common_widgets.dart';
import '../../../domain/media/inspection_photo.dart';
import '../domain/rv_draft.dart';
import '../domain/rv_sync_state.dart';
import 'rv_inspection_controller.dart';

String rvPhotoCountLabel(int count) =>
    count == 1 ? '1 foto capturada' : '$count fotos capturadas';

int? normalizedSignalPercent(RvSignalSample sample) {
  if (sample.signalPercent case final percent?) {
    return percent.clamp(0, 100);
  }
  final level = sample.level;
  if (level == null) return null;
  if (level == 0 && sample.availabilityReason == 'no_service') return null;
  return (level.clamp(0, 4) * 25).round();
}

String signalQualityLabel(int? percent) {
  if (percent == null) return 'No disponible';
  if (percent <= 20) return 'Muy baja';
  if (percent <= 40) return 'Baja';
  if (percent <= 60) return 'Media';
  if (percent <= 80) return 'Buena';
  return 'Excelente';
}

String networkTechnologyLabel(RvSignalSample sample) {
  if (sample.availabilityReason == 'no_sim') return 'No disponible';
  if (sample.availabilityReason == 'no_service') return 'Sin servicio';
  if (sample.networkTechnology case final technology?
      when technology.isNotEmpty) {
    return technology;
  }
  if (!sample.connected) return 'Sin servicio';
  final raw = '${sample.networkType ?? ''} ${sample.generation}'.toLowerCase();
  if (raw.contains('wifi')) return 'Wi-Fi';
  if (raw.contains('5g')) return '5G';
  if (raw.contains('lte')) return 'LTE';
  if (raw.contains('4g')) return '4G';
  if (raw.contains('3g')) return '3G';
  if (raw.contains('2g')) return '2G';
  return 'Desconocida';
}

String signalAvailabilityMessage(RvSignalSample sample) =>
    switch (sample.availabilityReason) {
      'permission_denied' =>
        'No se autorizó el acceso a la información de red móvil.',
      'no_sim' => 'No hay una SIM activa.',
      'no_service' => 'La red móvil está sin servicio.',
      'timeout' => 'La red móvil no respondió dentro del tiempo esperado.',
      'security_exception' =>
        'Android rechazó el acceso a la información de telefonía.',
      'api_error' || 'platform_exception' =>
        'Android no pudo consultar la información de telefonía.',
      'not_reported' => 'Android no proporcionó el nivel de señal.',
      _ => '',
    };

String transportTypeLabel(String? value) => switch (value) {
  'wifi' => 'Wi-Fi',
  'mobile' => 'Red móvil',
  'ethernet' => 'Ethernet',
  'none' => 'Sin conexión',
  _ => 'Otro',
};

String? manualCoordinateError(String? value, {required bool isLatitude}) {
  final parsed = double.tryParse((value ?? '').trim().replaceAll(',', '.'));
  if (parsed == null) return 'Captura un valor decimal válido.';
  final min = isLatitude ? -90 : -180;
  final max = isLatitude ? 90 : 180;
  if (parsed < min || parsed > max) {
    return isLatitude
        ? 'La latitud debe estar entre -90 y 90.'
        : 'La longitud debe estar entre -180 y 180.';
  }
  return null;
}

class RvStepOnePanel extends StatefulWidget {
  const RvStepOnePanel({
    required this.controller,
    this.navigationFieldId,
    this.targetKey,
    super.key,
  });
  final RvInspectionController controller;
  final String? navigationFieldId;
  final GlobalKey? targetKey;

  @override
  State<RvStepOnePanel> createState() => _RvStepOnePanelState();
}

class _RvStepOnePanelState extends State<RvStepOnePanel> {
  bool manual = false;
  final latitude = TextEditingController();
  final longitude = TextEditingController();
  final altitude = TextEditingController();
  final formKey = GlobalKey<FormState>();

  @override
  void dispose() {
    latitude.dispose();
    longitude.dispose();
    altitude.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final draft = widget.controller.draft!;
    return Column(
      key: const ValueKey('step-1-content'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionCard(
          key: const {'location', 'signal'}.contains(widget.navigationFieldId)
              ? widget.targetKey
              : null,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'UBICACIÓN Y CONECTIVIDAD',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                key: const ValueKey('capture-location-connectivity'),
                onPressed: widget.controller.busy || draft.isReadOnly
                    ? null
                    : widget.controller.captureLocationAndSignal,
                icon: widget.controller.busy
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.my_location),
                label: Text(
                  widget.controller.busy
                      ? 'Capturando…'
                      : draft.location != null || draft.signal != null
                      ? 'Actualizar ubicación y conectividad'
                      : 'Capturar ubicación y conectividad',
                ),
              ),
              if (draft.location != null) ...[
                const SizedBox(height: 16),
                RvLocationDetails(sample: draft.location!),
              ],
              if (draft.signal != null) ...[
                const SizedBox(height: 16),
                RvSignalDetails(sample: draft.signal!),
              ],
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: draft.isReadOnly
                    ? null
                    : () => setState(() => manual = !manual),
                icon: const Icon(Icons.edit_location_alt_outlined),
                label: const Text('Captura manual de coordenadas'),
              ),
              if (manual)
                Form(
                  key: formKey,
                  child: Column(
                    children: [
                      TextFormField(
                        key: const ValueKey('manual-latitude'),
                        controller: latitude,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                          signed: true,
                        ),
                        decoration: const InputDecoration(labelText: 'Latitud'),
                        validator: (value) =>
                            manualCoordinateError(value, isLatitude: true),
                      ),
                      TextFormField(
                        key: const ValueKey('manual-longitude'),
                        controller: longitude,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                          signed: true,
                        ),
                        decoration: const InputDecoration(
                          labelText: 'Longitud',
                        ),
                        validator: (value) =>
                            manualCoordinateError(value, isLatitude: false),
                      ),
                      TextFormField(
                        controller: altitude,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                          signed: true,
                        ),
                        decoration: const InputDecoration(
                          labelText: 'Altura opcional (m)',
                        ),
                      ),
                      const SizedBox(height: 12),
                      FilledButton(
                        onPressed: () async {
                          if (formKey.currentState?.validate() != true) return;
                          await widget.controller.saveManualLocation(
                            latitude: double.parse(
                              latitude.text.replaceAll(',', '.'),
                            ),
                            longitude: double.parse(
                              longitude.text.replaceAll(',', '.'),
                            ),
                            altitude: double.tryParse(
                              altitude.text.replaceAll(',', '.'),
                            ),
                          );
                          if (mounted) setState(() => manual = false);
                        },
                        child: const Text('Guardar coordenadas manuales'),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class RvLocationDetails extends StatelessWidget {
  const RvLocationDetails({required this.sample, super.key});
  final RvLocationSample sample;

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Detalles de ubicación',
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _detail('Latitud', sample.latitude.toStringAsFixed(6)),
        _detail('Longitud', sample.longitude.toStringAsFixed(6)),
        _detail(
          'Altura',
          sample.altitude == null
              ? 'No disponible'
              : '${sample.altitude!.toStringAsFixed(1)} m s. n. m.',
        ),
        _detail(
          'Precisión',
          sample.horizontalAccuracy == null
              ? 'No disponible'
              : '${sample.horizontalAccuracy!.toStringAsFixed(1)} m',
        ),
        _detail('Fecha y hora', '${sample.capturedAt.toLocal()}'),
        _detail(
          'Origen',
          sample.source == 'manual' ? 'captura manual' : 'GPS automático',
        ),
      ],
    ),
  );
}

class RvSignalDetails extends StatelessWidget {
  const RvSignalDetails({required this.sample, super.key});
  final RvSignalSample sample;

  @override
  Widget build(BuildContext context) {
    final percent = normalizedSignalPercent(sample);
    final quality = signalQualityLabel(percent);
    final color = percent == null
        ? AppColors.muted
        : percent <= 40
        ? AppColors.red
        : percent <= 60
        ? AppColors.orange
        : AppColors.green;
    return Semantics(
      label:
          'Calidad de señal ${percent == null ? 'no disponible' : '$percent por ciento, $quality'}',
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.signal_cellular_alt, color: color),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _detail(
                  'Compañía u operador',
                  sample.operatorName ??
                      (sample.availabilityReason == 'no_sim'
                          ? 'Sin SIM'
                          : 'No reportado'),
                ),
                _detail('Tecnología móvil', networkTechnologyLabel(sample)),
                _detail(
                  'Calidad relativa',
                  percent == null ? 'No disponible' : '$percent% · $quality',
                ),
                _detail(
                  'Conexión de datos',
                  transportTypeLabel(sample.transportType),
                ),
                if (sample.dbm != null)
                  _detail('Medición del módem', '${sample.dbm} dBm'),
                if (signalAvailabilityMessage(sample).isNotEmpty)
                  Text(
                    signalAvailabilityMessage(sample),
                    key: const ValueKey('telephony-availability-message'),
                  ),
                _detail('Fecha y hora', '${sample.capturedAt.toLocal()}'),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

Widget _detail(String label, String value) => Padding(
  padding: const EdgeInsets.only(bottom: 4),
  child: Text('$label: $value'),
);

class RvStepTwoPhotoPanel extends StatelessWidget {
  const RvStepTwoPhotoPanel({
    required this.controller,
    this.targetSlot,
    this.targetKey,
    super.key,
  });
  final RvInspectionController controller;
  final String? targetSlot;
  final GlobalKey? targetKey;

  @override
  Widget build(BuildContext context) {
    final draft = controller.draft!;
    return SectionCard(
      key: const ValueKey('step-2-photo-panel'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'FOTOGRAFÍAS OBLIGATORIAS',
            style: TextStyle(fontWeight: FontWeight.w800),
          ),
          for (final slot in requiredRvPhotoSlots)
            _PhotoSlot(
              key: slot == targetSlot ? targetKey : null,
              slot: slot,
              references: draft.photosFor(slot),
              readOnly: draft.isReadOnly,
              controller: controller,
            ),
        ],
      ),
    );
  }
}

class _PhotoSlot extends StatelessWidget {
  const _PhotoSlot({
    required this.slot,
    required this.references,
    required this.readOnly,
    required this.controller,
    super.key,
  });
  final String slot;
  final List<RvPhotoReference> references;
  final bool readOnly;
  final RvInspectionController controller;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          rvPhotoSlotLabels[slot]!,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        TextButton.icon(
          onPressed: references.isEmpty
              ? null
              : () => showDialog<void>(
                  context: context,
                  builder: (_) => _SlotGallery(
                    slot: slot,
                    references: references,
                    controller: controller,
                  ),
                ),
          icon: const Icon(Icons.photo_library_outlined),
          label: Text(rvPhotoCountLabel(references.length)),
        ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              onPressed: readOnly
                  ? null
                  : () => controller.addPhoto(slot, ImageSource.camera),
              icon: const Icon(Icons.camera_alt_outlined),
              label: const Text('Tomar fotografía'),
            ),
            OutlinedButton.icon(
              onPressed: readOnly
                  ? null
                  : () => controller.addPhoto(slot, ImageSource.gallery),
              icon: const Icon(Icons.collections_outlined),
              label: const Text('Elegir desde galería'),
            ),
          ],
        ),
      ],
    ),
  );
}

class _SlotGallery extends StatefulWidget {
  const _SlotGallery({
    required this.slot,
    required this.references,
    required this.controller,
  });
  final String slot;
  final List<RvPhotoReference> references;
  final RvInspectionController controller;

  @override
  State<_SlotGallery> createState() => _SlotGalleryState();
}

class _SlotGalleryState extends State<_SlotGallery> {
  InspectionPhoto? _photo(String id) {
    final raw = Hive.box<String>('inspection_photos_v1').get(id);
    if (raw == null) return null;
    try {
      return InspectionPhoto.fromJson(
        Map<String, dynamic>.from(jsonDecode(raw) as Map),
      );
    } on Object {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final references = widget.controller.draft!.photosFor(widget.slot);
    return AlertDialog(
      title: Text(rvPhotoSlotLabels[widget.slot]!),
      content: SizedBox(
        width: 420,
        child: references.isEmpty
            ? const Text('No hay fotografías en este rubro.')
            : ListView(
                shrinkWrap: true,
                children: [
                  for (final reference in references)
                    _GalleryPhoto(
                      reference: reference,
                      photo: _photo(reference.photoId),
                      onDelete: () async {
                        final confirmed = await showDialog<bool>(
                          context: context,
                          builder: (context) => AlertDialog(
                            title: const Text('Eliminar fotografía'),
                            content: Text(
                              reference.status == RvPhotoUploadStatus.verified
                                  ? 'La fotografía verificada se eliminará de forma lógica en la API.'
                                  : 'Se eliminará únicamente esta fotografía local.',
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(context, false),
                                child: const Text('Cancelar'),
                              ),
                              FilledButton(
                                onPressed: () => Navigator.pop(context, true),
                                child: const Text('Eliminar'),
                              ),
                            ],
                          ),
                        );
                        if (confirmed != true) return;
                        await widget.controller.removePhoto(
                          widget.slot,
                          reference.photoId,
                        );
                        if (mounted) setState(() {});
                      },
                    ),
                ],
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cerrar'),
        ),
      ],
    );
  }
}

class _GalleryPhoto extends StatelessWidget {
  const _GalleryPhoto({
    required this.reference,
    required this.photo,
    required this.onDelete,
  });
  final RvPhotoReference reference;
  final InspectionPhoto? photo;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) => ListTile(
    leading: photo != null
        ? GestureDetector(
            onTap: () => showDialog<void>(
              context: context,
              builder: (_) => Dialog(
                child: InteractiveViewer(
                  child: Image.file(File(photo!.localPath)),
                ),
              ),
            ),
            child: Image.file(
              File(photo!.thumbnailPath),
              width: 64,
              height: 64,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => const SizedBox.square(
                dimension: 64,
                child: Icon(Icons.broken_image_outlined),
              ),
            ),
          )
        : const SizedBox.square(
            dimension: 64,
            child: Icon(Icons.cloud_outlined),
          ),
    title: Text(
      photo == null ? 'Archivo remoto' : '${photo!.capturedAt.toLocal()}',
    ),
    subtitle: Text(reference.status.name),
    trailing: IconButton(
      tooltip: 'Eliminar fotografía',
      onPressed: onDelete,
      icon: const Icon(Icons.delete_outline),
    ),
  );
}
