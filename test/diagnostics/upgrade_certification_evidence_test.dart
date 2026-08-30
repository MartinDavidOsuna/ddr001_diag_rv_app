import 'dart:convert';
import 'dart:io';

import 'package:ddr001diag/features/diagnostics/upgrade_certification_evidence.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:package_info_plus/package_info_plus.dart';

void main() {
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('rv-cert-evidence-');
    Hive.init(root.path);
    for (final name in [
      'visual_inspections_v1',
      'active_inspection_index_v1',
      'inspection_photos_v1',
      'media_sync_queue',
      'media_work_queue_v1',
      'sync_queue',
      'operation_journal_v1',
      'rv_recovery_v1',
      'rv_recovery_snapshots_v1',
      'quarantine_documents_v1',
    ]) {
      await Hive.openBox<String>(name);
    }
  });

  tearDown(() async {
    await Hive.close();
    await root.delete(recursive: true);
  });

  test('captures raw identities and physical bytes before recovery', () async {
    final photoFile = File('${root.path}/photo.jpg');
    await photoFile.writeAsBytes([1, 2, 3, 4], flush: true);
    await Hive.box<String>('visual_inspections_v1').put(
      'draft-1',
      jsonEncode({
        'clientInspectionId': 'draft-1',
        'serverInspectionId': 'server-1',
        'accountNumber': '995',
      }),
    );
    await Hive.box<String>('inspection_photos_v1').put(
      'photo-1',
      jsonEncode({
        'id': 'photo-1',
        'inspectionId': 'draft-1',
        'slotCode': 'front',
        'sha256': 'persisted-sha',
        'fileSize': 4,
        'localPath': photoFile.path,
      }),
    );
    await Hive.box<String>('media_sync_queue').put('legacy', 'verified');

    final result = await const UpgradeCertificationEvidence()
        .capturePreRecovery(
          packageInfo: PackageInfo(
            appName: 'DDR001',
            packageName: 'com.aquafim.ddr001diag',
            version: '1.0.1',
            buildNumber: '101',
          ),
          directory: root,
          now: DateTime.utc(2026, 8, 27, 23),
        );
    final document = Map<String, dynamic>.from(
      jsonDecode(await result.readAsString()) as Map,
    );

    expect(document['evidenceType'], 'PRE_RECOVERY');
    expect(
      (document['boxes'] as Map)['visual_inspections_v1']['recordCount'],
      1,
    );
    expect(
      (document['boxes']
          as Map)['media_sync_queue']['entries'][0]['readableJson'],
      isFalse,
    );
    final physical = (document['physicalPhotos'] as List).single as Map;
    expect(physical['exists'], isTrue);
    expect(physical['actualFileSize'], 4);
    expect(
      physical['actualFileSha256'],
      '9f64a747e1b97f131fabb6b447296c9b6f0201e79fb3c5356e6c77e89b6a806a',
    );
  });
}
