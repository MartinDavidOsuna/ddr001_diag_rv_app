import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:hive_ce/hive.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Writes a read-only snapshot before startup recovery mutates any projection.
/// The evidence lives in external app storage so field support can retrieve it
/// with ADB even when the production package is not debuggable.
class UpgradeCertificationEvidence {
  const UpgradeCertificationEvidence();

  static const _boxNames = <String>[
    'visual_inspections_v1',
    'active_inspection_index_v1',
    'inspection_photos_v1',
    'media_sync_queue',
    'media_work_queue_v1',
    'sync_queue',
    'operation_journal_v1',
    'rv_recovery_v1',
    'rv_recovery_snapshots_v1',
    'quarantine_documents_v1',
  ];

  Future<File> capturePreRecovery({
    PackageInfo? packageInfo,
    Directory? directory,
    DateTime? now,
  }) async {
    final info = packageInfo ?? await PackageInfo.fromPlatform();
    final generatedAt = (now ?? DateTime.now()).toUtc();
    final target =
        directory ??
        await getExternalStorageDirectory() ??
        Directory.systemTemp;
    final boxes = <String, dynamic>{};
    for (final name in _boxNames) {
      if (!Hive.isBoxOpen(name)) continue;
      final box = Hive.box<String>(name);
      boxes[name] = {
        'recordCount': box.length,
        'entries': [
          for (final entry in box.toMap().entries)
            _entry('${entry.key}', entry.value),
        ],
      };
    }
    final photos = Hive.isBoxOpen('inspection_photos_v1')
        ? _physicalPhotos(Hive.box<String>('inspection_photos_v1'))
        : const <Map<String, dynamic>>[];
    final document = {
      'evidenceType': 'PRE_RECOVERY',
      'schemaVersion': 1,
      'generatedAtUtc': generatedAt.toIso8601String(),
      'app': {
        'packageName': info.packageName,
        'versionName': info.version,
        'versionCode': info.buildNumber,
        'gitSha': const String.fromEnvironment(
          'GIT_SHA',
          defaultValue: 'development-build-without-release-metadata',
        ),
        'buildDateUtc': const String.fromEnvironment(
          'BUILD_DATE_UTC',
          defaultValue: 'development-build-without-release-metadata',
        ),
      },
      'boxes': boxes,
      'physicalPhotos': photos,
      'summary': {
        'boxCount': boxes.length,
        'physicalPhotoDocuments': photos.length,
        'physicalPhotoFilesPresent': photos
            .where((row) => row['exists'] == true)
            .length,
        'physicalPhotoFilesMissing': photos
            .where((row) => row['exists'] != true)
            .length,
      },
    };
    final stamp = generatedAt
        .toIso8601String()
        .replaceAll(RegExp(r'[-:]'), '')
        .replaceAll(RegExp(r'[^0-9TZ]'), '');
    final file = File(
      p.join(target.path, 'DDR001_RV_CERT_PRE_RECOVERY_$stamp.json'),
    );
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(document),
      flush: true,
    );
    return file;
  }

  static Map<String, dynamic> _entry(String key, String raw) {
    Object? decoded;
    String? decodeError;
    try {
      decoded = jsonDecode(raw);
    } on Object catch (error) {
      decodeError = error.runtimeType.toString();
    }
    return {
      'key': key,
      'rawUtf8Bytes': utf8.encode(raw).length,
      'rawSha256': sha256.convert(utf8.encode(raw)).toString(),
      'readableJson': decodeError == null,
      'decodeError': ?decodeError,
      'identity': ?decoded is Map
          ? _identity(Map<String, dynamic>.from(decoded))
          : null,
    };
  }

  static Map<String, dynamic> _identity(Map<String, dynamic> value) {
    const keys = <String>[
      'id',
      'photoId',
      'inspectionId',
      'clientInspectionId',
      'serverInspectionId',
      'accountNumber',
      'slotCode',
      'status',
      'state',
      'sha256',
      'fileSize',
      'localPath',
    ];
    return {
      for (final key in keys)
        if (value.containsKey(key)) key: value[key],
    };
  }

  static List<Map<String, dynamic>> _physicalPhotos(Box<String> box) {
    final result = <Map<String, dynamic>>[];
    for (final entry in box.toMap().entries) {
      try {
        final value = Map<String, dynamic>.from(jsonDecode(entry.value) as Map);
        final path = value['localPath']?.toString();
        final file = path == null ? null : File(path);
        final exists = file?.existsSync() == true;
        result.add({
          'key': '${entry.key}',
          ..._identity(value),
          'exists': exists,
          'actualFileSize': exists ? file!.lengthSync() : null,
          'actualFileSha256': exists
              ? sha256.convert(file!.readAsBytesSync()).toString()
              : null,
        });
      } on Object catch (error) {
        result.add({
          'key': '${entry.key}',
          'readable': false,
          'errorType': error.runtimeType.toString(),
        });
      }
    }
    return result;
  }
}
