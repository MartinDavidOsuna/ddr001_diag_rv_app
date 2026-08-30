import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:ddr001diag/core/media/image_processing_service.dart';
import 'package:ddr001diag/core/media/reliable_photo_service.dart';
import 'package:ddr001diag/domain/integrity/operation_journal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:image_picker/image_picker.dart';

void main() {
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('reliable-photo-');
    Hive.init(root.path);
    await Hive.openBox<String>('operation_journal_v1');
    await Hive.openBox<String>('inspection_photos_v1');
    await Hive.openBox<String>('media_work_queue_v1');
  });

  tearDown(() async {
    await Hive.close();
    await root.delete(recursive: true);
  });

  test(
    'cancelar cámara no procesa ni deja una transacción pendiente',
    () async {
      final processor = _Processor();
      final picker = _Picker(picks: [null]);
      final result = await _service(root, picker, processor: processor).acquire(
        pickerSource: ImageSource.camera,
        hydrantId: 'hydrant-1',
        inspectionId: 'inspection-1',
        category: 'top',
        userId: 'user-1',
        userName: 'User',
        brigadeId: 'brigade-1',
        deviceId: 'device-1',
      );

      expect(result, isNull);
      expect(processor.calls, 0);
      expect(_journals().single.status, JournalStatus.committed);
    },
  );

  test(
    'capturas consecutivas se procesan una por una sin duplicar IDs',
    () async {
      final first = await _jpeg(root, 'first.jpg');
      final second = await _jpeg(root, 'second.jpg');
      final picker = _Picker(picks: [XFile(first.path), XFile(second.path)]);
      final service = _service(root, picker);

      final a = await _capture(service);
      await service.markDraftLinkedAndCommitted(a!.id);
      final b = await _capture(service);
      await service.markDraftLinkedAndCommitted(b!.id);

      expect(a.id, isNot(b.id));
      expect(picker.maximumConcurrentCalls, 1);
      expect(Hive.box<String>('inspection_photos_v1').length, 2);
      expect(Hive.box<String>('media_work_queue_v1').length, 2);
      expect(await File(a.localPath).exists(), isTrue);
      expect(await File(b.localPath).exists(), isTrue);
      expect(
        _journals().every((e) => e.status == JournalStatus.committed),
        isTrue,
      );
    },
  );

  for (final count in [5, 10]) {
    test(
      '$count capturas consecutivas conservan hashes, archivos y exclusión mutua',
      () async {
        final sources = <XFile>[];
        for (var index = 0; index < count; index++) {
          sources.add(XFile((await _jpeg(root, 'source-$index.jpg')).path));
        }
        final picker = _Picker(picks: sources);
        final service = _service(root, picker);
        final ids = <String>{};
        for (var index = 0; index < count; index++) {
          final photo = await _capture(service);
          expect(photo, isNotNull);
          ids.add(photo!.id);
          expect(photo.sha256, isNotEmpty);
          expect(photo.receivedSha256, isNotEmpty);
          expect(await File(photo.localPath).exists(), isTrue);
          await service.markDraftLinkedAndCommitted(photo.id);
        }

        expect(ids, hasLength(count));
        expect(picker.maximumConcurrentCalls, 1);
        expect(Hive.box<String>('inspection_photos_v1'), hasLength(count));
        expect(Hive.box<String>('media_work_queue_v1'), hasLength(count));
        expect(
          _journals().every((entry) => entry.status == JournalStatus.committed),
          isTrue,
        );
      },
    );
  }

  test(
    'bloquea una segunda cámara mientras la primera sigue abierta',
    () async {
      final gate = Completer<XFile?>();
      final picker = _Picker(gate: gate);
      final service = _service(root, picker);
      final first = _capture(service);

      await Future<void>.delayed(Duration.zero);
      await expectLater(_capture(service), throwsStateError);
      gate.complete(null);
      expect(await first, isNull);
      expect(picker.maximumConcurrentCalls, 1);
    },
  );

  test('restaura el resultado de cámara después de process death', () async {
    final source = await _jpeg(root, 'lost.jpg');
    final evidence = Directory('${root.path}/evidence/hydrant-1/inspection-1');
    await evidence.create(recursive: true);
    final prepared = OperationJournalEntry(
      operationId: 'lost-photo-id',
      operationType: JournalOperationType.capturePhoto,
      entityIds: const [
        'camera-pending-v1',
        'inspection-1',
        'hydrant-1',
        'top',
        'camera',
      ],
      documentWrites: const ['lost-photo-id'],
      fileWrites: [
        '${evidence.path}/lost-photo-id.jpg',
        '${evidence.path}/lost-photo-id_thumb.jpg',
      ],
      queueWrites: const ['lost-photo-id'],
      preparedAt: DateTime.utc(2026, 8, 28),
      actor: 'user-1',
      deviceId: 'device-1',
      correlationId: 'lost-photo-id',
    );
    await Hive.box<String>('operation_journal_v1').put(
      prepared.operationId,
      _journalJson(
        prepared.advance(
          JournalStatus.needsRecovery,
          error: pendingExternalCameraRecoveryError,
        ),
      ),
    );
    final picker = _Picker(
      picks: const [],
      lost: LostDataResponse(
        file: XFile(source.path),
        type: RetrieveType.image,
      ),
    );

    final photo = await _capture(_service(root, picker));

    expect(photo!.id, 'lost-photo-id');
    expect(picker.pickCalls, 0);
    expect(picker.retrieveCalls, 1);
    expect(await File(photo.localPath).exists(), isTrue);
  });

  test(
    'fallo de normalización conserva fuente y journal recuperable',
    () async {
      final source = await _jpeg(root, 'source.jpg');
      final service = _service(
        root,
        _Picker(picks: [XFile(source.path)]),
        processor: _Processor(fail: true),
      );

      await expectLater(_capture(service), throwsStateError);

      expect(await source.exists(), isTrue);
      expect(_journals().single.status, JournalStatus.needsRecovery);
      expect(Hive.box<String>('inspection_photos_v1'), isEmpty);
    },
  );
}

ReliablePhotoService _service(
  Directory root,
  _Picker picker, {
  _Processor? processor,
}) => ReliablePhotoService(
  picker: picker,
  processor: processor ?? _Processor(),
  thumbnailService: _Thumbnail(),
  documentsDirectory: () async => root,
  supportDirectory: () async => root,
);

Future<dynamic> _capture(ReliablePhotoService service) => service.acquire(
  pickerSource: ImageSource.camera,
  hydrantId: 'hydrant-1',
  inspectionId: 'inspection-1',
  category: 'top',
  userId: 'user-1',
  userName: 'User',
  brigadeId: 'brigade-1',
  deviceId: 'device-1',
);

Future<File> _jpeg(Directory root, String name) async {
  final file = File('${root.path}/$name');
  await file.writeAsBytes([
    0xff,
    0xd8,
    ...List<int>.filled(1024, 7),
    0xff,
    0xd9,
  ]);
  return file;
}

class _Picker implements PhotoPicker {
  _Picker({this.picks = const [], this.gate, LostDataResponse? lost})
    : lost = lost ?? LostDataResponse.empty();

  final List<XFile?> picks;
  final Completer<XFile?>? gate;
  final LostDataResponse lost;
  int pickCalls = 0;
  int retrieveCalls = 0;
  int _active = 0;
  int maximumConcurrentCalls = 0;

  @override
  Future<XFile?> pickImage({
    required ImageSource source,
    String? captureId,
    String? durablePath,
  }) async {
    pickCalls++;
    _active++;
    maximumConcurrentCalls = _active > maximumConcurrentCalls
        ? _active
        : maximumConcurrentCalls;
    try {
      if (gate != null) return await gate!.future;
      return picks[pickCalls - 1];
    } finally {
      _active--;
    }
  }

  @override
  Future<LostDataResponse> retrieveLostData() async {
    retrieveCalls++;
    return lost;
  }

  @override
  Future<DurableCameraOutcome> durableCameraOutcome(String captureId) async =>
      DurableCameraOutcome.unknown;

  @override
  Future<void> clearDurableCameraOutcome(String captureId) async {}
}

class _Processor implements ImageProcessingService {
  _Processor({this.fail = false});
  final bool fail;
  int calls = 0;

  @override
  Future<ProcessedImage> normalize(File source, String destination) async {
    calls++;
    if (fail) throw StateError('compression failed');
    final output = await source.copy(destination);
    return ProcessedImage(output, 1920, 1080);
  }
}

class _Thumbnail implements PhotoThumbnailService {
  @override
  Future<File?> create(File source, String destination) =>
      source.copy(destination);
}

List<OperationJournalEntry> _journals() =>
    Hive.box<String>('operation_journal_v1').values
        .map(
          (raw) => OperationJournalEntry.fromJson(
            Map<String, dynamic>.from(jsonDecode(raw) as Map),
          ),
        )
        .toList();

String _journalJson(OperationJournalEntry entry) => jsonEncode(entry.toJson());
