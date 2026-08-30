// The exporter intentionally continues after malformed legacy records.
// ignore_for_file: curly_braces_in_flow_control_structures, empty_catches, unnecessary_string_interpolations

import 'dart:convert';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:crypto/crypto.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:hive_ce/hive.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../core/config/app_config.dart';
import '../../core/network/api_exception.dart';
import '../../data/local/sync_queue_repository.dart';
import '../../data/local/visual_inspection_repository.dart';
import '../../domain/enums/app_enums.dart';
import '../../domain/media/inspection_photo.dart';
import '../../domain/media/media_sync_status.dart';
import '../../domain/sync/sync_queue_item.dart';
import '../auth/data/session_secure_storage.dart';
import '../hydrants/data/hydrant_api_models.dart';
import '../inspections/data/rv_draft_repository.dart';
import '../inspections/domain/rv_draft.dart';
import '../inspections/domain/rv_sync_state.dart';
import '../inspections/domain/rv_validator.dart';
import 'rv_answer_cross_check.dart';

typedef DiagnosticProgress = void Function(String message);
typedef DiagnosticDeviceProvider =
    Future<Map<String, dynamic>> Function(String installationId);
typedef DiagnosticDirectoryProvider = Future<Directory> Function();
typedef DiagnosticRemoteProvider =
    Future<Map<String, dynamic>> Function(RvDraft draft);

@visibleForTesting
String classifyDiagnosticPhoto({
  required bool localFileExists,
  required bool remoteVerified,
  required bool localVerified,
  required String? mediaWorkStatus,
  required bool hasDraft,
  required bool hasRemoteMatch,
}) {
  if (!localFileExists) return 'MISSING_LOCAL_FILE';
  if (remoteVerified && !localVerified) {
    return 'REMOTE_VERIFIED_LOCAL_PENDING';
  }
  if (remoteVerified) return 'REMOTE_VERIFIED_LOCAL_VERIFIED';
  if (localVerified && mediaWorkStatus == 'pendingUpload') {
    return 'LEGACY_QUEUE_STALE';
  }
  if (!hasDraft) return 'ORPHAN_LOCAL_PHOTO';
  if (hasRemoteMatch) return 'UPLOADED_NOT_VERIFIED';
  return 'TRUE_UPLOAD_PENDING';
}

@visibleForTesting
bool diagnosticLocalPhotoVerified({
  required InspectionPhoto photo,
  required RvPhotoReference? reference,
  required Object? mediaQueueValue,
  required String? mediaWorkStatus,
}) {
  var queueStatus = '$mediaQueueValue';
  if (mediaQueueValue is String && mediaQueueValue.startsWith('{')) {
    try {
      final decoded = jsonDecode(mediaQueueValue);
      if (decoded is Map) queueStatus = '${decoded['status']}';
    } on Object {
      // A legacy/unreadable queue entry cannot override stronger local truth.
    }
  }
  return photo.integrityStatus.isConfirmed ||
      photo.syncStatus == MediaSyncStatus.verified ||
      reference?.status == RvPhotoUploadStatus.verified ||
      queueStatus == MediaSyncStatus.verified.name ||
      mediaWorkStatus == MediaSyncStatus.verified.name;
}

@visibleForTesting
bool diagnosticPhotoRowIsPending(Map<String, dynamic> row) {
  if (row['deletedAt'] != null ||
      row['diagnosticClassification'] == 'DISCARDED_LOCAL_INACTIVE_DRAFT') {
    return false;
  }
  return row['syncStatus'] != 'verified' &&
      row['rvPhotoReferenceStatus'] != 'verified' &&
      row['mediaWorkQueueStatus'] != 'verified';
}

class RvDiagnosticExportResult {
  const RvDiagnosticExportResult({
    required this.file,
    required this.remoteSnapshotComplete,
    required this.errorCount,
  });
  final File file;
  final bool remoteSnapshotComplete;
  final int errorCount;
}

class RvDiagnosticExportService {
  RvDiagnosticExportService({
    required this.config,
    required this.packageInfo,
    required this.sessionStorage,
    required this.visualRepository,
    required this.drafts,
    required this.syncQueue,
    required this.hydrantBox,
    required this.activeIndexBox,
    required this.photoBox,
    required this.mediaSyncBox,
    required this.mediaWorkBox,
    required this.diagnosticsBox,
    this.receiptsBox,
    this.deviceProvider,
    this.directoryProvider,
    this.remoteProvider,
  });

  static const schemaVersion = 1;
  static const focusAccounts = <String>[
    '1134',
    '486-2',
    '367-2',
    '446',
    '472-2',
    '1144',
    '1167',
    '918',
    '441',
    '1136',
    '1139',
    '1296',
    '414',
    '430',
    '431',
    '438',
    '906',
    '937',
    '995',
    '1011',
  ];

  final AppConfig config;
  final PackageInfo packageInfo;
  final SessionStorage sessionStorage;
  final VisualInspectionRepository visualRepository;
  final RvDraftRepository drafts;
  final SyncQueueRepository syncQueue;
  final Box<String> hydrantBox, activeIndexBox, photoBox;
  final Box<String> mediaSyncBox, mediaWorkBox, diagnosticsBox;
  final Box<String>? receiptsBox;
  final DiagnosticDeviceProvider? deviceProvider;
  final DiagnosticDirectoryProvider? directoryProvider;
  final DiagnosticRemoteProvider? remoteProvider;

  Future<List<File>> certificationEvidenceFiles({
    File? currentDiagnostic,
  }) async {
    final directory = directoryProvider != null
        ? await directoryProvider!()
        : Platform.isAndroid
        ? await getExternalStorageDirectory() ??
              await getApplicationDocumentsDirectory()
        : await getApplicationDocumentsDirectory();
    final files = directory.listSync().whereType<File>().where((file) {
      final name = p.basename(file.path);
      return name.startsWith('DDR001_RV_CERT_PRE_RECOVERY_') ||
          name.startsWith('DDR001_RV_CERT_POST_RECOVERY_OFFLINE_');
    }).toList();
    if (currentDiagnostic != null &&
        !files.any((file) => file.path == currentDiagnostic.path)) {
      files.add(currentDiagnostic);
    }
    files.sort((a, b) => a.path.compareTo(b.path));
    return files;
  }

  Future<RvDiagnosticExportResult> export({
    required Map<String, dynamic> screenSummary,
    required List<dynamic> hydrants,
    DiagnosticProgress? onProgress,
    bool queryRemote = true,
    String evidenceType = 'POST_RUNTIME',
  }) async {
    onProgress?.call('Recopilando estado local...');
    final errors = <Map<String, dynamic>>[];
    final session = await sessionStorage.read();
    // Export must remain observational. In particular, do not call
    // SessionStorage.installationId(): that method creates and persists an id
    // when none exists.
    final installationId = session?.installationId ?? 'unavailable';
    final readOnlyDio = Dio(
      BaseOptions(
        baseUrl: config.apiBaseUrl.toString().replaceAll(RegExp(r'/$'), ''),
        connectTimeout: const Duration(seconds: 20),
        receiveTimeout: const Duration(seconds: 20),
        sendTimeout: const Duration(seconds: 20),
        headers: {
          'Accept': 'application/json',
          if (session?.accessToken.isNotEmpty == true)
            'Authorization': 'Bearer ${session!.accessToken}',
        },
      ),
    );
    final allDrafts = drafts.all();
    final cached = _cachedHydrants();
    final queue = _syncQueueEntries(session?.userId);
    final localPhotos = _photos(session?.userId);
    final diagnosticEvents = _diagnostics();
    final remote = <String, dynamic>{};
    var remoteComplete = queryRemote && session != null;

    if (remoteComplete) {
      onProgress?.call('Consultando estado del servidor...');
      for (final draft in allDrafts) {
        try {
          remote[draft.clientInspectionId] =
              await (remoteProvider?.call(draft) ??
                  _remoteFor(readOnlyDio, draft));
        } on ApiException catch (error) {
          remote[draft.clientInspectionId] = {'error': _apiError(error)};
          errors.add({
            'scope': 'remoteSnapshot',
            'accountNumber': draft.accountNumber,
            ..._apiError(error),
          });
          if (_stopRemote(error)) {
            remoteComplete = false;
            break;
          }
        } on Object catch (error) {
          remoteComplete = false;
          errors.add({
            'scope': 'remoteSnapshot',
            'runtimeType': error.runtimeType.toString(),
            'message': _safe('$error'),
          });
          break;
        }
      }
    } else {
      remoteComplete = false;
    }

    final draftRows = <Map<String, dynamic>>[];
    for (final draft in allDrafts) {
      draftRows.add(
        _draft(draft, cached, queue, remote[draft.clientInspectionId]),
      );
    }
    final photoRows = _photoRows(localPhotos, allDrafts, remote);
    final crossChecks = _crossChecks(
      draftRows,
      photoRows,
      diagnosticEvents,
      remote,
      authenticated: session != null,
    );
    final indexRows = _activeIndex(allDrafts);
    final mediaWorkRows = _mediaWork(localPhotos);
    final focusRows = _focus(
      draftRows,
      photoRows,
      diagnosticEvents,
      remote,
      cached.values.toList(),
    );
    final checks = <Map<String, dynamic>>[
      for (final row in draftRows)
        for (final issue in row['consistencyIssues'] as List)
          {
            'clientInspectionId': row['clientInspectionId'],
            'accountNumber': row['accountNumber'],
            'issue': issue,
          },
      for (final row in focusRows)
        if (row['internalContradiction'] == true)
          {
            'accountNumber': row['accountNumber'],
            'issue': 'FOCUS_CASE_CONTRADICTS_HYDRANTS',
            'source': row['remoteHydrantSource'],
          },
    ];
    final now = DateTime.now().toUtc();
    final document = <String, dynamic>{
      'evidenceType': evidenceType,
      'schemaVersion': schemaVersion,
      'generatedAtUtc': now.toIso8601String(),
      'app': {
        'packageName': packageInfo.packageName,
        'versionName': packageInfo.version,
        'versionCode': packageInfo.buildNumber,
        'environment': config.environment,
        'apiBaseUrl': config.apiBaseUrl.toString(),
        'gitSha': const String.fromEnvironment(
          'GIT_SHA',
          defaultValue: 'development-build-without-release-metadata',
        ),
        'buildDateUtc': const String.fromEnvironment(
          'BUILD_DATE_UTC',
          defaultValue: 'development-build-without-release-metadata',
        ),
        'diagnosticSchemaVersion': schemaVersion,
      },
      'device':
          await (deviceProvider?.call(installationId) ??
              _device(installationId)),
      'session': {
        'userId': session?.userId,
        'crewId': session?.crewId,
        'workSessionId': session?.sessionId,
        'localStatus': session == null ? 'none' : 'active',
        'tokenPresent': session?.accessToken.isNotEmpty == true,
      },
      'summary': {
        ...screenSummary,
        'totalVisualInspectionDocuments': visualRepository.accessible().length,
        'totalRvDrafts': allDrafts.length,
        'totalActiveIndexEntries': activeIndexBox.length,
        'totalSyncQueueEntries': syncQueue.box.length,
        'totalUnreadableSyncQueueEntries': syncQueue.unreadableCount,
        'totalInspectionPhotos': photoBox.length,
        'totalMediaSyncQueueEntries': mediaSyncBox.length,
        'totalMediaWorkQueueEntries': mediaWorkBox.length,
        'totalDiagnosticEvents': diagnosticsBox.length,
        'totalSyncReceipts': receiptsBox?.length ?? 0,
        'photoClassifications': _counts(photoRows, 'diagnosticClassification'),
        'reviewClassifications': _counts(crossChecks, 'finalClassification'),
      },
      'boxes': _boxes(),
      'drafts': draftRows,
      'photos': photoRows,
      'crossChecks': crossChecks,
      'syncQueue': queue,
      'mediaWorkQueue': mediaWorkRows,
      'operationJournal': _rawBoxRows('operation_journal_v1'),
      'recoveryState': _rawBoxRows('rv_recovery_v1'),
      'recoverySnapshots': _rawBoxRows('rv_recovery_snapshots_v1'),
      'quarantine': _rawBoxRows('quarantine_documents_v1'),
      'orphanPhotos': photoRows
          .where((row) => row['clientInspectionId'] == null)
          .toList(),
      'diagnostics': diagnosticEvents,
      'syncReceipts': receiptsBox == null
          ? const <Map<String, dynamic>>[]
          : _rawBoxRows(receiptsBox!.name),
      'hydrants': cached.values.map((value) => _cachedHydrant(value)).toList(),
      'activeInspectionIndex': indexRows,
      'remoteSnapshot': {'complete': remoteComplete, 'drafts': remote},
      'focusCases': focusRows,
      'consistencyChecks': checks,
      'errors': errors,
    };
    onProgress?.call('Generando archivo...');
    late final Directory directory;
    if (directoryProvider != null) {
      directory = await directoryProvider!();
    } else if (Platform.isAndroid) {
      directory =
          await getExternalStorageDirectory() ??
          await getApplicationDocumentsDirectory();
    } else {
      directory = await getApplicationDocumentsDirectory();
    }
    final stamp = now
        .toIso8601String()
        .replaceAll(RegExp(r'[-:]'), '')
        .replaceAll('.000', '')
        .replaceAll(RegExp(r'[^0-9TZ]'), '');
    final filePrefix = evidenceType == 'POST_RECOVERY_OFFLINE'
        ? 'DDR001_RV_CERT_POST_RECOVERY_OFFLINE'
        : 'DDR001_RV_DIAGNOSTIC_v60';
    final file = File(p.join(directory.path, '${filePrefix}_$stamp.json'));
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(_sanitize(document)),
      flush: true,
    );
    return RvDiagnosticExportResult(
      file: file,
      remoteSnapshotComplete: remoteComplete,
      errorCount: errors.length,
    );
  }

  Map<String, CachedHydrant> _cachedHydrants() {
    final result = <String, CachedHydrant>{};
    for (final raw in hydrantBox.values) {
      try {
        final value = CachedHydrant.fromJson(
          Map<String, dynamic>.from(jsonDecode(raw) as Map),
        );
        result[value.hydrantId] = value;
      } on Object {
        /* counted in boxes */
      }
    }
    return result;
  }

  List<Map<String, dynamic>> _syncQueueEntries(String? userId) {
    final result = <Map<String, dynamic>>[];
    for (final entry in syncQueue.box.toMap().entries) {
      try {
        final item = SyncQueueItem.fromJson(
          Map<String, dynamic>.from(jsonDecode(entry.value) as Map),
        );
        if (userId == null ||
            item.ownerUserId.isEmpty ||
            item.ownerUserId == userId)
          result.add({...item.toJson(), 'unreadable': false});
      } on Object catch (error) {
        result.add({
          'key': '${entry.key}',
          'unreadable': true,
          'errorType': error.runtimeType.toString(),
        });
      }
    }
    return result;
  }

  List<InspectionPhoto> _photos(String? userId) {
    final result = <InspectionPhoto>[];
    for (final raw in photoBox.values) {
      try {
        final value = InspectionPhoto.fromJson(
          Map<String, dynamic>.from(jsonDecode(raw) as Map),
        );
        if (userId == null || value.capturedByUserId == userId)
          result.add(value);
      } on Object {}
    }
    return result;
  }

  Future<Map<String, dynamic>> _remoteFor(
    Dio readOnlyDio,
    RvDraft draft,
  ) async {
    if (draft.serverInspectionId == null) {
      try {
        final response = await readOnlyDio.get<Map<String, dynamic>>(
          '/hydrants/${Uri.encodeComponent(draft.accountNumber.trim())}',
        );
        final data = response.data ?? const <String, dynamic>{};
        return {
          'remoteHydrant': {
            'exactAccountExists': true,
            'hydrantId': data['hydrant_id'] ?? data['hydrantId'],
            'source': data['source_type'] ?? data['source'],
            'active': data['is_active'] ?? data['isActive'],
          },
          'remoteInspectionExists': false,
        };
      } on DioException catch (error) {
        final parsed = ApiException.fromDio(error);
        if (parsed.statusCode == 404)
          return {
            'remoteHydrant': {'exactAccountExists': false},
            'remoteInspectionExists': false,
          };
        rethrow;
      }
    }
    try {
      final response = await readOnlyDio.get<Map<String, dynamic>>(
        '/inspections/${draft.serverInspectionId}',
      );
      final data = response.data ?? const <String, dynamic>{};
      final photosResponse = await readOnlyDio.get<Map<String, dynamic>>(
        '/inspections/${draft.serverInspectionId}/photos',
      );
      final items = (photosResponse.data?['items'] as List? ?? const [])
          .whereType<Map>()
          .map((raw) => Map<String, dynamic>.from(raw))
          .toList();
      return {
        'remoteInspectionExists': true,
        'remoteInspection': {
          'inspectionId': data['inspection_id'] ?? data['inspectionId'],
          'hydrantId': data['hydrant_id'] ?? data['hydrantId'],
          'status': data['status'],
          'submittedAt': data['submitted_at'] ?? data['submittedAt'],
          'updatedAt': data['server_updated_at'] ?? data['updatedAt'],
          'officialInspectionId': data['officialInspectionId'],
          'conflictId': data['conflictId'],
          'rvStatus': data['rvStatus'],
        },
        'remotePhotoCount': items.length,
        'remoteVerifiedPhotoCount': items
            .where((e) => (e['upload_status'] ?? e['status']) == 'verified')
            .length,
        'answerCrossCheck': buildRvAnswerCrossCheck(draft, data['answers']),
        'photos': items
            .map(
              (e) => {
                'remotePhotoId': e['photo_id'] ?? e['photoId'],
                'slotCode': e['slot_code'] ?? e['slotCode'],
                'status': e['upload_status'] ?? e['status'],
                'sha256':
                    e['normalized_sha256'] ?? e['server_sha256'] ?? e['sha256'],
                'clientSha256': e['client_sha256'] ?? e['clientSha256'],
              },
            )
            .toList(),
      };
    } on DioException catch (error) {
      final parsed = ApiException.fromDio(error);
      if (parsed.statusCode == 404)
        return {
          'remoteInspectionExists': false,
          'staleServerInspectionIdCandidate': true,
          'error': _apiError(parsed),
        };
      throw parsed;
    }
  }

  Map<String, dynamic> _draft(
    RvDraft d,
    Map<String, CachedHydrant> cached,
    List<Map<String, dynamic>> queue,
    Object? remoteRaw,
  ) {
    final refs = d.photos.values.expand((e) => e).toList();
    final remote = remoteRaw is Map
        ? Map<String, dynamic>.from(remoteRaw)
        : const <String, dynamic>{};
    final remoteInspection = remote['remoteInspection'] is Map
        ? Map<String, dynamic>.from(remote['remoteInspection'] as Map)
        : const <String, dynamic>{};
    final remoteStatus = remoteInspection['status']?.toString();
    final answerCrossCheck = remote['answerCrossCheck'] is Map
        ? Map<String, dynamic>.from(remote['answerCrossCheck'] as Map)
        : buildRvAnswerCrossCheck(d, null);
    final captureIssues = _captureIssues(d);
    final issues = <String>[];
    if (const {'submitted', 'validated'}.contains(remoteStatus) &&
        d.localStatus != RvLocalStatus.submitted)
      issues.add('REMOTE_${remoteStatus!.toUpperCase()}_LOCAL_PENDING');
    if (remote['staleServerInspectionIdCandidate'] == true)
      issues.add('STALE_SERVER_INSPECTION_ID');
    if (d.serverHydrantId == null) issues.add('SERVER_HYDRANT_ID_MISSING');
    final ch = cached[d.hydrantId];
    if (ch?.remoteId != null &&
        d.serverHydrantId != null &&
        ch!.remoteId != d.serverHydrantId)
      issues.add('HYDRANT_REMOTE_ID_MISMATCH');
    final indexPoints = activeIndexBox.values.contains(d.clientInspectionId);
    if (indexPoints && d.isReadOnly)
      issues.add('ACTIVE_INDEX_POINTS_TO_COMPLETED');
    if (d.submitStatus == RvPartStatus.synced &&
        d.localStatus != RvLocalStatus.submitted)
      issues.add('SUBMIT_SYNCED_LOCAL_PENDING');
    if (d.serverInspectionId == null &&
        remote['remoteHydrant'] is Map &&
        (remote['remoteHydrant'] as Map)['exactAccountExists'] == false)
      issues.add('MANUAL_HYDRANT_NOT_CREATED');
    if (d.retryCount >= 20) issues.add('RETRY_STORM_CANDIDATE');
    return {
      'accountNumber': d.accountNumber,
      'localHydrantId': d.hydrantId,
      'serverHydrantId': d.serverHydrantId,
      'cachedHydrantRemoteId': ch?.remoteId,
      'clientInspectionId': d.clientInspectionId,
      'serverInspectionId': d.serverInspectionId,
      'officialInspectionId': d.officialInspectionId,
      'conflictId': d.conflictId,
      'visualReportId': d.visualReportId,
      'currentVersionId': d.currentVersionId,
      'localStatus': d.localStatus.name,
      'remoteStatus': d.remoteStatus,
      'currentStep': d.currentStep.name,
      'answersStatus': d.answersStatus.name,
      'photosStatus': d.photosStatus.name,
      'locationStatus': d.locationStatus.name,
      'signalStatus': d.signalStatus.name,
      'submitStatus': d.submitStatus.name,
      'hasPendingChanges': d.hasPendingChanges,
      'isReadOnly': d.isReadOnly,
      'inactiveClosure': d.inactiveClosure?.toJson(),
      'retryCount': d.retryCount,
      'nextRetryAt': d.nextRetryAt?.toIso8601String(),
      'lastAttemptAt': d.lastAttemptAt?.toIso8601String(),
      'updatedAt': d.updatedAt.toIso8601String(),
      'createdAt': d.createdAt.toIso8601String(),
      'lastSyncError': _safe(d.lastSyncError),
      'answersCount': d.answers.length,
      'answerCrossCheck': answerCrossCheck,
      'missingRequiredAnswers': null,
      'captureIssues': captureIssues,
      'photoReferenceCount': refs.length,
      'verifiedPhotoReferenceCount': refs
          .where((e) => e.status == RvPhotoUploadStatus.verified)
          .length,
      'pendingPhotoReferenceCount': refs
          .where(
            (e) =>
                e.status == RvPhotoUploadStatus.pending ||
                e.status == RvPhotoUploadStatus.uploading,
          )
          .length,
      'errorPhotoReferenceCount': refs
          .where((e) => e.status == RvPhotoUploadStatus.error)
          .length,
      'missingLocalPhotoReferenceCount': refs
          .where((e) => e.status == RvPhotoUploadStatus.missingLocal)
          .length,
      'generalPhotoCount': d.generalPhotos.length,
      'hasLocation': d.location != null,
      'hasSignal': d.signal != null,
      'hasParcelValveConfiguration': d.parcelValveConfiguration != null,
      'parcelValveCount': d.parcelValveConfiguration?.valves.length ?? 0,
      'activeIndexPointsToThisDraft': indexPoints,
      'syncQueueEntries': queue
          .where(
            (e) =>
                e['inspectionId'] == d.clientInspectionId ||
                e['entityId'] == d.clientInspectionId,
          )
          .toList(),
      'consistencyIssues': issues,
    };
  }

  List<Map<String, dynamic>> _photoRows(
    List<InspectionPhoto> photos,
    List<RvDraft> allDrafts,
    Map<String, dynamic> remote,
  ) => photos.map((photo) {
    final draft = allDrafts
        .where((d) => d.clientInspectionId == photo.inspectionId)
        .firstOrNull;
    final refs =
        draft?.photos.values
            .expand((e) => e)
            .where((e) => e.photoId == photo.id)
            .toList() ??
        const [];
    final ref = refs.firstOrNull;
    final snapshot = remote[draft?.clientInspectionId];
    final remotePhotos = snapshot is Map && snapshot['photos'] is List
        ? snapshot['photos'] as List
        : const [];
    Map? match;
    String method = 'none';
    String normalizedId(Object? value) => '${value ?? ''}'.trim().toLowerCase();
    for (final candidate in remotePhotos.whereType<Map>()) {
      if (ref?.serverPhotoId != null &&
          normalizedId(candidate['remotePhotoId']) ==
              normalizedId(ref!.serverPhotoId)) {
        match = candidate;
        method = 'serverPhotoId';
        break;
      }
      if (normalizedId(candidate['remotePhotoId']) == normalizedId(photo.id)) {
        match = candidate;
        method = 'photoId';
        break;
      }
      if (photo.sha256.isNotEmpty &&
          {
            candidate['sha256'],
            candidate['clientSha256'],
          }.contains(photo.sha256)) {
        match = candidate;
        method = 'hash';
        break;
      }
    }
    final media = mediaSyncBox.get(photo.id),
        work = _workStatus(photo.id),
        remoteVerified = match?['status'] == 'verified';
    final classification = photo.isDeleted
        ? 'DISCARDED_LOCAL_INACTIVE_DRAFT'
        : classifyDiagnosticPhoto(
            localFileExists: File(photo.localPath).existsSync(),
            remoteVerified: remoteVerified,
            localVerified: diagnosticLocalPhotoVerified(
              photo: photo,
              reference: ref,
              mediaQueueValue: media,
              mediaWorkStatus: work,
            ),
            mediaWorkStatus: work,
            hasDraft: draft != null,
            hasRemoteMatch: match != null,
          );
    return {
      'photoId': photo.id,
      'ownerUserId': photo.capturedByUserId,
      'clientInspectionId': draft?.clientInspectionId,
      'accountNumber': draft?.accountNumber,
      'serverInspectionId': draft?.serverInspectionId,
      'slotCode': ref?.slotCode ?? photo.category,
      'localFileName': p.basename(photo.localPath),
      'localPathPresent': File(photo.localPath).existsSync(),
      'fileSize': photo.fileSize,
      'clientSha256': photo.sha256,
      'receivedSha256': photo.receivedSha256,
      'syncStatus': photo.syncStatus.name,
      'deletedAt': photo.deletedAt?.toIso8601String(),
      'serverPhotoId': ref?.serverPhotoId ?? photo.remoteObjectKey,
      'serverSha256': photo.remoteSha256,
      'verifiedAt': photo.verifiedAt?.toIso8601String(),
      'lastError': _safe(photo.lastError),
      'updatedAt': photo.updatedAt.toIso8601String(),
      'mediaSyncQueueStatus': media,
      'mediaWorkQueueStatus': work,
      'rvPhotoReferenceStatus': ref?.status.name,
      'remoteMatch': match,
      'matchMethod': method,
      'diagnosticClassification': classification,
    };
  }).toList();

  List<Map<String, dynamic>> _captureIssues(RvDraft draft) {
    if (draft.localStatus == RvLocalStatus.inactive) {
      final closure = draft.inactiveClosure;
      final issues = <Map<String, dynamic>>[];
      void add(String code, String message) =>
          issues.add({'code': code, 'message': message});
      if (closure == null) {
        add(
          'inactive_closure_missing',
          'El cierre inactivo no contiene su registro de dominio.',
        );
        return issues;
      }
      if (closure.reasonCode != noHydrantAtLocationReasonCode) {
        add(
          'inactive_reason_incompatible',
          'El motivo del cierre inactivo no es compatible.',
        );
      }
      if (!closure.location.isValid) {
        add('inactive_location_invalid', 'La coordenada no es válida.');
      }
      if (closure.comment.trim().length < inactiveClosureCommentMinLength ||
          closure.comment.trim().length > inactiveClosureCommentMaxLength) {
        add('inactive_comment_invalid', 'El comentario no es válido.');
      }
      final referenced = draft
          .photosFor(noHydrantAtLocationPhotoSlot)
          .map((photo) => photo.photoId)
          .toSet();
      if (closure.photoIds.isEmpty ||
          !closure.photoIds.every(referenced.contains)) {
        add(
          'inactive_evidence_missing',
          'La evidencia fotográfica dedicada no está completa.',
        );
      }
      if (closure.closedByUserId.isEmpty || closure.deviceId.isEmpty) {
        add(
          'inactive_traceability_missing',
          'Falta trazabilidad de usuario o dispositivo.',
        );
      }
      return issues;
    }
    try {
      return [
        for (final issue in const RvValidator().validate(draft).issues)
          {
            'code': issue.code,
            'message': issue.message,
            'questionId': issue.questionId,
            'slotCode': issue.slotCode,
            'focusKey': issue.focusKey,
          },
      ];
    } on Object catch (error) {
      return [
        {
          'code': 'local_checklist_snapshot_unreadable',
          'message':
              'La captura se conserva, pero su checklist local requiere recuperación.',
          'errorType': error.runtimeType.toString(),
        },
      ];
    }
  }

  List<Map<String, dynamic>> _diagnostics() {
    final rows = <Map<String, dynamic>>[];
    for (final entry in diagnosticsBox.toMap().entries) {
      try {
        final value = Map<String, dynamic>.from(jsonDecode(entry.value) as Map);
        rows.add(Map<String, dynamic>.from(_sanitize(value) as Map));
      } catch (error) {
        rows.add({
          'key': '${entry.key}',
          'unreadable': true,
          'errorType': error.runtimeType.toString(),
        });
      }
    }
    rows.sort(
      (a, b) => '${b['timestamp'] ?? b['timestampUtc']}'.compareTo(
        '${a['timestamp'] ?? a['timestampUtc']}',
      ),
    );
    return rows.take(1000).toList();
  }

  List<Map<String, dynamic>> _activeIndex(List<RvDraft> allDrafts) {
    final result = <Map<String, dynamic>>[];
    for (final e in activeIndexBox.toMap().entries) {
      final id = '${e.value}';
      final doc = visualRepository.findById(id);
      final draft = allDrafts
          .where((d) => d.clientInspectionId == id)
          .firstOrNull;
      result.add({
        'key': '${e.key}',
        'documentId': id,
        'exists': doc != null,
        'inspectionStatus': doc?.status.name,
        'draftStatus': draft?.localStatus.name,
        'accountNumber': draft?.accountNumber,
        'stale':
            doc?.status == InspectionStatus.completed ||
            draft?.isReadOnly == true,
      });
    }
    return result;
  }

  List<Map<String, dynamic>> _mediaWork(List<InspectionPhoto> photos) {
    final ids = photos.map((e) => e.id).toSet();
    return mediaWorkBox
        .toMap()
        .entries
        .where((e) => ids.contains('${e.key}'))
        .map((e) {
          try {
            final value = Map<String, dynamic>.from(jsonDecode(e.value) as Map);
            final id = '${value['photoId'] ?? e.key}',
                status = '${value['status']}';
            return {
              ...value,
              'classification':
                  mediaSyncBox.get(id) == MediaSyncStatus.verified.name &&
                      status != 'verified'
                  ? 'LEGACY_STALE_PENDING'
                  : 'CONSISTENT',
            };
          } catch (error) {
            return {
              'photoId': '${e.key}',
              'classification': 'UNREADABLE',
              'errorType': error.runtimeType.toString(),
            };
          }
        })
        .toList();
  }

  List<Map<String, dynamic>> _crossChecks(
    List<Map<String, dynamic>> draftRows,
    List<Map<String, dynamic>> photoRows,
    List<Map<String, dynamic>> events,
    Map<String, dynamic> remote, {
    required bool authenticated,
  }) => draftRows
      .map((draft) {
        final id = '${draft['clientInspectionId']}';
        final relatedPhotos = photoRows
            .where((photo) => photo['clientInspectionId'] == id)
            .toList(growable: false);
        final relatedEvents = events
            .where((event) => event['clientInspectionId'] == id)
            .toList(growable: false);
        final snapshot = remote[id] is Map
            ? Map<String, dynamic>.from(remote[id] as Map)
            : const <String, dynamic>{};
        final remoteInspection = snapshot['remoteInspection'] is Map
            ? Map<String, dynamic>.from(snapshot['remoteInspection'] as Map)
            : const <String, dynamic>{};
        final answers = Map<String, dynamic>.from(
          draft['answerCrossCheck'] as Map? ?? const {},
        );
        final photoDifferences = <Map<String, dynamic>>[];
        var confirmedPhotos = 0;
        for (final photo in relatedPhotos) {
          final match = photo['remoteMatch'] is Map
              ? Map<String, dynamic>.from(photo['remoteMatch'] as Map)
              : const <String, dynamic>{};
          final localHash = '${photo['clientSha256'] ?? ''}'.toLowerCase();
          final remoteClientHash = '${match['clientSha256'] ?? ''}'
              .toLowerCase();
          final remoteServerHash = '${match['sha256'] ?? ''}'.toLowerCase();
          final hashMatches =
              localHash.isNotEmpty &&
              (localHash == remoteClientHash || localHash == remoteServerHash);
          final remoteVerified = match['status'] == 'verified';
          if (photo['localPathPresent'] == true &&
              remoteVerified &&
              hashMatches) {
            confirmedPhotos++;
          } else {
            photoDifferences.add({
              'photoId': photo['photoId'],
              'slotCode': photo['slotCode'],
              'localFilePresent': photo['localPathPresent'],
              'remoteMatch': match.isNotEmpty,
              'remoteVerified': remoteVerified,
              'hashMatches': hashMatches,
              'classification': photo['diagnosticClassification'],
            });
          }
        }
        final captureIssues = (draft['captureIssues'] as List? ?? const [])
            .whereType<Map>()
            .toList(growable: false);
        final localIntegrityIssue = relatedPhotos.any(
          (photo) => photo['localPathPresent'] != true,
        );
        final latestStatus = relatedEvents
            .map((event) => event['statusCode'])
            .whereType<num>()
            .map((status) => status.toInt())
            .firstOrNull;
        final hasContractConflict =
            const {
              'conflict',
              'versionConflict',
            }.contains(draft['localStatus']) ||
            const {409, 422}.contains(latestStatus) ||
            answers['localSerializationIssue'] != null;
        final remoteSubmitted = const {
          'submitted',
          'validated',
        }.contains(remoteInspection['status']);
        final answerMatches = answers['match'] == true;
        final photoMatches =
            relatedPhotos.isNotEmpty && confirmedPhotos == relatedPhotos.length;
        final inactiveClosure = draft['inactiveClosure'] is Map
            ? Map<String, dynamic>.from(draft['inactiveClosure'] as Map)
            : const <String, dynamic>{};
        final inactiveContractPending =
            draft['localStatus'] == RvLocalStatus.inactive.name &&
            inactiveClosure['syncStatus'] !=
                RvInactiveClosureSyncStatus.remoteVerified.name;
        final inactiveIntegrityIssue =
            draft['localStatus'] == RvLocalStatus.inactive.name &&
            captureIssues.isNotEmpty;

        late final String classification;
        late final String actionRequired;
        if (!authenticated || const {401, 403}.contains(latestStatus)) {
          classification = 'AUTHENTICATION_REQUIRED';
          actionRequired = 'Restaurar una sesión de campo válida y reintentar.';
        } else if (localIntegrityIssue || inactiveIntegrityIssue) {
          classification = 'LOCAL_INTEGRITY_REQUIRES_RECOVERY';
          actionRequired =
              'Conservar el documento y recuperar el archivo local faltante; no reenviar evidencia distinta.';
        } else if (hasContractConflict) {
          classification = 'CONTRACT_CONFLICT_REQUIRES_ACTION';
          actionRequired =
              'Resolver el código de dominio conservando el payload local exacto.';
        } else if (inactiveContractPending) {
          classification = 'REMOTE_CONFIRMATION_PENDING';
          actionRequired =
              'Conservar el cierre local sin enviarlo como revisión normal; '
              'esperar el contrato exclusivo de cierre inactivo.';
        } else if (captureIssues.isNotEmpty) {
          classification = 'CAPTURE_INCOMPLETE_REQUIRES_TECHNICIAN';
          actionRequired =
              'El técnico debe completar únicamente los campos señalados; no autocompletar.';
        } else if (!remoteSubmitted || !answerMatches || !photoMatches) {
          classification = 'REMOTE_CONFIRMATION_PENDING';
          actionRequired =
              'Reconciliar por clientInspectionId y confirmar respuestas, fotos y submit sin descartar la captura.';
        } else {
          classification = 'FULLY_CONFIRMED';
          actionRequired = 'Ninguna.';
        }

        return <String, dynamic>{
          'clientInspectionId': id,
          'accountNumber': draft['accountNumber'],
          'serverInspectionId': draft['serverInspectionId'],
          'documentStatus': 'LEGIBLE',
          'answerManifest': answers,
          'photosExpected': relatedPhotos.length,
          'photosLocalPresent': relatedPhotos
              .where((photo) => photo['localPathPresent'] == true)
              .length,
          'photosRemoteConfirmed': confirmedPhotos,
          'photoDifferences': photoDifferences,
          'captureIssues': captureIssues,
          'submitEvidence': {
            'remoteStatus': remoteInspection['status'],
            'submittedAt': remoteInspection['submittedAt'],
            'officialInspectionId': remoteInspection['officialInspectionId'],
          },
          'finalClassification': classification,
          'actionRequired': actionRequired,
          'requestIds': relatedEvents
              .map((event) => event['requestId'])
              .whereType<String>()
              .toSet()
              .toList(growable: false),
        };
      })
      .toList(growable: false);

  String? _workStatus(String id) {
    final raw = mediaWorkBox.get(id);
    if (raw == null) return null;
    try {
      return '${(jsonDecode(raw) as Map)['status']}';
    } on Object {
      return 'unreadable';
    }
  }

  Map<String, dynamic> _boxes() => {
    for (final b in [
      visualRepository.documents,
      activeIndexBox,
      photoBox,
      mediaSyncBox,
      mediaWorkBox,
      syncQueue.box,
      diagnosticsBox,
      ?receiptsBox,
      hydrantBox,
      if (Hive.isBoxOpen('operation_journal_v1'))
        Hive.box<String>('operation_journal_v1'),
      if (Hive.isBoxOpen('rv_recovery_v1')) Hive.box<String>('rv_recovery_v1'),
      if (Hive.isBoxOpen('rv_recovery_snapshots_v1'))
        Hive.box<String>('rv_recovery_snapshots_v1'),
      if (Hive.isBoxOpen('quarantine_documents_v1'))
        Hive.box<String>('quarantine_documents_v1'),
    ])
      b.name: {
        'name': b.name,
        'recordCount': b.length,
        'unreadableCount': _unreadable(b),
      },
  };

  List<Map<String, dynamic>> _rawBoxRows(String name) {
    if (!Hive.isBoxOpen(name)) return const [];
    final result = <Map<String, dynamic>>[];
    for (final entry in Hive.box<String>(name).toMap().entries) {
      try {
        final decoded = jsonDecode(entry.value);
        result.add({
          'key': '${entry.key}',
          'readable': true,
          'value': _sanitize(decoded),
        });
      } on Object catch (error) {
        result.add({
          'key': '${entry.key}',
          'readable': false,
          'rawSha256': sha256.convert(utf8.encode(entry.value)).toString(),
          'rawUtf8Bytes': utf8.encode(entry.value).length,
          'errorType': error.runtimeType.toString(),
        });
      }
    }
    return result;
  }

  int _unreadable(Box<String> box) {
    var n = 0;
    for (final value in box.values) {
      try {
        jsonDecode(value);
      } on Object {
        n++;
      }
    }
    return n;
  }

  Map<String, dynamic> _cachedHydrant(CachedHydrant h) => {
    'localHydrantId': h.hydrantId,
    'accountNumber': h.accountNumber,
    'remoteId': h.remoteId,
    'source': h.source,
    'active': h.isActive,
    'rvStatus': h.rvStatus,
    'officialInspectionId': h.officialInspectionId,
  };
  List<Map<String, dynamic>> _focus(
    List<Map<String, dynamic>> ds,
    List<Map<String, dynamic>> ps,
    List<Map<String, dynamic>> events,
    Map<String, dynamic> remote,
    List<CachedHydrant> hydrants,
  ) => focusAccounts.map((account) {
    String normalized(Object? value) =>
        '${value ?? ''}'.trim().toUpperCase().replaceAll(RegExp(r'\s+'), '');
    final target = normalized(account);
    final d = ds
        .where((e) => normalized(e['accountNumber']) == target)
        .toList();
    final p = ps
        .where((e) => normalized(e['accountNumber']) == target)
        .toList();
    final ev = events
        .where((e) => normalized(e['accountNumber']) == target)
        .toList();
    final projected = hydrants
        .where((e) => normalized(e.accountNumber) == target)
        .toList();
    final rem = d
        .map((e) => remote[e['clientInspectionId']])
        .whereType<Map>()
        .toList();
    final remoteSnapshotExists = rem.any(
      (e) => (e['remoteHydrant'] as Map?)?['exactAccountExists'] == true,
    );
    final projectionExists = projected.isNotEmpty;
    return {
      'accountNumber': account,
      'normalizedAccountNumber': target,
      'localHydrantExists': projectionExists,
      'remoteHydrantExists': projectionExists || remoteSnapshotExists,
      'localReviewExists': d.isNotEmpty,
      'remoteInspectionExists': rem.any((e) => e['remoteInspection'] is Map),
      'officialReportExists': projected.any(
        (e) => e.officialInspectionId != null,
      ),
      'remoteHydrantSource': projectionExists
          ? 'hydrants_projection'
          : remoteSnapshotExists
          ? 'remote_snapshot'
          : 'not_found',
      'internalContradiction':
          projectionExists && !(projectionExists || remoteSnapshotExists),
      'draftCount': d.length,
      'localStatuses': d.map((e) => e['localStatus']).toList(),
      'serverInspectionIds': d
          .map((e) => e['serverInspectionId'])
          .whereType<String>()
          .toList(),
      'remoteInspectionStatuses': rem
          .map((e) => (e['remoteInspection'] as Map?)?['status'])
          .whereType<Object>()
          .toList(),
      'photoLocalCount': p.length,
      'photoPendingCount': p.where(diagnosticPhotoRowIsPending).length,
      'remotePhotoCount': rem.fold<int>(
        0,
        (n, e) => n + ((e['remotePhotoCount'] as num?)?.toInt() ?? 0),
      ),
      'lastDiagnosticEvent': ev.firstOrNull,
      'lastHttpStatus': ev.firstOrNull?['statusCode'],
      'lastEndpoint': ev.firstOrNull?['logicalEndpoint'],
      'lastDomainCode': ev.firstOrNull?['domainCode'],
    };
  }).toList();
  Map<String, int> _counts(List<Map<String, dynamic>> rows, String key) {
    final out = <String, int>{};
    for (final row in rows) {
      final value = '${row[key]}';
      out[value] = (out[value] ?? 0) + 1;
    }
    return out;
  }

  Future<Map<String, dynamic>> _device(String installationId) async {
    final info = await DeviceInfoPlugin().androidInfo;
    final connectivity = await Connectivity().checkConnectivity();
    return {
      'installationId': installationId,
      'manufacturer': info.manufacturer,
      'model': info.model,
      'androidVersion': info.version.release,
      'sdkLevel': info.version.sdkInt,
      'locale': Platform.localeName,
      'timezone': DateTime.now().timeZoneName,
      'connectivityTypes': connectivity.map((e) => e.name).toList(),
      // Android does not expose these values through the currently bundled
      // cross-platform plugins. Keep explicit nullable schema fields instead
      // of guessing or requiring a new privileged native channel.
      'storageAvailableApproxBytes': null,
      'firstInstallTime': null,
      'lastUpdateTime': null,
    };
  }

  Map<String, dynamic> _apiError(ApiException e) => {
    'kind': e.kind.name,
    'message': _safe(e.message),
    'statusCode': e.statusCode,
    'requestId': e.requestId,
    'domainCode': e.domainCode,
    'problemType': e.problemType,
    'problemTitle': e.problemTitle,
    'httpMethod': e.httpMethod,
    'logicalEndpoint': e.logicalEndpoint,
    'originalMessage': _safe(e.originalMessage),
    'retryAfterSeconds': e.retryAfter?.inSeconds,
    'dioExceptionType': e.dioExceptionType,
  };
  bool _stopRemote(ApiException e) =>
      e.kind == ApiErrorKind.rateLimited ||
      e.kind == ApiErrorKind.serverUnavailable ||
      e.kind == ApiErrorKind.serverError ||
      e.kind == ApiErrorKind.timeout ||
      e.kind == ApiErrorKind.offline;
  String? _safe(String? value) => value
      ?.replaceAll(
        RegExp(r'Bearer\s+[A-Za-z0-9._-]+', caseSensitive: false),
        'Bearer [REDACTED]',
      )
      .replaceAll(
        RegExp(r'(access|refresh)?token["\s:=]+[^,}\s]+', caseSensitive: false),
        'token=[REDACTED]',
      );
  Object? _sanitize(Object? value) {
    if (value is Map) {
      final out = <String, dynamic>{};
      for (final e in value.entries) {
        final key = '${e.key}';
        if (RegExp(
          r'authorization|accessToken|refreshToken|password|cookie',
          caseSensitive: false,
        ).hasMatch(key))
          continue;
        if (RegExp(
          r'latitude|longitude|coordinates|localPath$',
          caseSensitive: false,
        ).hasMatch(key))
          continue;
        out[key] = _sanitize(e.value);
      }
      return out;
    }
    if (value is List) return value.map(_sanitize).toList();
    if (value is String) return _safe(value);
    return value;
  }
}
