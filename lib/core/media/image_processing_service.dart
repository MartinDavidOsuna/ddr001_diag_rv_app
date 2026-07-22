import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter_image_compress/flutter_image_compress.dart';

class ProcessedImage {
  const ProcessedImage(this.file, this.width, this.height);
  final File file;
  final int width, height;
}

abstract interface class ImageProcessingService {
  Future<ProcessedImage> normalize(File source, String destination);
}

class FlutterImageCompressProcessingService implements ImageProcessingService {
  @override
  Future<ProcessedImage> normalize(File source, String destination) async {
    final result = await FlutterImageCompress.compressAndGetFile(
      source.path,
      destination,
      quality: 85,
      minWidth: 1080,
      minHeight: 1080,
      format: CompressFormat.jpeg,
      keepExif: false,
    );
    if (result == null) {
      throw StateError('No fue posible normalizar la imagen.');
    }
    final file = File(result.path);
    final bytes = await file.readAsBytes();
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    final width = frame.image.width, height = frame.image.height;
    frame.image.dispose();
    codec.dispose();
    if (width < 640 || height < 480) {
      throw StateError('La imagen no alcanza 640 × 480.');
    }
    return ProcessedImage(file, width, height);
  }
}
