// The exporter intentionally continues after malformed legacy records.
// ignore_for_file: curly_braces_in_flow_control_structures, empty_catches, unnecessary_string_interpolations

import 'dart:convert';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
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
  ];

  final AppConfig config;
  final PackageInfo packageInfo;
  final SessionStorage sessionStorage;
  final VisualInspectionRepository visualRepository;
  final RvDraftRepository drafts;
  final SyncQueueRepository syncQueue;
  final Box<String> hydrantBox, activeIndexBox, photoBox;
  final Box<String> mediaSyncBox, mediaWorkBox, diagnosticsBox;
  final DiagnosticDeviceProvider? deviceProvider;
  final DiagnosticDirectoryProvider? directoryProvider;
  final DiagnosticRemoteProvider? remoteProvider;

  Future<RvDiagnosticExportResult> export({
    required Map<String, dynamic> screenSummary,
    required List<dynamic> hydrants,
    DiagnosticProgress? onProgress,
    bool queryRemote = true,
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
    final indexRows = _activeIndex(allDrafts);
    final mediaWorkRows = _mediaWork(localPhotos);
    final checks = <Map<String, dynamic>>[
      for (final row in draftRows)
        for (final issue in row['consistencyIssues'] as List)
          {
            'clientInspectionId': row['clientInspectionId'],
            'accountNumber': row['accountNumber'],
            'issue': issue,
          },
    ];
    final now = DateTime.now().toUtc();
    final document = <String, dynamic>{
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
          defaultValue: 'unknown',
        ),
        'buildDateUtc': const String.fromEnvironment(
          'BUILD_DATE_UTC',
          defaultValue: 'unknown',
        ),
        'diagnosticSchemaVersion': schemaVersion,
      },
      'device':
          await (deviceProvider?.call(installationId) ??
              _device(installationId)),
      'session': {
        'userId': session?.userId,
        'displayName': session?.name,
        'crewId': session?.crewId,
        'crewName': session?.crew,
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
        'photoClassifications': _counts(photoRows, 'diagnosticClassification'),
      },
      'boxes': _boxes(),
      'drafts': draftRows,
      'photos': photoRows,
      'syncQueue': queue,
      'mediaWorkQueue': mediaWorkRows,
      'diagnostics': diagnosticEvents,
      'hydrants': cached.values.map((value) => _cachedHydrant(value)).toList(),
      'activeInspectionIndex': indexRows,
      'remoteSnapshot': {'complete': remoteComplete, 'drafts': remote},
      'focusCases': _focus(draftRows, photoRows, diagnosticEvents, remote),
      'consistencyChecks': checks,
      'errors': errors,
    };
    onProgress?.call('Generando archivo...');
    final directory =
        await (directoryProvider?.call() ?? getApplicationDocumentsDirectory());
    final stamp = now
        .toIso8601String()
        .replaceAll(RegExp(r'[-:]'), '')
        .replaceAll('.000', '')
        .replaceAll(RegExp(r'[^0-9TZ]'), '');
    final file = File(
      p.join(directory.path, 'DDR001_RV_DIAGNOSTIC_v60_$stamp.json'),
    );
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
      'retryCount': d.retryCount,
      'nextRetryAt': d.nextRetryAt?.toIso8601String(),
      'lastAttemptAt': d.lastAttemptAt?.toIso8601String(),
      'updatedAt': d.updatedAt.toIso8601String(),
      'createdAt': d.createdAt.toIso8601String(),
      'lastSyncError': _safe(d.lastSyncError),
      'answersCount': d.answers.length,
      'missingRequiredAnswers': null,
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
    for (final candidate in remotePhotos.whereType<Map>()) {
      if (ref?.serverPhotoId != null &&
          candidate['remotePhotoId'] == ref!.serverPhotoId) {
        match = candidate;
        method = 'serverPhotoId';
        break;
      }
      if (candidate['remotePhotoId'] == photo.id) {
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
    final classification = classifyDiagnosticPhoto(
      localFileExists: File(photo.localPath).existsSync(),
      remoteVerified: remoteVerified,
      localVerified: media == MediaSyncStatus.verified.name,
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
      'syncStatus': photo.syncStatus.name,
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
      hydrantBox,
    ])
      b.name: {
        'name': b.name,
        'recordCount': b.length,
        'unreadableCount': _unreadable(b),
      },
  };
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
  ) => focusAccounts.map((account) {
    final d = ds.where((e) => e['accountNumber'] == account).toList();
    final p = ps.where((e) => e['accountNumber'] == account).toList();
    final ev = events.where((e) => e['accountNumber'] == account).toList();
    final rem = d
        .map((e) => remote[e['clientInspectionId']])
        .whereType<Map>()
        .toList();
    return {
      'accountNumber': account,
      'localHydrantExists': d.isNotEmpty,
      'remoteHydrantExists': rem.any(
        (e) => (e['remoteHydrant'] as Map?)?['exactAccountExists'] == true,
      ),
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
      'photoPendingCount': p
          .where((e) => e['mediaSyncQueueStatus'] != 'verified')
          .length,
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
