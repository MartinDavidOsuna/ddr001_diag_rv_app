import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:hive_ce/hive.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/api_exception.dart';
import '../domain/visual_report.dart';

class VisualReportRepository {
  VisualReportRepository({required this.client, required this.cache});
  final ApiClient client;
  final Box<String> cache;
  final Map<String, VisualReport> _sessionCache = {};
  Future<VisualReport> byAccount(
    String account, {
    required String userId,
    required bool online,
  }) async {
    final key = '$userId|${account.trim().toUpperCase()}';
    if (!online) {
      final raw = cache.get(key);
      if (raw == null) {
        throw const ApiException(
          ApiErrorKind.offline,
          'Este reporte pertenece a otro técnico y está disponible cuando tengas conexión.',
        );
      }
      return VisualReport.fromJson(
        Map<String, dynamic>.from(jsonDecode(raw) as Map),
        currentUserId: userId,
      );
    }
    try {
      final response = await client.dio.get<Map<String, dynamic>>(
        '/hydrants/${Uri.encodeComponent(account.trim())}/visual-report',
      );
      final data = response.data ?? const <String, dynamic>{};
      final report = VisualReport.fromJson(data, currentUserId: userId);
      _sessionCache[report.id] = report;
      if (report.isOwn) await cache.put(key, jsonEncode(data));
      return report;
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }

  Future<List<int>> photo(String path) async {
    try {
      final r = await client.dio.get<List<int>>(
        _apiRelativePath(path),
        options: Options(responseType: ResponseType.bytes),
      );
      return r.data ?? const [];
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  void clearSessionCache() => _sessionCache.clear();
  Future<void> invalidateOwn(String account, String userId) =>
      cache.delete('$userId|${account.trim().toUpperCase()}');

  static String _apiRelativePath(String path) {
    final trimmed = path.trim();
    if (trimmed.startsWith('/api/v1/')) {
      return trimmed.substring('/api/v1'.length);
    }
    return trimmed;
  }
}
