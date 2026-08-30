import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

import 'app/bootstrap.dart';
import 'core/persistence/versioned_json_codec.dart';
import 'core/services/app_state.dart';
import 'features/inspections/domain/rv_sync_state.dart';

const reportChannel = MethodChannel('com.aquafim.ddr001diag/diagnostic_report');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const DiagnosticApp());
}

class DiagnosticApp extends StatelessWidget {
  const DiagnosticApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: ThemeData(colorSchemeSeed: const Color(0xff075985)),
    home: const DiagnosticPage(),
  );
}

class DiagnosticPage extends StatefulWidget {
  const DiagnosticPage({super.key});
  @override
  State<DiagnosticPage> createState() => _DiagnosticPageState();
}

class _DiagnosticPageState extends State<DiagnosticPage> {
  bool running = false;
  String status = 'Listo. El análisis no modifica ni sincroniza datos.';
  String? path;

  Future<void> analyze() async {
    setState(() {
      running = true;
      status = 'Analizando…';
      path = null;
    });
    try {
      final result = await ActiveDiagnosticRunner(
        onTask: (task) {
          if (mounted) setState(() => status = task);
        },
      ).run();
      if (mounted) {
        setState(() {
          path = result;
          status = 'Reporte generado correctamente.';
        });
      }
    } on Object catch (error) {
      if (mounted) {
        setState(() => status = 'Falló el análisis: ${error.runtimeType}.');
      }
    } finally {
      if (mounted) setState(() => running = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Diagnóstico RV de campo')),
    body: Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Icon(Icons.health_and_safety_outlined, size: 72),
              const SizedBox(height: 16),
              const Text(
                'Herramienta temporal de sólo lectura. No elimina drafts, fotos, caché ni sesiones.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: running ? null : analyze,
                icon: running
                    ? const SizedBox.square(
                        dimension: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.manage_search),
                label: const Text('Iniciar análisis'),
              ),
              if (path != null) ...[
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: () =>
                      reportChannel.invokeMethod<void>('share', {'path': path}),
                  icon: const Icon(Icons.share),
                  label: const Text('Compartir reporte TXT'),
                ),
              ],
              const SizedBox(height: 20),
              Text(status, textAlign: TextAlign.center),
            ],
          ),
        ),
      ),
    ),
  );
}

class ActiveDiagnosticRunner {
  ActiveDiagnosticRunner({required this.onTask});
  final ValueChanged<String> onTask;

  Future<String> run() async {
    final events = <String>[];
    void event(String value) {
      events.add('${DateTime.now().toUtc().toIso8601String()} $value');
      onTask(value);
    }

    event('Cargando sesión y datos locales');
    late final AppState state;
    try {
      state = await bootstrap(onStatus: event, startRemoteServices: false);
    } on Object catch (error, stackTrace) {
      events.add(
        'bootstrapError runtimeType=${error.runtimeType} message=$error',
      );
      events.add('bootstrapStackTrace=$stackTrace');
      event('Generando reporte del error de inicialización');
      return DiagnosticReport().generate(events: events);
    }

    void observe() {
      final account = state.syncingReport;
      onTask(
        account == null
            ? 'Sincronizando: ${state.syncStage.name}'
            : 'Sincronizando cuenta $account',
      );
    }

    state.addListener(observe);
    try {
      event('Esperando conexión con el servidor');
      final deadline = DateTime.now().add(const Duration(seconds: 45));
      while (!state.online && DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 500));
      }
      if (!state.authenticated) {
        events.add('syncSkipped reason=no_authenticated_session');
      } else if (!state.online) {
        events.add('syncSkipped reason=api_unavailable_after_45_seconds');
      } else {
        event('Intentando subir todas las revisiones pendientes');
        final drafts = state.rvDraftRepository.pending();
        var completed = 0, warnings = 0, conflicts = 0;
        for (final draft in drafts) {
          event('Sincronizando cuenta ${draft.accountNumber}');
          try {
            final result = await state.inspectionSyncCoordinator.synchronize(
              draft,
              forceRetry: true,
              submit:
                  draft.localStatus == RvLocalStatus.submitPending ||
                  draft.localStatus == RvLocalStatus.readyToSubmit ||
                  draft.submitStatus == RvPartStatus.pending ||
                  draft.submitStatus == RvPartStatus.syncing,
            );
            completed++;
            if (result.lastSyncError != null) {
              warnings++;
              events.add(
                'draftResult account=${draft.accountNumber} '
                'status=${result.localStatus.name} step=${result.currentStep.name} '
                'error=${result.lastSyncError}',
              );
            }
            final diagnostic = state
                .inspectionSyncCoordinator
                .failureDiagnostics[draft.clientInspectionId];
            if (diagnostic != null) {
              events.add('technicalFailure=${jsonEncode(diagnostic)}');
            }
            if (result.localStatus == RvLocalStatus.conflict ||
                result.localStatus == RvLocalStatus.versionConflict) {
              conflicts++;
            }
          } on Object catch (error, stackTrace) {
            warnings++;
            events.add(
              'draftException account=${draft.accountNumber} '
              'runtimeType=${error.runtimeType} message=$error',
            );
            events.add('draftStackTrace=$stackTrace');
          }
          await Future<void>.delayed(const Duration(seconds: 2));
        }
        events.add(
          'syncResult total=${drafts.length} completed=$completed '
          'warnings=$warnings conflicts=$conflicts',
        );
        event('Actualizando estados del servidor');
        try {
          await state.synchronizeAssignments();
        } on Object catch (error, stackTrace) {
          events.add(
            'projectionError runtimeType=${error.runtimeType} message=$error',
          );
          events.add('projectionStackTrace=$stackTrace');
        }
      }
    } finally {
      state.removeListener(observe);
    }
    event('Recopilando estados y errores finales');
    return DiagnosticReport().generate(events: events);
  }
}

class DiagnosticReport {
  static const boxes = <String>[
    'visual_inspections_v1',
    'active_inspection_index_v1',
    'inspection_photos_v1',
    'media_sync_queue',
    'media_work_queue_v1',
    'rv_dynamic_catalogs_v1',
    'local_hydrants_v1',
    'trace_events',
  ];

  Future<String> generate({List<String> events = const []}) async {
    await Hive.initFlutter();
    final opened = <String, Box<String>>{};
    for (final name in boxes) {
      opened[name] = await Hive.openBox<String>(name);
    }
    final info = await PackageInfo.fromPlatform();
    final now = DateTime.now().toUtc();
    final out = StringBuffer()
      ..writeln('DDR001_RV_DIAGNOSTIC schema=1')
      ..writeln('generatedAtUtc=${now.toIso8601String()}')
      ..writeln('appVersion=${info.version}+${info.buildNumber}')
      ..writeln('mode=ACTIVE_RECOVERY networkRequests=enabled')
      ..writeln(
        'privacy=no_tokens,no_coordinates,no_answer_values,no_photo_binary,no_local_paths',
      )
      ..writeln()
      ..writeln('[runEvents]');
    for (final event in events) {
      out.writeln(_safe(event));
    }
    out.writeln();
    for (final entry in opened.entries) {
      out.writeln('box.${entry.key}.records=${entry.value.length}');
    }
    out.writeln();

    final photoBox = opened['inspection_photos_v1']!;
    final photos = <String, Map<String, dynamic>>{};
    var invalidPhotos = 0;
    for (final entry in photoBox.toMap().entries) {
      try {
        photos['${entry.key}'] = Map<String, dynamic>.from(
          jsonDecode(entry.value) as Map,
        );
      } on Object {
        invalidPhotos++;
      }
    }
    out.writeln('invalidPhotoRecords=$invalidPhotos');

    final draftBox = opened['visual_inspections_v1']!;
    var invalidDrafts = 0;
    final drafts = <Map<String, dynamic>>[];
    for (final raw in draftBox.values) {
      try {
        final payload = VersionedJsonCodec.decode(raw).payload;
        final rvDraft = payload['rvDynamicDraft'];
        if (rvDraft is Map) {
          drafts.add(Map<String, dynamic>.from(rvDraft));
        }
      } on Object catch (e) {
        invalidDrafts++;
        out.writeln('invalidDraft.runtimeType=${e.runtimeType}');
      }
    }
    drafts.sort(
      (a, b) => '${a['accountNumber']}'.compareTo('${b['accountNumber']}'),
    );
    out
      ..writeln('invalidDraftRecords=$invalidDrafts')
      ..writeln('validDraftRecords=${drafts.length}')
      ..writeln();
    for (final d in drafts) {
      await _draft(out, d, photos);
    }

    _summarizeJsonBox(out, 'media_sync_queue', opened['media_sync_queue']!);
    _summarizeJsonBox(
      out,
      'media_work_queue_v1',
      opened['media_work_queue_v1']!,
    );
    _summarizeJsonBox(
      out,
      'rv_dynamic_catalogs_v1',
      opened['rv_dynamic_catalogs_v1']!,
    );
    _summarizeJsonBox(out, 'trace_events', opened['trace_events']!);
    final dir =
        await getExternalStorageDirectory() ?? await getTemporaryDirectory();
    final file = File(
      '${dir.path}${Platform.pathSeparator}rv-diagnostic-${now.toIso8601String().replaceAll(':', '-')}.txt',
    );
    await file.writeAsString(out.toString(), flush: true);
    return file.path;
  }

  Future<void> _draft(
    StringBuffer out,
    Map<String, dynamic> d,
    Map<String, Map<String, dynamic>> photos,
  ) async {
    final rawRefs = d['photos'];
    final refs = <String, List<Map<String, dynamic>>>{};
    if (rawRefs is Map) {
      for (final e in rawRefs.entries) {
        refs['${e.key}'] = [
          for (final x in e.value is List ? e.value as List : const [])
            if (x is Map) Map<String, dynamic>.from(x),
        ];
      }
    }
    var present = 0, missing = 0, unresolved = 0;
    final slots = <String>[];
    for (final e in refs.entries) {
      final states = <String, int>{};
      for (final ref in e.value) {
        final state = '${ref['status'] ?? 'unknown'}';
        states[state] = (states[state] ?? 0) + 1;
        final photo = photos['${ref['photoId']}'];
        if (photo == null) {
          unresolved++;
          continue;
        }
        final localPath = photo['localPath']?.toString();
        if (localPath != null && await File(localPath).exists()) {
          present++;
        } else {
          missing++;
        }
      }
      slots.add(
        '${e.key}:${states.entries.map((x) => '${x.key}=${x.value}').join(',')}',
      );
    }
    final answers = d['answers'] is Map ? d['answers'] as Map : const {};
    final config = d['parcelValveConfiguration'] is Map
        ? d['parcelValveConfiguration'] as Map
        : null;
    final valves = config?['valves'] is List
        ? config!['valves'] as List
        : const [];
    out.writeln('[draft]');
    for (final key in const [
      'accountNumber',
      'hydrantId',
      'clientInspectionId',
      'serverInspectionId',
      'officialInspectionId',
      'fieldSessionId',
      'checklistId',
      'checklistVersion',
      'createdAt',
      'updatedAt',
      'localStatus',
      'remoteStatus',
      'currentStep',
      'answersStatus',
      'photosStatus',
      'locationStatus',
      'signalStatus',
      'submitStatus',
      'lastAttemptAt',
      'nextRetryAt',
      'retryCount',
      'lastSyncError',
    ]) {
      out.writeln('$key=${_safe(d[key])}');
    }
    out
      ..writeln('answerCount=${answers.length}')
      ..writeln('locationCaptured=${d['location'] != null}')
      ..writeln('signalCaptured=${d['signal'] != null}')
      ..writeln('parcelValveConfigurationPresent=${config != null}')
      ..writeln('parcelValveCount=${valves.length}')
      ..writeln(
        'photoReferenceCount=${refs.values.fold<int>(0, (n, x) => n + x.length)}',
      )
      ..writeln('photoFilesPresent=$present')
      ..writeln('photoFilesMissing=$missing')
      ..writeln('photoRecordsUnresolved=$unresolved')
      ..writeln('photoSlots=${slots.join(';')}')
      ..writeln();
  }

  void _summarizeJsonBox(StringBuffer out, String name, Box<String> box) {
    final states = <String, int>{};
    var invalid = 0;
    for (final raw in box.values) {
      try {
        final x = jsonDecode(raw);
        final state = x is Map
            ? '${x['status'] ?? x['syncStatus'] ?? x['kind'] ?? 'record'}'
            : raw;
        states[state] = (states[state] ?? 0) + 1;
      } on Object {
        states[raw] = (states[raw] ?? 0) + 1;
        invalid++;
      }
    }
    out.writeln(
      'summary.$name=${states.entries.map((e) => '${_safe(e.key)}:${e.value}').join(',')} invalidJson=$invalid',
    );
  }

  String _safe(Object? value) => value == null
      ? '-'
      : '$value'
            .replaceAll(RegExp(r'[\r\n]+'), ' ')
            .replaceAll(
              RegExp(r'bearer\s+[A-Za-z0-9._~+/-]+=*', caseSensitive: false),
              '[REDACTED]',
            );
}
