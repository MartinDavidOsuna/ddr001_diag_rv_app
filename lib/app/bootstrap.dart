import 'dart:convert';

import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/services/app_state.dart';
import '../data/local/visual_inspection_repository.dart';
import '../data/local/functional_repositories.dart';
import '../data/local/integrity_audit_service.dart';
import '../data/local/operation_journal_repository.dart';
import '../data/local/quarantine_repository.dart';
import '../data/local/recovery_coordinator.dart';
import '../data/local/media_reconciliation_service.dart';

Future<AppState> bootstrap() async {
  await initializeDateFormatting('es');
  await Hive.initFlutter();
  final traceBox = await Hive.openBox<String>('trace_events');
  final syncBox = await Hive.openBox<String>('sync_queue');
  final mediaBox = await Hive.openBox<String>('media_sync_queue');
  final syncedTraceBox = await Hive.openBox<String>('synced_trace_ids');
  final inspectionBox = await Hive.openBox<String>('visual_inspections_v1');
  final inspectionIndexBox = await Hive.openBox<String>(
    'active_inspection_index_v1',
  );
  await Hive.openBox<String>('damage_records_v1');
  await Hive.openBox<String>('inspection_photos_v1');
  await Hive.openBox<String>('hydrant_configurations_v1');
  await Hive.openBox<String>('local_hydrants_v1');
  await Hive.openBox<String>('media_work_queue_v1');
  final functionalEligibilityBox = await Hive.openBox<String>(
    'functional_eligibility_v1',
  );
  final functionalInspectionBox = await Hive.openBox<String>(
    'functional_inspections_v1',
  );
  final functionalInspectionIndexBox = await Hive.openBox<String>(
    'active_functional_inspection_index_v1',
  );
  await Hive.openBox<String>('measurement_series_v1');
  await Hive.openBox<String>('instrument_records_v1');
  await Hive.openBox<String>('functional_valve_tests_v1');
  await Hive.openBox<String>('alarm_tests_v1');
  await Hive.openBox<String>('functional_results_v1');
  await Hive.openBox<String>('functional_test_records_v1');
  final operationJournalBox = await Hive.openBox<String>(
    'operation_journal_v1',
  );
  final quarantineBox = await Hive.openBox<String>('quarantine_documents_v1');
  await Hive.openBox<String>('report_revisions_v1');
  await Hive.openBox<String>('valve_records_v1');
  await Hive.openBox<String>('reducer_runs_v1');
  await Hive.openBox<String>('alarm_attempts_v1');
  await Hive.openBox<String>('instrument_snapshots_v1');
  final integrityReportBox = await Hive.openBox<String>(
    'integrity_audit_reports_v1',
  );
  await Hive.openBox<String>('gallery_ui_state_v1');
  final recovery = await RecoveryCoordinator(
    auditService: const IntegrityAuditService(),
    journal: OperationJournalRepository(operationJournalBox),
    quarantine: QuarantineRepository(quarantineBox),
  ).runLightweight();
  await integrityReportBox.put(
    recovery.audit.id,
    jsonEncode(recovery.audit.toJson()),
  );
  await MediaReconciliationService().reconcile();
  final preferences = await SharedPreferences.getInstance();
  final packageInfo = await PackageInfo.fromPlatform();
  final state = AppState(
    preferences: preferences,
    traceBox: traceBox,
    syncBox: syncBox,
    mediaBox: mediaBox,
    syncedTraceBox: syncedTraceBox,
    packageInfo: packageInfo,
    visualInspectionRepository: VisualInspectionRepository(
      documents: inspectionBox,
      index: inspectionIndexBox,
    ),
    functionalEligibilityRepository: FunctionalEligibilityRepository(
      functionalEligibilityBox,
    ),
    functionalInspectionRepository: FunctionalInspectionRepository(
      documents: functionalInspectionBox,
      index: functionalInspectionIndexBox,
    ),
  );
  await state.initialize();
  return state;
}
