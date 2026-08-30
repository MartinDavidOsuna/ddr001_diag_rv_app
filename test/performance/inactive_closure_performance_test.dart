import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:ddr001diag/data/local/media_work_item_codec.dart';
import 'package:ddr001diag/data/local/visual_inspection_repository.dart';
import 'package:ddr001diag/domain/enums/app_enums.dart';
import 'package:ddr001diag/domain/inspections/visual_inspection.dart';
import 'package:ddr001diag/domain/media/inspection_photo.dart';
import 'package:ddr001diag/domain/models/app_models.dart';
import 'package:ddr001diag/features/inspections/data/rv_draft_repository.dart';
import 'package:ddr001diag/features/inspections/domain/rv_draft.dart';
import 'package:ddr001diag/features/inspections/domain/rv_sync_state.dart';
import 'package:ddr001diag/features/inspections/presentation/inspection_photo_projection.dart';
import 'package:ddr001diag/features/inspections/presentation/rv_steps_one_two.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';

import '../helpers/hive_test_environment.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('bounded inspection photo projection', () {
    test('retains, adds, removes, invalidates and refreshes exact IDs', () {
      final raw = <String, String>{
        'photo-1': jsonEncode(_photoJson('photo-1')),
        'photo-2': jsonEncode(_photoJson('photo-2')),
      };
      final projection = InspectionPhotoDocumentProjection(
        readRaw: (id) => raw[id],
      );

      projection.retain(const ['photo-1']);
      expect(projection.hiveReads, 1);
      expect(projection.jsonDecodes, 1);
      expect(projection.photo('photo-1')?.id, 'photo-1');

      projection.retain(const ['photo-1']);
      expect(projection.hiveReads, 1);
      expect(projection.jsonDecodes, 1);

      projection.retain(const ['photo-1', 'photo-2']);
      expect(projection.hiveReads, 2);
      expect(projection.jsonDecodes, 2);
      expect(projection.retainedDocuments, 2);

      projection.retain(const ['photo-2']);
      expect(projection.retainedDocuments, 1);
      expect(projection.contains('photo-1'), isFalse);
      expect(projection.hiveReads, 2);

      projection.invalidate('photo-2');
      expect(projection.contains('photo-2'), isFalse);
      projection.retain(const ['photo-2']);
      expect(projection.hiveReads, 3);
      expect(projection.jsonDecodes, 3);

      raw['photo-2'] = jsonEncode({
        ..._photoJson('photo-2'),
        'thumbnailPath': '/synthetic/regenerated.jpg',
      });
      projection.refresh(const ['photo-2']);
      expect(
        projection.photo('photo-2')?.thumbnailPath,
        '/synthetic/regenerated.jpg',
      );
      expect(projection.hiveReads, 4);
      expect(projection.jsonDecodes, 4);

      raw['photo-2'] = jsonEncode({
        ..._photoJson('photo-2'),
        'deletedAt': DateTime.utc(2026, 8, 28, 21).toIso8601String(),
      });
      projection.refresh(const ['photo-2']);
      expect(projection.photo('photo-2')?.isDeleted, isTrue);
      expect(projection.hiveReads, 5);
      expect(projection.jsonDecodes, 5);

      projection.clear();
      expect(projection.retainedDocuments, 0);
    });

    test(
      'missing and unreadable documents recover after selective refresh',
      () {
        final raw = <String, String>{'unreadable': '{not-json'};
        final projection = InspectionPhotoDocumentProjection(
          readRaw: (id) => raw[id],
        );

        projection.retain(const ['missing', 'unreadable']);
        expect(projection.photo('missing'), isNull);
        expect(projection.photo('unreadable'), isNull);
        expect(projection.hiveReads, 2);
        expect(projection.jsonDecodes, 1);

        raw['missing'] = jsonEncode(_photoJson('missing'));
        raw['unreadable'] = jsonEncode(_photoJson('unreadable'));
        projection.refresh(const ['missing']);
        expect(projection.photo('missing')?.id, 'missing');
        expect(projection.photo('unreadable'), isNull);
        expect(projection.hiveReads, 3);
        expect(projection.jsonDecodes, 2);

        projection.invalidate('unreadable');
        projection.retain(const ['missing', 'unreadable']);
        expect(projection.photo('unreadable')?.id, 'unreadable');
        expect(projection.hiveReads, 4);
        expect(projection.jsonDecodes, 3);

        // Only typed metadata is retained; unknown byte-like payload data is
        // ignored by the domain decoder and cannot enter the cache.
        raw['missing'] = jsonEncode({
          ..._photoJson('missing'),
          'imageBytes': List<int>.filled(128, 7),
        });
        projection.refresh(const ['missing']);
        expect(projection.photo('missing'), isA<InspectionPhoto>());
        expect(
          projection.photo('missing')!.toJson().containsKey('imageBytes'),
          isFalse,
        );
      },
    );

    test(
      'same photoId metadata replacement evicts only its thumbnail',
      () async {
        final environment = HiveTestEnvironment();
        await environment.open();
        final box = Hive.box<String>('inspection_photos_v1');
        final raw = jsonEncode(_photoJson('same-id'));
        await box.put('same-id', raw);
        final projection = InspectionPhotoDocumentProjection();
        final evictions = <String>[];
        var notifications = 0;
        final binding = InspectionPhotoProjectionBinding(
          projection: projection,
          box: box,
          onChanged: () => notifications++,
          evictThumbnail: (before, after) {
            evictions.add('${before?.sha256}->${after?.sha256}');
          },
        );
        binding.retain(const ['same-id']);

        final changed = {
          ..._photoJson('same-id'),
          'fileSize': 2049,
          'sha256': ''.padRight(64, 'b'),
          'updatedAt': DateTime.utc(2026, 8, 29).toIso8601String(),
        };
        await box.put('same-id', jsonEncode(changed));
        await Future<void>.delayed(Duration.zero);

        expect(projection.hiveReads, 2);
        expect(projection.jsonDecodes, 2);
        expect(projection.photo('same-id')?.fileSize, 2049);
        expect(projection.photo('same-id')?.sha256, ''.padRight(64, 'b'));
        expect(evictions, hasLength(1));
        expect(notifications, 1);
        expect(binding.activeListeners, 1);

        binding.dispose();
        expect(binding.activeListeners, 0);
        expect(projection.retainedDocuments, 0);
        await environment.close();
      },
    );
  });

  testWidgets(
    'open gallery refreshes incrementally without duplicate listeners',
    (tester) async {
      final environment = HiveTestEnvironment();
      await tester.runAsync(environment.open);
      final box = Hive.box<String>('inspection_photos_v1');
      final notifier = _CountingNotifier();
      var draft = _galleryDraft(const []);
      final projection = InspectionPhotoDocumentProjection();
      final files = <String, File>{};

      Future<void> storePhoto(String id, {String suffix = 'initial'}) async {
        await tester.runAsync(() async {
          final file = File('${environment.directory.path}/$id-$suffix.png');
          await file.writeAsBytes(_onePixelPng, flush: true);
          files[id] = file;
          await box.put(
            id,
            jsonEncode({
              ..._photoJson(id),
              'localPath': file.path,
              'thumbnailPath': file.path,
            }),
          );
        });
      }

      Future<void> showGallery() => tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RvPhotoSlotGallery.testing(
              slot: _gallerySlot,
              changes: notifier,
              draftProvider: () => draft,
              removePhoto: (_, photoId) async {
                draft = _galleryDraft(
                  draft
                      .photosFor(_gallerySlot)
                      .map((reference) => reference.photoId)
                      .where((id) => id != photoId)
                      .toList(),
                );
                notifier.emit();
              },
              photoProjection: projection,
            ),
          ),
        ),
      );

      try {
        final rssBefore = ProcessInfo.currentRss;
        final incrementalWatch = Stopwatch()..start();
        await showGallery();
        expect(find.text('No hay fotografías en este rubro.'), findsOneWidget);
        expect(projection.hiveReads, 0);
        expect(notifier.activeListeners, 1);

        for (var index = 0; index < 10; index++) {
          final id = 'incremental-$index';
          await storePhoto(id);
          draft = _galleryDraft([
            ...draft
                .photosFor(_gallerySlot)
                .map((reference) => reference.photoId),
            id,
          ]);
          notifier.emit();
          await tester.pump();
          if (index < 5) {
            expect(find.byKey(ValueKey('gallery-photo-$id')), findsOneWidget);
          }
          expect(projection.hiveReads, index + 1);
          expect(projection.jsonDecodes, index + 1);
          expect(projection.retainedDocuments, index + 1);
        }
        await tester.scrollUntilVisible(
          find.byKey(const ValueKey('gallery-photo-incremental-9')),
          160,
          scrollable: find.byType(Scrollable).last,
        );
        expect(
          find.byKey(const ValueKey('gallery-photo-incremental-9')),
          findsOneWidget,
        );
        debugPrint(
          '[PERF][PHOTO_PROJECTION_INCREMENTAL] sequence=0,1,5,10 '
          'hive_reads=10 json_decodes=10 retained=10',
        );

        for (var rebuild = 0; rebuild < 20; rebuild++) {
          notifier.emit();
          await tester.pump();
        }
        expect(projection.hiveReads, 10);
        expect(projection.jsonDecodes, 10);
        expect(notifier.activeListeners, 1);

        final oldPath = files['incremental-4']!.path;
        await storePhoto('incremental-4', suffix: 'regenerated');
        await tester.pump();
        await tester.pump();
        expect(projection.hiveReads, 11);
        expect(projection.jsonDecodes, 11);
        expect(
          projection.photo('incremental-4')?.thumbnailPath,
          isNot(oldPath),
        );
        await tester.scrollUntilVisible(
          find.byKey(const ValueKey('gallery-photo-incremental-4')),
          -160,
          scrollable: find.byType(Scrollable).last,
        );
        expect(
          find.byKey(
            ValueKey(
              'gallery-thumbnail-incremental-4-'
              '${files['incremental-4']!.path}',
            ),
          ),
          findsOneWidget,
        );
        debugPrint(
          '[PERF][PHOTO_PROJECTION_INVALIDATION] changed_ids=1 '
          'additional_hive_reads=1 additional_json_decodes=1 '
          'unchanged_ids_reread=0',
        );

        draft = _galleryDraft([
          ...draft
              .photosFor(_gallerySlot)
              .map((reference) => reference.photoId),
          'recovered-missing',
        ]);
        notifier.emit();
        await tester.pump();
        expect(projection.hiveReads, 12);
        expect(projection.photo('recovered-missing'), isNull);
        await tester.scrollUntilVisible(
          find.byKey(const ValueKey('gallery-photo-recovered-missing')),
          160,
          scrollable: find.byType(Scrollable).last,
        );
        expect(
          find.byKey(
            const ValueKey('gallery-photo-fallback-recovered-missing'),
          ),
          findsOneWidget,
        );
        await storePhoto('recovered-missing');
        await tester.pump();
        await tester.pump();
        expect(projection.hiveReads, 13);
        expect(projection.jsonDecodes, 12);
        expect(projection.photo('recovered-missing'), isNotNull);
        expect(
          find.byKey(
            const ValueKey('gallery-photo-fallback-recovered-missing'),
          ),
          findsNothing,
        );

        final readsBeforeDelete = projection.hiveReads;
        await tester.scrollUntilVisible(
          find.byKey(const ValueKey('gallery-photo-incremental-9')),
          160,
          scrollable: find.byType(Scrollable).last,
        );
        await tester.tap(
          find.descendant(
            of: find.byKey(const ValueKey('gallery-photo-incremental-9')),
            matching: find.byTooltip('Eliminar fotografía'),
          ),
        );
        await tester.pump();
        await tester.tap(find.widgetWithText(FilledButton, 'Eliminar'));
        await tester.pump();
        await tester.pump();
        expect(
          find.byKey(const ValueKey('gallery-photo-incremental-9')),
          findsNothing,
        );
        expect(projection.retainedDocuments, 10);
        expect(projection.hiveReads, readsBeforeDelete);

        incrementalWatch.stop();
        debugPrint(
          '[PERF][PHOTO_PROJECTION_WIDGET_LIFECYCLE] '
          'hive_reads=${projection.hiveReads} '
          'json_decodes=${projection.jsonDecodes} retained=10 '
          'controller_rebuilds=31 active_listeners=${notifier.activeListeners} '
          'elapsed_us=${incrementalWatch.elapsedMicroseconds} '
          'rss_before=$rssBefore rss_after=${ProcessInfo.currentRss}',
        );

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        expect(projection.retainedDocuments, 0);
        expect(notifier.activeListeners, 0);
        notifier.emit();
        await tester.pump();
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.runAsync(environment.close);
      }
    },
  );

  test(
    '20 rebuilds reuse exact-ID preview projection without retained bytes',
    () {
      final raw = <String, String>{
        for (var index = 0; index < 10; index++)
          'photo-$index': jsonEncode(_photoJson('photo-$index')),
      };
      final ids = raw.keys.toList(growable: false);
      final rssBefore = ProcessInfo.currentRss;

      var legacyReads = 0;
      var legacyDecodes = 0;
      final legacyWatch = Stopwatch()..start();
      for (var rebuild = 0; rebuild < 20; rebuild++) {
        for (final id in ids) {
          legacyReads++;
          jsonDecode(raw[id]!);
          legacyDecodes++;
        }
      }
      legacyWatch.stop();

      final projection = InspectionPhotoDocumentProjection(
        readRaw: (id) => raw[id],
      );
      final optimizedWatch = Stopwatch()..start();
      for (var rebuild = 0; rebuild < 20; rebuild++) {
        projection.retain(ids);
      }
      optimizedWatch.stop();

      expect(legacyReads, 200);
      expect(legacyDecodes, 200);
      expect(projection.hiveReads, 10);
      expect(projection.jsonDecodes, 10);
      expect(projection.retainedDocuments, 10);
      projection.clear();
      expect(projection.retainedDocuments, 0);

      var lifecycleReads = 0;
      var lifecycleDecodes = 0;
      var maxRetained = 0;
      final lifecycleWatch = Stopwatch()..start();
      for (final count in [0, 0, 1, 10]) {
        for (var opening = 0; opening < 20; opening++) {
          final opened = InspectionPhotoDocumentProjection(
            readRaw: (id) => raw[id],
          );
          opened.retain(ids.take(count));
          // Comment edits and parent rebuilds keep the same projection.
          for (var rebuild = 0; rebuild < 20; rebuild++) {
            opened.retain(ids.take(count));
          }
          maxRetained = maxRetained < opened.retainedDocuments
              ? opened.retainedDocuments
              : maxRetained;
          lifecycleReads += opened.hiveReads;
          lifecycleDecodes += opened.jsonDecodes;
          // Models save/reopen and discard: each dialog owns and clears its
          // bounded projection; files and image bytes are never retained here.
          opened.retain(const []);
          opened.clear();
          expect(opened.retainedDocuments, 0);
        }
      }
      lifecycleWatch.stop();
      final rssAfter = ProcessInfo.currentRss;

      debugPrint(
        '[PERF][INACTIVE_DIALOG] legacy_20_rebuild_reads=$legacyReads '
        'legacy_json_decodes=$legacyDecodes '
        'legacy_elapsed_us=${legacyWatch.elapsedMicroseconds}',
      );
      debugPrint(
        '[PERF][INACTIVE_DIALOG] optimized_20_rebuild_reads='
        '${projection.hiveReads} optimized_json_decodes='
        '${projection.jsonDecodes} optimized_elapsed_us='
        '${optimizedWatch.elapsedMicroseconds}',
      );
      debugPrint(
        '[PERF][INACTIVE_DIALOG] lifecycle_openings=80 '
        'reads=$lifecycleReads decodes=$lifecycleDecodes '
        'max_retained_documents=$maxRetained final_retained_documents=0 '
        'elapsed_us=${lifecycleWatch.elapsedMicroseconds} '
        'rss_before=$rssBefore rss_after=$rssAfter',
      );

      expect(lifecycleReads, 220);
      expect(lifecycleDecodes, 220);
      expect(maxRetained, 10);
    },
  );

  test('80 projection lifecycles release all key-specific listeners', () async {
    final environment = HiveTestEnvironment();
    await environment.open();
    try {
      final box = Hive.box<String>('inspection_photos_v1');
      final ids = List.generate(10, (index) => 'lifecycle-$index');
      for (final id in ids) {
        await box.put(id, jsonEncode(_photoJson(id)));
      }
      var totalReads = 0;
      var totalDecodes = 0;
      var maxListeners = 0;
      var callbacksAfterDispose = 0;
      final watch = Stopwatch()..start();
      for (final count in [0, 0, 1, 10]) {
        for (var opening = 0; opening < 20; opening++) {
          final projection = InspectionPhotoDocumentProjection();
          var disposed = false;
          final binding = InspectionPhotoProjectionBinding(
            projection: projection,
            onChanged: () {
              if (disposed) callbacksAfterDispose++;
            },
          );
          binding.retain(ids.take(count));
          maxListeners = maxListeners < binding.activeListeners
              ? binding.activeListeners
              : maxListeners;
          totalReads += projection.hiveReads;
          totalDecodes += projection.jsonDecodes;
          disposed = true;
          binding.dispose();
          expect(binding.activeListeners, 0);
          expect(projection.retainedDocuments, 0);
        }
      }
      watch.stop();
      await Future<void>.delayed(Duration.zero);
      expect(callbacksAfterDispose, 0);
      expect(totalReads, 220);
      expect(totalDecodes, 220);
      expect(maxListeners, 10);
      debugPrint(
        '[PERF][PHOTO_PROJECTION_LIFECYCLE] openings=80 reads=$totalReads '
        'decodes=$totalDecodes max_listeners=$maxListeners '
        'final_listeners=0 final_documents=0 callbacks_after_dispose=0 '
        'elapsed_us=${watch.elapsedMicroseconds}',
      );
    } finally {
      await environment.close();
    }
  });

  test(
    '27-review discard scans archive once for ten dedicated photos',
    () async {
      final environment = HiveTestEnvironment();
      await environment.open();
      try {
        final visual = VisualInspectionRepository(
          documents: Hive.box<String>('visual_inspections_v1'),
          index: Hive.box<String>('active_inspection_index_v1'),
        );
        final repository = RvDraftRepository(visual);
        final now = DateTime.utc(2026, 8, 28, 20);
        final corpusWatch = Stopwatch()..start();
        var totalAnswers = 0;
        var totalReferences = 0;
        for (var review = 0; review < 27; review++) {
          final answerCount = review == 0 ? 41 : 50;
          final referenceCount = review == 0
              ? 10
              : review == 26
              ? 3
              : 10;
          totalAnswers += answerCount;
          totalReferences += referenceCount;
          final id = 'synthetic-review-$review';
          final photoIds = List.generate(
            referenceCount,
            (photo) => review == 0
                ? 'inactive-photo-$photo'
                : 'ordinary-$review-$photo',
          );
          final status = switch (review) {
            23 => RvLocalStatus.submitted,
            24 => RvLocalStatus.inactive,
            25 => RvLocalStatus.conflict,
            _ => RvLocalStatus.pendingCreate,
          };
          final location = RvLocationSample(
            latitude: 1.25,
            longitude: -1.25,
            horizontalAccuracy: 4,
            source: 'synthetic_fixture',
            capturedAt: now,
          );
          final draft = RvDraft(
            clientInspectionId: id,
            hydrantId: 'synthetic-hydrant-$review',
            accountNumber: 'QA-${review.toString().padLeft(4, '0')}',
            fieldSessionId: _user.id,
            checklistId: 'synthetic-checklist',
            checklistVersion: 1,
            checklistSnapshot: const {},
            answers: {
              for (var answer = 0; answer < answerCount; answer++)
                'q-$review-$answer': RvAnswer(
                  questionId: 'q-$review-$answer',
                  sectionId: 'synthetic-section',
                  answerType: 'text',
                  value: 'synthetic-value-$answer',
                  updatedAt: now,
                ),
            },
            photos: {
              review == 0
                  ? noHydrantAtLocationPhotoSlot
                  : 'synthetic_normal_slot': [
                for (final photoId in photoIds)
                  RvPhotoReference(
                    photoId: photoId,
                    slotCode: review == 0
                        ? noHydrantAtLocationPhotoSlot
                        : 'synthetic_normal_slot',
                    status: RvPhotoUploadStatus.pending,
                  ),
              ],
            },
            location: review == 0 || review == 24 ? location : null,
            locationStatus: review == 0 || review == 24
                ? RvPartStatus.pending
                : RvPartStatus.notCaptured,
            localStatus: status,
            remoteStatus: review == 23 ? 'submitted' : 'not_created',
            inactiveClosure: review == 24
                ? RvInactiveClosure(
                    reasonCode: noHydrantAtLocationReasonCode,
                    comment: 'Cierre inactivo sintético confirmado localmente.',
                    location: location,
                    closedAt: now,
                    closedByUserId: _user.id,
                    closedByName: _user.fullName,
                    brigadeId: _user.brigadeId,
                    deviceId: _user.deviceId,
                    photoIds: photoIds,
                    idempotencyKey: 'synthetic-inactive-closure-24',
                  )
                : null,
            createdAt: now,
            updatedAt: now,
          );
          final storedDraft = draft.toJson();
          if (review == 26) {
            storedDraft
              ..remove('inactiveClosureDraft')
              ..remove('inactiveClosure');
          }
          await visual.save(
            VisualInspection(
              id: id,
              hydrantId: draft.hydrantId,
              source: HydrantSource.fieldCreated,
              status: review == 23 || review == 24
                  ? InspectionStatus.completed
                  : InspectionStatus.inProgress,
              inspectorId: _user.id,
              inspectorName: _user.fullName,
              brigadeId: _user.brigadeId,
              brigadeName: _user.brigadeName,
              deviceId: _user.deviceId,
              startedAt: now,
              createdAt: now,
              createdBy: _user.id,
              updatedAt: now,
              updatedBy: _user.id,
              unknownFields: {RvDraftRepository.storageKey: storedDraft},
            ),
          );
        }
        await visual.index.clear();
        for (var active = 0; active < 5; active++) {
          await visual.index.put(
            'synthetic-hydrant-$active:f02A',
            'synthetic-review-$active',
          );
        }
        corpusWatch.stop();

        expect(totalAnswers, 1341);
        expect(totalReferences, 263);
        expect(visual.documents, hasLength(27));
        expect(visual.index, hasLength(5));
        expect(repository.all(), hasLength(27));
        expect(
          repository.all().where((draft) => draft.isInactive),
          hasLength(1),
        );
        expect(
          repository.all().where(
            (draft) => draft.localStatus == RvLocalStatus.conflict,
          ),
          hasLength(1),
        );
        expect(
          repository.all().where(
            (draft) => draft.localStatus == RvLocalStatus.submitted,
          ),
          hasLength(1),
        );

        final photoBox = Hive.box<String>('inspection_photos_v1');
        for (var photo = 0; photo < 10; photo++) {
          final id = 'inactive-photo-$photo';
          final file = File('${environment.directory.path}/$id.jpg');
          final bytes = List<int>.generate(
            256,
            (index) => (index + photo) % 251,
          );
          await file.writeAsBytes(bytes, flush: true);
          await photoBox.put(
            id,
            jsonEncode(
              InspectionPhoto(
                id: id,
                hydrantId: 'synthetic-hydrant-0',
                inspectionId: 'synthetic-review-0',
                category: noHydrantAtLocationPhotoSlot,
                source: PhotoSource.camera,
                originalFilename: '$id-source.jpg',
                normalizedFilename: '$id.jpg',
                localPath: file.path,
                thumbnailPath: file.path,
                mimeType: 'image/jpeg',
                fileSize: bytes.length,
                width: 128,
                height: 128,
                sha256: sha256.convert(bytes).toString(),
                receivedSha256: sha256.convert(bytes).toString(),
                capturedAt: now,
                capturedByUserId: _user.id,
                capturedByName: _user.fullName,
                brigadeId: _user.brigadeId,
                deviceId: _user.deviceId,
                createdAt: now,
                updatedAt: now,
              ).toJson(),
            ),
          );
        }
        final discardedFile = File(
          '${environment.directory.path}/discarded-synthetic.jpg',
        );
        await discardedFile.writeAsBytes([9, 8, 7], flush: true);
        await photoBox.put(
          'discarded-synthetic',
          jsonEncode({
            ..._photoJson('discarded-synthetic'),
            'localPath': discardedFile.path,
            'thumbnailPath': discardedFile.path,
            'deletedAt': now.toIso8601String(),
          }),
        );
        final discardedQueue = MediaWorkItemCodec.pending(
          photoId: 'discarded-synthetic',
          inspectionId: 'synthetic-review-22',
          slotCode: noHydrantAtLocationPhotoSlot,
          status: 'discardedLocalInactiveDraft',
        );
        await Hive.box<String>(
          'media_work_queue_v1',
        ).put('discarded-synthetic', discardedQueue);
        await Hive.box<String>(
          'media_sync_queue',
        ).put('discarded-synthetic', discardedQueue);
        await repository.saveInactiveClosureDraft(
          clientInspectionId: 'synthetic-review-0',
          user: _user,
          comment: 'Borrador sintético para medir descarte seguro.',
          now: now.add(const Duration(seconds: 1)),
        );

        final journalBox = Hive.box<String>('operation_journal_v1');
        final journalsBeforeCorrupt = journalBox.length;
        await visual.documents.put('controlled-corrupt', '{not-json');
        await expectLater(
          repository.discardInactiveClosureDraft(
            clientInspectionId: 'synthetic-review-0',
            user: _user,
          ),
          throwsA(isA<StateError>()),
        );
        final preservedAfterCorrupt = repository.find('synthetic-review-0')!;
        expect(
          preservedAfterCorrupt.photosFor(noHydrantAtLocationPhotoSlot),
          hasLength(10),
        );
        expect(journalBox.length, journalsBeforeCorrupt);
        for (var photo = 0; photo < 10; photo++) {
          expect(
            File(
              '${environment.directory.path}/inactive-photo-$photo.jpg',
            ).existsSync(),
            isTrue,
          );
        }
        await visual.documents.delete('controlled-corrupt');

        final rssBefore = ProcessInfo.currentRss;
        final discardWatch = Stopwatch()..start();
        await repository.discardInactiveClosureDraft(
          clientInspectionId: 'synthetic-review-0',
          user: _user,
        );
        discardWatch.stop();
        final rssAfter = ProcessInfo.currentRss;

        final discarded = repository.find('synthetic-review-0')!;
        expect(discarded.inactiveClosureDraft, isNull);
        expect(discarded.photosFor(noHydrantAtLocationPhotoSlot), isEmpty);
        expect(repository.lastInactiveDiscardDocumentDecodes, 27);
        for (var photo = 0; photo < 10; photo++) {
          final id = 'inactive-photo-$photo';
          final restored = InspectionPhoto.fromJson(
            Map<String, dynamic>.from(jsonDecode(photoBox.get(id)!) as Map),
          );
          expect(restored.isDeleted, isTrue);
          expect(File(restored.localPath).existsSync(), isTrue);
          expect(
            MediaWorkItemCodec.statusOf(
              id,
              Hive.box<String>('media_work_queue_v1').get(id),
            ),
            'discardedLocalInactiveDraft',
          );
        }
        final openJournals = Hive.box<String>('operation_journal_v1').values
            .map((raw) => jsonDecode(raw) as Map)
            .where((entry) => entry['status'] != 'committed')
            .length;
        expect(openJournals, 0);
        expect(discardedFile.existsSync(), isTrue);

        debugPrint(
          '[PERF][INACTIVE_DISCARD] fixture_reviews=27 answers=1341 '
          'references=263 active=5 normal_closed=1 conflict=1 '
          'inactive_draft=1 inactive_confirmed=1 discarded=1 legacy=1 '
          'controlled_corrupt_rejected=1 '
          'corpus_ms=${corpusWatch.elapsedMilliseconds}',
        );
        debugPrint(
          '[PERF][INACTIVE_DISCARD] legacy_expected_document_decodes=270 '
          'optimized_document_decodes='
          '${repository.lastInactiveDiscardDocumentDecodes} '
          'elapsed_ms=${discardWatch.elapsedMilliseconds} '
          'rss_before=$rssBefore rss_after=$rssAfter',
        );
      } finally {
        await environment.close();
      }
    },
  );
}

Map<String, dynamic> _photoJson(String id) {
  final now = DateTime.utc(2026, 8, 28, 20);
  return InspectionPhoto(
    id: id,
    hydrantId: 'synthetic-hydrant',
    inspectionId: 'synthetic-inspection',
    category: noHydrantAtLocationPhotoSlot,
    source: PhotoSource.camera,
    originalFilename: '$id-source.jpg',
    normalizedFilename: '$id.jpg',
    localPath: '/synthetic/$id.jpg',
    thumbnailPath: '/synthetic/$id-thumb.jpg',
    mimeType: 'image/jpeg',
    fileSize: 1024,
    width: 128,
    height: 128,
    sha256: 'a' * 64,
    receivedSha256: 'b' * 64,
    capturedAt: now,
    capturedByUserId: _user.id,
    capturedByName: _user.fullName,
    brigadeId: _user.brigadeId,
    deviceId: _user.deviceId,
    createdAt: now,
    updatedAt: now,
  ).toJson();
}

RvDraft _galleryDraft(List<String> photoIds) {
  final now = DateTime.utc(2026, 8, 28, 20);
  return RvDraft(
    clientInspectionId: 'synthetic-gallery-review',
    hydrantId: 'synthetic-gallery-hydrant',
    accountNumber: 'QA-GALLERY',
    fieldSessionId: _user.id,
    checklistId: 'synthetic-checklist',
    checklistVersion: 1,
    checklistSnapshot: const {},
    answers: const {},
    photos: {
      _gallerySlot: [
        for (final id in photoIds)
          RvPhotoReference(
            photoId: id,
            slotCode: _gallerySlot,
            status: RvPhotoUploadStatus.pending,
          ),
      ],
    },
    location: RvLocationSample(
      latitude: 1.25,
      longitude: -1.25,
      horizontalAccuracy: 4,
      source: 'synthetic_fixture',
      capturedAt: now,
    ),
    locationStatus: RvPartStatus.pending,
    localStatus: RvLocalStatus.pendingCreate,
    remoteStatus: 'not_created',
    createdAt: now,
    updatedAt: now,
  );
}

class _CountingNotifier extends ChangeNotifier {
  int activeListeners = 0;

  @override
  void addListener(VoidCallback listener) {
    activeListeners++;
    super.addListener(listener);
  }

  @override
  void removeListener(VoidCallback listener) {
    activeListeners--;
    super.removeListener(listener);
  }

  void emit() => notifyListeners();
}

final _onePixelPng = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk'
  'AAMAABsAASkLtQsAAAAASUVORK5CYII=',
);

const _gallerySlot = 'front_closed';

const _user = AppUser(
  id: 'synthetic-user',
  fullName: 'Técnico QA',
  email: 'qa@example.invalid',
  role: 'field',
  brigadeId: 'synthetic-brigade',
  brigadeName: 'QA aislado',
  deviceId: 'synthetic-device',
);
