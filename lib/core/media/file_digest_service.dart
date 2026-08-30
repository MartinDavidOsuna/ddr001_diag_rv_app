import 'dart:io';

import 'package:crypto/crypto.dart';

abstract interface class FileDigestService {
  Future<String> sha256Of(File file);
}

class StreamingFileDigestService implements FileDigestService {
  const StreamingFileDigestService();

  @override
  Future<String> sha256Of(File file) async =>
      (await sha256.bind(file.openRead()).first).toString();
}
