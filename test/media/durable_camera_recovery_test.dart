import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:ddr001diag/core/media/image_processing_service.dart';
import 'package:ddr001diag/core/media/reliable_photo_service.dart';
import 'package:ddr001diag/data/local/operation_journal_repository.dart';
import 'package:ddr001diag/domain/integrity/operation_journal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:image_picker/image_picker.dart';

void main() {
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('durable-camera-');
    Hive.init(root.path);
    for (final box in const [
      'operation_journal_v1',
      'inspection_photos_v1',
      'media_work_queue_v1',
    ]) {
      await Hive.openBox<String>(box);
    }
  });

  tearDown(() async {
    await Hive.close();
    await root.delete(recursive: true);
  });

  test(
    'journal y destino durable existen antes de abandonar Flutter',
    () async {
      final picker = _DurablePicker(
        onCapture: (id, path) async {
          final journal = _journal(id);
          expect(journal.status, JournalStatus.prepared);
          expect(journal.entityIds.first, 'camera-pending-v2');
          expect(journal.fileWrites, contains(path));
          expect(File(path).parent.path, contains('camera-capture-staging'));
          return null;
        },
      );

      expect(await _capture(_service(root, picker)), isNull);
      expect(_journals().single.status, JournalStatus.committed);
    },
  );

  test(
    'process death después de escritura converge exactamente una vez',
    () async {
      final firstPicker = _DurablePicker(
        onCapture: (id, path) async {
          await _writeJpeg(File(path));
          throw StateError('simulated-process-death');
        },
      );
      await expectLater(
        _capture(_service(root, firstPicker)),
        throwsA(isA<StateError>()),
      );
      final id = _journals().single.operationId;
      expect(_journals().single.status, JournalStatus.needsRecovery);

      final recoveringPicker = _DurablePicker(
        outcomes: {id: DurableCameraOutcome.success},
      );
      final firstRecovery = await _service(root, recoveringPicker)
          .recoverPendingForInspection(
            inspectionId: 'inspection-1',
            userId: 'user-1',
            userName: 'User',
            brigadeId: 'brigade-1',
            deviceId: 'device-1',
            localScopeNamespace: 'qa/scope',
          );
      expect(firstRecovery, hasLength(1));
      expect(firstRecovery.single.id, id);
      expect(Hive.box<String>('inspection_photos_v1'), hasLength(1));

      await _service(root, recoveringPicker).markDraftLinkedAndCommitted(id);
      final secondRecovery = await _service(root, recoveringPicker)
          .recoverPendingForInspection(
            inspectionId: 'inspection-1',
            userId: 'user-1',
            userName: 'User',
            brigadeId: 'brigade-1',
            deviceId: 'device-1',
            localScopeNamespace: 'qa/scope',
          );
      expect(secondRecovery, isEmpty);
      expect(Hive.box<String>('inspection_photos_v1'), hasLength(1));
      expect(_journal(id).status, JournalStatus.committed);
      expect(recoveringPicker.cleared, contains(id));
    },
  );

  test(
    'recreación antes de archivo listo conserva journal y recupera después',
    () async {
      final picker = _DurablePicker(
        onCapture: (id, path) async {
          throw StateError('simulated-process-death-before-write');
        },
      );
      await expectLater(_capture(_service(root, picker)), throwsStateError);
      final entry = _journals().single;
      final recoveryPicker = _DurablePicker(
        outcomes: {entry.operationId: DurableCameraOutcome.launched},
      );

      expect(await _recover(root, recoveryPicker), isEmpty);
      expect(_journal(entry.operationId).status, JournalStatus.needsRecovery);
      await _writeJpeg(_durableFile(entry));
      recoveryPicker.outcomes[entry.operationId] = DurableCameraOutcome.success;

      expect(await _recover(root, recoveryPicker), hasLength(1));
      expect(Hive.box<String>('inspection_photos_v1'), hasLength(1));
    },
  );

  test('bytes visibles no se aceptan antes de RESULT_OK durable', () async {
    final picker = _DurablePicker(
      onCapture: (id, path) async {
        await _writeJpeg(File(path));
        throw StateError('process-death-before-result');
      },
    );
    await expectLater(_capture(_service(root, picker)), throwsStateError);
    final id = _journals().single.operationId;
    picker.outcomes[id] = DurableCameraOutcome.launched;

    expect(await _recover(root, picker), isEmpty);
    expect(Hive.box<String>('inspection_photos_v1'), isEmpty);
    expect(_journal(id).status, JournalStatus.needsRecovery);

    picker.outcomes[id] = DurableCameraOutcome.success;
    expect(await _recover(root, picker), hasLength(1));
  });

  test('cancelación cierra journal sin evidencia', () async {
    final picker = _DurablePicker(onCapture: (id, path) async => null);
    expect(await _capture(_service(root, picker)), isNull);
    expect(Hive.box<String>('inspection_photos_v1'), isEmpty);
    expect(Hive.box<String>('media_work_queue_v1'), isEmpty);
    expect(_journals().single.status, JournalStatus.committed);
  });

  for (final invalid in ['missing', 'zero', 'corrupt']) {
    test('$invalid no se acepta como evidencia', () async {
      final picker = _DurablePicker(
        onCapture: (id, path) async {
          final file = File(path);
          if (invalid == 'zero') await file.create(recursive: true);
          if (invalid == 'corrupt') {
            await file.writeAsBytes(List<int>.filled(64, 7), flush: true);
          }
          throw StateError('simulated-process-death');
        },
      );
      await expectLater(_capture(_service(root, picker)), throwsStateError);
      final entry = _journals().single;
      picker.outcomes[entry.operationId] = DurableCameraOutcome.success;

      if (invalid == 'corrupt') {
        await expectLater(_recover(root, picker), throwsStateError);
      } else {
        await expectLater(_recover(root, picker), throwsStateError);
      }
      expect(Hive.box<String>('inspection_photos_v1'), isEmpty);
      expect(_journal(entry.operationId).status, JournalStatus.needsRecovery);
    });
  }

  test('resultado normal seguido de recovery no duplica documento', () async {
    final picker = _DurablePicker(
      onCapture: (id, path) async {
        await _writeJpeg(File(path));
        return XFile(path);
      },
    );
    final photo = await _capture(_service(root, picker));
    expect(photo, isNotNull);
    expect((await _recover(root, picker)).map((item) => item.id), [photo!.id]);
    expect(Hive.box<String>('inspection_photos_v1'), hasLength(1));
    await _service(root, picker).markDraftLinkedAndCommitted(photo.id);
    expect(await _recover(root, picker), isEmpty);
  });

  test(
    'scope, usuario y revisión distintos no recuperan captura ajena',
    () async {
      final picker = _DurablePicker(
        onCapture: (id, path) async {
          await _writeJpeg(File(path));
          throw StateError('process-death');
        },
      );
      await expectLater(_capture(_service(root, picker)), throwsStateError);

      expect(
        await _service(root, picker).recoverPendingForInspection(
          inspectionId: 'inspection-2',
          userId: 'user-1',
          userName: 'User',
          brigadeId: 'brigade-1',
          deviceId: 'device-1',
          localScopeNamespace: 'qa/scope',
        ),
        isEmpty,
      );
      expect(
        await _service(root, picker).recoverPendingForInspection(
          inspectionId: 'inspection-1',
          userId: 'user-2',
          userName: 'Other',
          brigadeId: 'brigade-2',
          deviceId: 'device-1',
          localScopeNamespace: 'qa/scope',
        ),
        isEmpty,
      );
      expect(
        await _service(root, picker).recoverPendingForInspection(
          inspectionId: 'inspection-1',
          userId: 'user-1',
          userName: 'User',
          brigadeId: 'brigade-1',
          deviceId: 'device-1',
          localScopeNamespace: 'other/scope',
        ),
        isEmpty,
      );
      expect(Hive.box<String>('inspection_photos_v1'), isEmpty);
    },
  );

  test('cleanup conserva intento recuperable y elimina al commit', () async {
    final picker = _DurablePicker(
      onCapture: (id, path) async {
        await _writeJpeg(File(path));
        throw StateError('process-death');
      },
    );
    await expectLater(_capture(_service(root, picker)), throwsStateError);
    final entry = _journals().single;
    final source = _durableFile(entry);
    picker.outcomes[entry.operationId] = DurableCameraOutcome.success;

    await _service(root, picker).cleanupCommittedCaptureSources();
    expect(await source.exists(), isTrue);

    expect(await _recover(root, picker), hasLength(1));
    await _service(root, picker).markDraftLinkedAndCommitted(entry.operationId);
    expect(await source.exists(), isFalse);
    expect(_journal(entry.operationId).status, JournalStatus.committed);
  });

  test('cancelación recuperada es idempotente y no crea huérfanos', () async {
    final picker = _DurablePicker(
      onCapture: (id, path) async {
        throw StateError('process-death-before-cancel');
      },
    );
    await expectLater(_capture(_service(root, picker)), throwsStateError);
    final id = _journals().single.operationId;
    picker.outcomes[id] = DurableCameraOutcome.canceled;

    expect(await _recover(root, picker), isEmpty);
    expect(await _recover(root, picker), isEmpty);
    expect(_journal(id).status, JournalStatus.committed);
    expect(Hive.box<String>('inspection_photos_v1'), isEmpty);
    expect(Hive.box<String>('media_work_queue_v1'), isEmpty);
  });

  test('fallo entre documento y cola converge antes de commit', () async {
    final picker = _DurablePicker(
      onCapture: (id, path) async {
        await _writeJpeg(File(path));
        return XFile(path);
      },
    );
    final photo = await _capture(_service(root, picker));
    final queue = Hive.box<String>('media_work_queue_v1');
    await queue.delete(photo!.id);
    expect(queue, isEmpty);

    await _service(root, picker).markDraftLinkedAndCommitted(photo.id);

    expect(queue.containsKey(photo.id), isTrue);
    expect(_journal(photo.id).status, JournalStatus.committed);
    expect(Hive.box<String>('inspection_photos_v1'), hasLength(1));
  });

  test('recovery conserva metadata completa del slot', () async {
    final picker = _DurablePicker(
      onCapture: (id, path) async {
        await _writeJpeg(File(path));
        throw StateError('process-death');
      },
    );
    await expectLater(
      _service(root, picker).acquire(
        pickerSource: ImageSource.camera,
        hydrantId: 'hydrant-1',
        inspectionId: 'inspection-1',
        category: 'component-photo',
        inspectionType: 'f02B',
        testId: 'test-1',
        componentId: 'component-1',
        instrumentId: 'instrument-1',
        measurementSeriesId: 'series-1',
        measurementReadingId: 'reading-1',
        evidenceRequirementId: 'requirement-1',
        userId: 'user-1',
        userName: 'User',
        brigadeId: 'brigade-1',
        deviceId: 'device-1',
        localScopeNamespace: 'qa/scope',
      ),
      throwsStateError,
    );
    picker.outcomes[_journals().single.operationId] =
        DurableCameraOutcome.success;

    final recovered = await _service(root, picker).recoverPendingForInspection(
      inspectionId: 'inspection-1',
      userId: 'user-1',
      userName: 'User',
      brigadeId: 'brigade-1',
      deviceId: 'device-1',
      localScopeNamespace: 'qa/scope',
    );

    expect(recovered, hasLength(1));
    final photo = recovered.single;
    expect(photo.inspectionType, 'f02B');
    expect(photo.testId, 'test-1');
    expect(photo.componentId, 'component-1');
    expect(photo.instrumentId, 'instrument-1');
    expect(photo.measurementSeriesId, 'series-1');
    expect(photo.measurementReadingId, 'reading-1');
    expect(photo.evidenceRequirementId, 'requirement-1');
  });

  test('dos instancias no crean capturas concurrentes', () async {
    final started = Completer<void>();
    final finish = Completer<XFile?>();
    final picker = _DurablePicker(
      onCapture: (id, path) {
        started.complete();
        return finish.future;
      },
    );
    final first = _capture(_service(root, picker));
    await started.future;

    await expectLater(_capture(_service(root, picker)), throwsStateError);
    expect(_journals(), hasLength(1));
    finish.complete(null);
    await first;
    expect(_journals().single.status, JournalStatus.committed);
  });

  test('cleanup no sigue una ruta durable manipulada', () async {
    const id = '123e4567-e89b-42d3-a456-426614174000';
    final outside = File('${root.path}/$id.source.jpg');
    await _writeJpeg(outside);
    await OperationJournalRepository(
      Hive.box<String>('operation_journal_v1'),
    ).save(
      OperationJournalEntry(
        operationId: id,
        operationType: JournalOperationType.capturePhoto,
        entityIds: const [
          'camera-pending-v2',
          'inspection-1',
          'hydrant-1',
          'top',
          'camera',
          'User',
          'brigade-1',
          'qa/scope',
        ],
        fileWrites: [outside.path],
        status: JournalStatus.committed,
        preparedAt: DateTime.utc(2026),
        actor: 'user-1',
        deviceId: 'device-1',
        correlationId: id,
      ),
    );

    await _service(root, _DurablePicker()).cleanupCommittedCaptureSources();

    expect(await outside.exists(), isTrue);
  });

  test(
    'fuente modificada durante normalización se conserva para recovery',
    () async {
      final picker = _DurablePicker(
        onCapture: (id, path) async {
          await _writeJpeg(File(path));
          return XFile(path);
        },
      );
      final service = ReliablePhotoService(
        picker: picker,
        processor: const _MutatingProcessor(),
        thumbnailService: const _Thumbnail(),
        documentsDirectory: () async => root,
        supportDirectory: () async => root,
      );

      await expectLater(_capture(service), throwsStateError);

      expect(Hive.box<String>('inspection_photos_v1'), isEmpty);
      expect(Hive.box<String>('media_work_queue_v1'), isEmpty);
      final journal = _journals().single;
      expect(journal.status, JournalStatus.needsRecovery);
      expect(journal.lastError, 'StateError');
      expect(journal.lastError, isNot(contains(root.path)));
      expect(await _durableFile(journal).exists(), isTrue);
    },
  );
}

ReliablePhotoService _service(Directory root, _DurablePicker picker) =>
    ReliablePhotoService(
      picker: picker,
      processor: const _Processor(),
      thumbnailService: const _Thumbnail(),
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
  localScopeNamespace: 'qa/scope',
);

Future<List<dynamic>> _recover(Directory root, _DurablePicker picker) =>
    _service(root, picker).recoverPendingForInspection(
      inspectionId: 'inspection-1',
      userId: 'user-1',
      userName: 'User',
      brigadeId: 'brigade-1',
      deviceId: 'device-1',
      localScopeNamespace: 'qa/scope',
    );

Future<void> _writeJpeg(File file) async {
  await file.parent.create(recursive: true);
  await file.writeAsBytes([
    0xff,
    0xd8,
    ...List<int>.filled(1024, 9),
    0xff,
    0xd9,
  ], flush: true);
}

OperationJournalEntry _journal(String id) => OperationJournalEntry.fromJson(
  Map<String, dynamic>.from(
    jsonDecode(Hive.box<String>('operation_journal_v1').get(id)!) as Map,
  ),
);

List<OperationJournalEntry> _journals() => Hive.box<String>(
  'operation_journal_v1',
).keys.map((id) => _journal('$id')).toList();

File _durableFile(OperationJournalEntry entry) => File(
  entry.fileWrites.singleWhere(
    (path) => path.endsWith('${entry.operationId}.source.jpg'),
  ),
);

class _DurablePicker implements PhotoPicker {
  _DurablePicker({this.onCapture, Map<String, DurableCameraOutcome>? outcomes})
    : outcomes = outcomes ?? {};

  final Future<XFile?> Function(String id, String path)? onCapture;
  final Map<String, DurableCameraOutcome> outcomes;
  final List<String> cleared = [];

  @override
  Future<XFile?> pickImage({
    required ImageSource source,
    String? captureId,
    String? durablePath,
  }) => onCapture!(captureId!, durablePath!);

  @override
  Future<LostDataResponse> retrieveLostData() async => LostDataResponse.empty();

  @override
  Future<DurableCameraOutcome> durableCameraOutcome(String captureId) async =>
      outcomes[captureId] ?? DurableCameraOutcome.unknown;

  @override
  Future<void> clearDurableCameraOutcome(String captureId) async {
    cleared.add(captureId);
    outcomes.remove(captureId);
  }
}

class _Processor implements ImageProcessingService {
  const _Processor();

  @override
  Future<ProcessedImage> normalize(File source, String destination) async =>
      ProcessedImage(await source.copy(destination), 1920, 1080);
}

class _Thumbnail implements PhotoThumbnailService {
  const _Thumbnail();

  @override
  Future<File?> create(File source, String destination) =>
      source.copy(destination);
}

class _MutatingProcessor implements ImageProcessingService {
  const _MutatingProcessor();

  @override
  Future<ProcessedImage> normalize(File source, String destination) async {
    final processed = await source.copy(destination);
    await source.writeAsBytes([0xff, 0xd8, 1, 2, 3, 0xff, 0xd9], flush: true);
    return ProcessedImage(processed, 1920, 1080);
  }
}
