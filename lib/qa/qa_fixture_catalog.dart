import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:hive_ce/hive.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

enum QaFixtureState {
  normal,
  inactiveDraft,
  inactiveClosed,
  conflict,
  legacy,
  controlledCorrupt,
}

class QaFixtureRecord {
  const QaFixtureRecord({
    required this.id,
    required this.hydrantId,
    required this.account,
    required this.state,
    required this.latitude,
    required this.longitude,
    this.photoId,
    this.photoPath,
    this.photoSha256,
  });

  final String id;
  final String hydrantId;
  final String account;
  final QaFixtureState state;
  final double latitude;
  final double longitude;
  final String? photoId;
  final String? photoPath;
  final String? photoSha256;

  Map<String, dynamic> toJson() => {
    'id': id,
    'hydrantId': hydrantId,
    'account': account,
    'state': state.name,
    'latitude': latitude,
    'longitude': longitude,
    'photoId': photoId,
    'photoPath': photoPath,
    'photoSha256': photoSha256,
    'fixture': true,
    'syncAllowed': false,
  };

  factory QaFixtureRecord.fromJson(Map<String, dynamic> json) =>
      QaFixtureRecord(
        id: json['id'] as String,
        hydrantId: json['hydrantId'] as String,
        account: json['account'] as String,
        state: QaFixtureState.values.byName(json['state'] as String),
        latitude: (json['latitude'] as num).toDouble(),
        longitude: (json['longitude'] as num).toDouble(),
        photoId: json['photoId'] as String?,
        photoPath: json['photoPath'] as String?,
        photoSha256: json['photoSha256'] as String?,
      );
}

class QaFixtureCatalog {
  QaFixtureCatalog(
    this._box,
    this._corruptBox, {
    Future<Directory> Function()? documentsDirectory,
  }) : _documentsDirectory =
           documentsDirectory ?? getApplicationDocumentsDirectory;

  static const boxName = 'qa_fixture_catalog_v1';
  static const corruptBoxName = 'qa_controlled_corrupt_documents_v1';
  static const fixtureVersion = 1;
  static const syntheticPhotoId = 'qa-photo-synthetic-0001';
  static const _seedMarker = 'qa-fixtures-v1';

  final Box<String> _box;
  final Box<String> _corruptBox;
  final Future<Directory> Function() _documentsDirectory;

  static Future<QaFixtureCatalog> open({
    Future<Directory> Function()? documentsDirectory,
  }) async {
    final box = await Hive.openBox<String>(boxName);
    final corrupt = await Hive.openBox<String>(corruptBoxName);
    final catalog = QaFixtureCatalog(
      box,
      corrupt,
      documentsDirectory: documentsDirectory,
    );
    await catalog.seedIfNeeded();
    return catalog;
  }

  Future<void> seedIfNeeded() async {
    if (_box.get('seedMarker') == _seedMarker) return;
    final root = Directory(
      p.join((await _documentsDirectory()).path, 'qa_fixtures_v1'),
    );
    await root.create(recursive: true);
    final photo = File(p.join(root.path, '$syntheticPhotoId.png'));
    if (!await photo.exists()) {
      await photo.writeAsBytes(_syntheticPng, flush: true);
    }
    final photoBytes = await photo.readAsBytes();
    final photoHash = sha256.convert(photoBytes).toString();
    final fixtures = <QaFixtureRecord>[
      const QaFixtureRecord(
        id: 'qa-review-normal-0001',
        hydrantId: 'qa-hydrant-normal-0001',
        account: 'QA-0001',
        state: QaFixtureState.normal,
        latitude: 1.0,
        longitude: -1.0,
      ),
      QaFixtureRecord(
        id: 'qa-review-inactive-draft-0001',
        hydrantId: 'qa-hydrant-draft-0001',
        account: 'QA-0002',
        state: QaFixtureState.inactiveDraft,
        latitude: 1.1,
        longitude: -1.1,
        photoId: syntheticPhotoId,
        photoPath: photo.path,
        photoSha256: photoHash,
      ),
      QaFixtureRecord(
        id: 'qa-review-inactive-closed-0001',
        hydrantId: 'qa-hydrant-inactive-0001',
        account: 'QA-0003',
        state: QaFixtureState.inactiveClosed,
        latitude: 1.2,
        longitude: -1.2,
        photoId: syntheticPhotoId,
        photoPath: photo.path,
        photoSha256: photoHash,
      ),
      const QaFixtureRecord(
        id: 'qa-review-conflict-0001',
        hydrantId: 'qa-hydrant-conflict-0001',
        account: 'QA-0004',
        state: QaFixtureState.conflict,
        latitude: 1.3,
        longitude: -1.3,
      ),
      const QaFixtureRecord(
        id: 'qa-review-legacy-0001',
        hydrantId: 'qa-hydrant-legacy-0001',
        account: 'QA-0005',
        state: QaFixtureState.legacy,
        latitude: 1.4,
        longitude: -1.4,
      ),
      const QaFixtureRecord(
        id: 'qa-review-corrupt-0001',
        hydrantId: 'qa-hydrant-corrupt-0001',
        account: 'QA-0006',
        state: QaFixtureState.controlledCorrupt,
        latitude: 1.5,
        longitude: -1.5,
      ),
    ];
    for (final fixture in fixtures) {
      await _box.put(fixture.id, jsonEncode(fixture.toJson()));
    }
    await _box.put(
      'qa-review-legacy-raw-0001',
      jsonEncode({
        'id': 'qa-review-legacy-raw-0001',
        'account': 'QA-LEGACY',
        'fixture': true,
      }),
    );
    await _corruptBox.put(
      'qa-review-corrupt-raw-0001',
      '{controlled-corrupt-fixture',
    );
    await _box.put('seedMarker', _seedMarker);
  }

  List<QaFixtureRecord> records() {
    final values = <QaFixtureRecord>[];
    for (final entry in _box.toMap().entries) {
      if (!entry.key.toString().startsWith('qa-review-') ||
          entry.key.toString().contains('-raw-')) {
        continue;
      }
      try {
        values.add(
          QaFixtureRecord.fromJson(
            Map<String, dynamic>.from(jsonDecode(entry.value) as Map),
          ),
        );
      } on Object {
        continue;
      }
    }
    values.sort((left, right) => left.id.compareTo(right.id));
    return List.unmodifiable(values);
  }

  int get controlledCorruptCount => _corruptBox.length;

  /// Replaces only the supported synthetic fixture while retaining its ID.
  Future<String> replaceSyntheticPhoto() async {
    final recordsWithPhoto = records()
        .where((record) => record.photoId == syntheticPhotoId)
        .toList();
    if (recordsWithPhoto.isEmpty || recordsWithPhoto.first.photoPath == null) {
      throw StateError('No existe la foto sintética soportada.');
    }
    final file = File(recordsWithPhoto.first.photoPath!);
    final current = await file.readAsBytes();
    final replacement = Uint8List.fromList([
      ..._syntheticPng,
      if (current.length == _syntheticPng.length) 0x00,
    ]);
    await file.writeAsBytes(replacement, flush: true);
    final hash = sha256.convert(replacement).toString();
    for (final record in recordsWithPhoto) {
      await _box.put(
        record.id,
        jsonEncode(
          QaFixtureRecord(
            id: record.id,
            hydrantId: record.hydrantId,
            account: record.account,
            state: record.state,
            latitude: record.latitude,
            longitude: record.longitude,
            photoId: record.photoId,
            photoPath: record.photoPath,
            photoSha256: hash,
          ).toJson(),
        ),
      );
    }
    return hash;
  }

  Future<void> resetSyntheticFixtures() async {
    final paths = records()
        .map((record) => record.photoPath)
        .whereType<String>()
        .toSet();
    final catalogKeys = _box.keys
        .where((key) => key == 'seedMarker' || '$key'.startsWith('qa-review-'))
        .toList();
    await _box.deleteAll(catalogKeys);
    await _corruptBox.deleteAll(_corruptBox.keys.toList());
    for (final path in paths) {
      final file = File(path);
      if (p.basename(file.parent.path) == 'qa_fixtures_v1' &&
          p.basename(path).startsWith('qa-photo-') &&
          await file.exists()) {
        await file.delete();
      }
    }
    await seedIfNeeded();
  }

  static Uint8List get _syntheticPng => base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
  );
}
