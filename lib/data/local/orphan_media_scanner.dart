import 'dart:convert';
import 'dart:io';

import 'package:hive_ce/hive.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../domain/media/inspection_photo.dart';
import 'quarantine_repository.dart';

enum OrphanMediaKind {
  originalWithoutDocument,
  thumbnailWithoutDocument,
  abandonedTemporary,
  outsideManagedDirectory,
}

class OrphanMediaRecord {
  const OrphanMediaRecord({
    required this.path,
    required this.kind,
    required this.detectedAt,
    required this.unambiguousPhotoId,
  });
  final String path;
  final OrphanMediaKind kind;
  final DateTime detectedAt;
  final String? unambiguousPhotoId;

  Map<String, dynamic> toJson() => {
    'path': path,
    'kind': kind.name,
    'detectedAt': detectedAt.toUtc().toIso8601String(),
    'unambiguousPhotoId': unambiguousPhotoId,
  };
}

class OrphanMediaScanner {
  const OrphanMediaScanner();

  Future<List<OrphanMediaRecord>> scanEvidenceDirectory() async {
    final documents = await getApplicationDocumentsDirectory();
    final root = Directory(p.join(documents.path, 'evidence'));
    final rootPath = p.normalize(p.absolute(root.path));
    final referenced = <String>{};
    final knownIds = <String>{};
    final findings = <OrphanMediaRecord>[];
    for (final raw in Hive.box<String>('inspection_photos_v1').values) {
      try {
        final photo = InspectionPhoto.fromJson(
          Map<String, dynamic>.from(jsonDecode(raw) as Map),
        );
        knownIds.add(photo.id);
        for (final path in [photo.localPath, photo.thumbnailPath]) {
          final normalized = p.normalize(p.absolute(path));
          if (p.isWithin(rootPath, normalized) || normalized == rootPath) {
            referenced.add(normalized);
          } else if (normalized.isNotEmpty) {
            findings.add(
              OrphanMediaRecord(
                path: normalized,
                kind: OrphanMediaKind.outsideManagedDirectory,
                detectedAt: DateTime.now().toUtc(),
                unambiguousPhotoId: photo.id,
              ),
            );
          }
        }
      } on Object {
        // El auditor de JSON conserva el documento corrupto.
      }
    }
    if (await root.exists()) {
      await for (final entity in root.list(
        recursive: true,
        followLinks: false,
      )) {
        if (entity is! File) continue;
        final normalized = p.normalize(p.absolute(entity.path));
        if (!p.isWithin(rootPath, normalized)) continue;
        if (referenced.contains(normalized)) continue;
        final name = p.basename(normalized);
        final isTemporary = name.contains('.tmp') || name.endsWith('.part');
        final id = name.split('_thumb').first.split('.').first;
        findings.add(
          OrphanMediaRecord(
            path: normalized,
            kind: isTemporary
                ? OrphanMediaKind.abandonedTemporary
                : name.contains('_thumb')
                ? OrphanMediaKind.thumbnailWithoutDocument
                : OrphanMediaKind.originalWithoutDocument,
            detectedAt: DateTime.now().toUtc(),
            unambiguousPhotoId: knownIds.contains(id) ? id : null,
          ),
        );
      }
    }
    return findings;
  }

  Future<int> quarantineAmbiguous(List<OrphanMediaRecord> findings) async {
    final box = Hive.box<String>('quarantine_documents_v1');
    final existingKeys = <String>{};
    for (final raw in box.values) {
      try {
        final json = Map<String, dynamic>.from(jsonDecode(raw) as Map);
        if (json['sourceBox'] == 'managedEvidenceDirectory') {
          existingKeys.add('${json['sourceKey']}');
        }
      } on Object {
        // La cuarentena corrupta se reporta por el auditor general.
      }
    }
    final repository = QuarantineRepository(box);
    var created = 0;
    for (final finding in findings.where(
      (item) =>
          item.unambiguousPhotoId == null ||
          item.kind == OrphanMediaKind.outsideManagedDirectory,
    )) {
      if (!existingKeys.add(finding.path)) continue;
      await repository.preserve(
        sourceBox: 'managedEvidenceDirectory',
        sourceKey: finding.path,
        originalDocument: jsonEncode(finding.toJson()),
        errorType: finding.kind.name,
        technicalMessage:
            'Referencia lógica preservada; el archivo físico no se modificó.',
        recoverable: true,
      );
      created++;
    }
    return created;
  }
}
