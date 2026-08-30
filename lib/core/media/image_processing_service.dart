import 'dart:io';

import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:image_size_getter/file_input.dart';
import 'package:image_size_getter/image_size_getter.dart';

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
    final sourceSize = await ImageSizeGetter.getSizeResultAsync(
      AsyncImageInput.input(FileInput(source)),
    );
    final landscape = sourceSize.size.width >= sourceSize.size.height;
    final result = await FlutterImageCompress.compressAndGetFile(
      source.path,
      destination,
      quality: 87,
      minWidth: landscape ? 1920 : 1080,
      minHeight: landscape ? 1080 : 1920,
      format: CompressFormat.jpeg,
      keepExif: false,
      autoCorrectionAngle: true,
    );
    if (result == null) {
      throw StateError('No fue posible normalizar la imagen.');
    }
    final file = File(result.path);
    // Reads only image metadata. Decoding a full camera bitmap here used to
    // create a large allocation on the UI isolate immediately after picker
    // return.
    final size = await ImageSizeGetter.getSizeResultAsync(
      AsyncImageInput.input(FileInput(file)),
    );
    final width = size.size.width, height = size.size.height;
    if (width < 640 || height < 480) {
      throw StateError('La imagen no alcanza 640 × 480.');
    }
    return ProcessedImage(file, width, height);
  }
}
