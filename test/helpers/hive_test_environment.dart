import 'dart:io';

import 'package:hive_ce/hive.dart';

const stage4BoxNames = <String>[
  'active_inspection_index_v1',
  'active_functional_inspection_index_v1',
  'visual_inspections_v1',
  'functional_inspections_v1',
  'measurement_series_v1',
  'instrument_records_v1',
  'functional_results_v1',
  'inspection_photos_v1',
  'media_work_queue_v1',
  'media_sync_queue',
  'operation_journal_v1',
  'quarantine_v1',
  'sync_queue',
  'trace_events',
  'synced_trace_ids',
  'functional_eligibility_v1',
  'local_hydrants_v1',
  'report_revisions_v1',
];

class HiveTestEnvironment {
  late final Directory directory;

  Future<void> open({Iterable<String> boxes = stage4BoxNames}) async {
    directory = await Directory.systemTemp.createTemp('ddr001diag_test_');
    Hive.init(directory.path);
    for (final name in boxes) {
      await Hive.openBox<String>(name);
    }
  }

  Future<void> close() async {
    await Hive.close();
    if (directory.existsSync()) directory.deleteSync(recursive: true);
  }
}
