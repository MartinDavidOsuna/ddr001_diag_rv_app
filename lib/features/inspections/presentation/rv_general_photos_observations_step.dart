import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'rv_inspection_controller.dart';

class RvGeneralPhotosAndObservationsStep extends StatelessWidget {
  const RvGeneralPhotosAndObservationsStep({
    required this.controller,
    super.key,
  });
  final RvInspectionController controller;

  @override
  Widget build(BuildContext context) {
    final draft = controller.draft!;
    final photos = draft.generalPhotos;
    return Semantics(
      label: 'Fotografías y observaciones generales, paso opcional',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Fotografías y observaciones generales',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 8),
          const Text(
            'Puedes agregar hasta cinco fotografías generales y observaciones adicionales. Este paso es opcional.',
          ),
          const SizedBox(height: 16),
          Text(
            '${photos.length} de 5',
            key: const ValueKey('general-photo-counter'),
          ),
          for (final photo in photos)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  children: [
                    ListTile(
                      leading: const Icon(Icons.photo_outlined),
                      title: Text(
                        'Fotografía general ${photo.order ?? photos.indexOf(photo) + 1}',
                      ),
                      subtitle: Text(photo.status.name),
                      trailing: IconButton(
                        tooltip: 'Eliminar fotografía general',
                        onPressed:
                            draft.editingMode.name == 'validatedComplements' &&
                                photo.serverPhotoId != null
                            ? null
                            : () => controller.removeGeneralPhoto(photo),
                        icon: const Icon(Icons.delete_outline),
                      ),
                    ),
                    TextFormField(
                      key: ValueKey(
                        'general-photo-description-${photo.photoId}',
                      ),
                      initialValue: photo.description,
                      maxLength: 300,
                      decoration: const InputDecoration(
                        labelText: 'Descripción de la fotografía (opcional)',
                      ),
                      onChanged: (value) => controller
                          .updateGeneralPhotoDescription(photo.photoId, value),
                    ),
                  ],
                ),
              ),
            ),
          FilledButton.tonalIcon(
            onPressed: photos.length >= 5
                ? null
                : () => controller.addGeneralPhoto(ImageSource.camera),
            icon: const Icon(Icons.add_a_photo_outlined),
            label: Text(
              photos.length >= 5
                  ? 'Límite de 5 fotografías alcanzado'
                  : 'Agregar fotografía',
            ),
          ),
          const SizedBox(height: 20),
          TextFormField(
            key: const ValueKey('general-observations'),
            initialValue: draft.generalObservations,
            minLines: 4,
            maxLines: 8,
            maxLength: 2000,
            decoration: const InputDecoration(
              labelText: 'Observaciones generales (opcional)',
              alignLabelWithHint: true,
            ),
            onChanged: controller.saveGeneralObservations,
          ),
        ],
      ),
    );
  }
}
