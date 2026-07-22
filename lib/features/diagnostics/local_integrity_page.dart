import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hive_ce/hive.dart';
import 'package:provider/provider.dart';

import '../../core/services/app_state.dart';
import '../../core/widgets/common_widgets.dart';
import '../../data/local/integrity_audit_service.dart';
import '../../data/local/operation_journal_repository.dart';
import '../../data/local/orphan_media_scanner.dart';
import '../../data/local/quarantine_repository.dart';
import '../../data/local/recovery_coordinator.dart';
import '../../domain/integrity/integrity_models.dart';

class LocalIntegrityPage extends StatefulWidget {
  const LocalIntegrityPage({super.key});

  @override
  State<LocalIntegrityPage> createState() => _LocalIntegrityPageState();
}

class _LocalIntegrityPageState extends State<LocalIntegrityPage> {
  IntegrityAuditReport? report;
  List<OrphanMediaRecord> orphans = const [];
  bool running = false;
  String? message;

  bool _authorized(String role) {
    final normalized = role.toLowerCase();
    return normalized.contains('supervisor') || normalized.contains('admin');
  }

  Future<void> _audit() async {
    if (running) return;
    setState(() {
      running = true;
      message = null;
    });
    final next = const IntegrityAuditService().runLightweight();
    const orphanScanner = OrphanMediaScanner();
    final orphanResults = await orphanScanner.scanEvidenceDirectory();
    await orphanScanner.quarantineAmbiguous(orphanResults);
    await Hive.box<String>(
      'integrity_audit_reports_v1',
    ).put(next.id, jsonEncode(next.toJson()));
    if (!mounted) return;
    setState(() {
      report = next;
      orphans = orphanResults;
      running = false;
    });
  }

  Future<void> _repair() async {
    if (running) return;
    setState(() => running = true);
    final summary = await RecoveryCoordinator(
      auditService: const IntegrityAuditService(),
      journal: OperationJournalRepository(
        Hive.box<String>('operation_journal_v1'),
      ),
      quarantine: QuarantineRepository(
        Hive.box<String>('quarantine_documents_v1'),
      ),
    ).runLightweight(includeMediaRepair: true);
    if (!mounted) return;
    setState(() {
      report = summary.audit;
      running = false;
      message =
          'Reparadas: ${summary.repaired} · Cuarentena: ${summary.quarantined} · Revisión manual: ${summary.requiresManualReview}';
    });
  }

  Future<void> _export({required bool asJson}) async {
    final value = report;
    if (value == null) return;
    final export = asJson
        ? const JsonEncoder.withIndent('  ').convert({
            ...value.toJson(),
            'orphanMedia': orphans.map((item) => item.toJson()).toList(),
          })
        : _asText(value);
    await Clipboard.setData(ClipboardData(text: export));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${asJson ? 'JSON' : 'Informe de texto'} copiado al portapapeles.',
          ),
        ),
      );
    }
  }

  String _asText(IntegrityAuditReport value) {
    final buffer = StringBuffer()
      ..writeln('AUDITORÍA DE INTEGRIDAD LOCAL')
      ..writeln('Fecha: ${value.completedAt.toLocal()}')
      ..writeln('Problemas: ${value.issues.length}')
      ..writeln('Archivos huérfanos: ${orphans.length}');
    for (final issue in value.issues) {
      buffer.writeln(
        '- ${issue.severity.name} · ${issue.type.name} · ${issue.userMessage}',
      );
    }
    return buffer.toString();
  }

  @override
  Widget build(BuildContext context) {
    final role = context.watch<AppState>().user.role;
    if (!_authorized(role)) {
      return const Scaffold(
        appBar: AppPageHeader(
          title: 'Auditoría técnica',
          subtitle: 'Acceso restringido',
        ),
        body: Center(
          child: Text(
            'Esta función requiere rol administrador o supervisor local.',
          ),
        ),
      );
    }
    final value = report;
    final severityCounts = <IntegritySeverity, int>{
      for (final severity in IntegritySeverity.values)
        severity:
            value?.issues.where((issue) => issue.severity == severity).length ??
            0,
    };
    return Scaffold(
      appBar: const AppPageHeader(
        title: 'Auditoría técnica',
        subtitle: 'Integridad y recuperación local',
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Semantics(
            liveRegion: true,
            child: SectionCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    value == null
                        ? 'Auditoría no ejecutada en esta vista'
                        : value.requiresReview
                        ? 'Datos locales requieren revisión'
                        : 'Sin problemas críticos detectados',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  if (value != null)
                    Text('Última auditoría: ${value.completedAt.toLocal()}'),
                  Text(
                    'Problemas: ${value?.issues.length ?? 0} · Reparables: ${value?.issues.where((issue) => issue.repairableAutomatically).length ?? 0}',
                  ),
                  Text(
                    'Journals pendientes: ${OperationJournalRepository(Hive.box<String>('operation_journal_v1')).pending().length}',
                  ),
                  Text(
                    'Cuarentena: ${Hive.box<String>('quarantine_documents_v1').length} · Huérfanos: ${orphans.length}',
                  ),
                  if (message != null) Text(message!),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                onPressed: running ? null : _audit,
                icon: const Icon(Icons.search),
                label: const Text('Ejecutar auditoría'),
              ),
              OutlinedButton.icon(
                onPressed: running ? null : _repair,
                icon: const Icon(Icons.healing),
                label: const Text('Reparaciones seguras'),
              ),
              OutlinedButton.icon(
                onPressed: value == null ? null : () => _export(asJson: true),
                icon: const Icon(Icons.data_object),
                label: const Text('Exportar JSON'),
              ),
              OutlinedButton.icon(
                onPressed: value == null ? null : () => _export(asJson: false),
                icon: const Icon(Icons.description),
                label: const Text('Exportar texto'),
              ),
            ],
          ),
          if (running)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            ),
          if (value != null) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              children: [
                for (final entry in severityCounts.entries)
                  Chip(label: Text('${entry.key.name}: ${entry.value}')),
              ],
            ),
            for (final issue in value.issues)
              Card(
                child: ExpansionTile(
                  title: Text(issue.userMessage),
                  subtitle: Text('${issue.severity.name} · ${issue.type.name}'),
                  children: [
                    ListTile(
                      title: const Text('Elemento'),
                      subtitle: Text('${issue.entityType} · ${issue.entityId}'),
                    ),
                    ListTile(
                      title: const Text('Acción'),
                      subtitle: Text(issue.recommendedAction.name),
                    ),
                    if (issue.repairableAutomatically)
                      const ListTile(
                        title: Text('Reparación automática permitida'),
                      ),
                  ],
                ),
              ),
            if (orphans.isNotEmpty)
              ExpansionTile(
                title: Text('Archivos huérfanos (${orphans.length})'),
                children: [
                  for (final orphan in orphans)
                    ListTile(
                      title: Text(orphan.kind.name),
                      subtitle: Text(orphan.path),
                    ),
                ],
              ),
          ],
        ],
      ),
    );
  }
}
