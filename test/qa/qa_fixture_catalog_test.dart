import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:ddr001diag/qa/qa_fixture_catalog.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';

void main() {
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('ddr001-qa-fixtures-');
    Hive.init(root.path);
  });

  tearDown(() async {
    await Hive.close();
    await root.delete(recursive: true);
  });

  test('siembra únicamente fixtures sintéticos deterministas', () async {
    final catalog = await QaFixtureCatalog.open(
      documentsDirectory: () async => root,
    );
    final records = catalog.records();

    expect(records, hasLength(6));
    expect(records.every((record) => record.id.startsWith('qa-')), isTrue);
    expect(
      records.every((record) => record.hydrantId.startsWith('qa-')),
      isTrue,
    );
    expect(records.every((record) => record.account.startsWith('QA-')), isTrue);
    expect(
      records.map((record) => record.state).toSet(),
      QaFixtureState.values.toSet(),
    );
    expect(catalog.controlledCorruptCount, 1);
  });

  test('foto sintética tiene hash verificable y queda en raíz QA', () async {
    final catalog = await QaFixtureCatalog.open(
      documentsDirectory: () async => root,
    );
    final photoRecords = catalog.records().where(
      (record) => record.photoId == QaFixtureCatalog.syntheticPhotoId,
    );

    expect(photoRecords, isNotEmpty);
    for (final fixture in photoRecords) {
      final file = File(fixture.photoPath!);
      expect(await file.exists(), isTrue);
      expect(file.path, startsWith(root.path));
      expect(
        sha256.convert(await file.readAsBytes()).toString(),
        fixture.photoSha256,
      );
    }
  });

  test('seed es idempotente y conserva documentos controlados', () async {
    final first = await QaFixtureCatalog.open(
      documentsDirectory: () async => root,
    );
    final initial = first
        .records()
        .map((record) => jsonEncode(record.toJson()))
        .toList();

    await first.seedIfNeeded();
    final second = first
        .records()
        .map((record) => jsonEncode(record.toJson()))
        .toList();

    expect(second, initial);
    expect(first.controlledCorruptCount, 1);
  });

  test('reemplazo soportado conserva photoId y actualiza hash', () async {
    final catalog = await QaFixtureCatalog.open(
      documentsDirectory: () async => root,
    );
    final before = catalog.records().firstWhere(
      (record) => record.photoId == QaFixtureCatalog.syntheticPhotoId,
    );

    final nextHash = await catalog.replaceSyntheticPhoto();
    final after = catalog.records().firstWhere(
      (record) => record.id == before.id,
    );

    expect(after.photoId, before.photoId);
    expect(after.photoPath, before.photoPath);
    expect(nextHash, isNot(before.photoSha256));
    expect(after.photoSha256, nextHash);
    expect(
      sha256.convert(await File(after.photoPath!).readAsBytes()).toString(),
      nextHash,
    );
  });

  test('reset elimina y vuelve a sembrar únicamente catálogo QA', () async {
    final catalog = await QaFixtureCatalog.open(
      documentsDirectory: () async => root,
    );
    await Hive.openBox<String>('unrelated_box');
    await Hive.box<String>('unrelated_box').put('protected', 'unchanged');
    final original = catalog.records().map((record) => record.id).toList();
    await catalog.replaceSyntheticPhoto();

    await catalog.resetSyntheticFixtures();

    expect(catalog.records().map((record) => record.id), original);
    expect(catalog.controlledCorruptCount, 1);
    expect(Hive.box<String>('unrelated_box').get('protected'), 'unchanged');
  });
}
