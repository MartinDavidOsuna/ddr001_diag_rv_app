import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:hive_ce/hive.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_exception.dart';
import 'checklist_models.dart';

class ChecklistRepository {
  ChecklistRepository({required this.client, required this.box});
  final ApiClient client;
  final Box<String> box;
  static const _key = 'active_rv';

  DynamicChecklist? cached() {
    final raw = box.get(_key);
    if (raw == null) return null;
    try {
      return DynamicChecklist.fromJson(
        Map<String, dynamic>.from(jsonDecode(raw) as Map),
      );
    } on Object {
      return null;
    }
  }

  Future<DynamicChecklist> refresh() async {
    final local = cached();
    try {
      final response = await client.dio.get<Map<String, dynamic>>(
        '/checklists/rv/active',
        options: Options(
          headers: {
            if (local?.etag.isNotEmpty == true) 'If-None-Match': local!.etag,
          },
          validateStatus: (status) => status == 200 || status == 304,
        ),
      );
      if (response.statusCode == 304) {
        if (local == null) throw const FormatException('304 sin caché');
        return local;
      }
      final etag =
          response.headers.value('etag') ??
          response.data?['etag']?.toString() ??
          '';
      final checklist = DynamicChecklist.fromApi(
        response.data ?? const {},
        etag: etag,
        cachedAt: DateTime.now().toUtc(),
      );
      await box.put(_key, jsonEncode(checklist.toJson()));
      return checklist;
    } on DioException catch (error) {
      if (local != null &&
          (error.type == DioExceptionType.connectionError ||
              error.type == DioExceptionType.connectionTimeout ||
              error.type == DioExceptionType.receiveTimeout)) {
        return local;
      }
      throw ApiException.fromDio(error);
    }
  }
}

/// Puente inicial: la UI actual sigue disponible mientras la siguiente etapa
/// renderiza [DynamicChecklist] como fuente canónica.
class DynamicChecklistAdapter {
  const DynamicChecklistAdapter(this.checklist);
  final DynamicChecklist checklist;
  Iterable<ChecklistItemDefinition> get answerableItems => checklist.sections
      .expand((section) => section.items)
      .where(
        (item) => !const {
          'photo',
          'coordinates',
          'signal',
          'readonly',
        }.contains(item.type),
      );
}
