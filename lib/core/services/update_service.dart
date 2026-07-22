import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:pub_semver/pub_semver.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../domain/enums/app_enums.dart';
import '../../domain/models/app_models.dart';

enum UpdateDemoScenario { current, optional, required, error }

class UpdateService {
  UpdateService({this.remoteManifestUrl = ''});
  final String remoteManifestUrl;
  static const demoAndroidUrl =
      'https://example.invalid/diagnostico-hidrantes-demo.apk';
  DateTime? _lastCheck;
  UpdateInfo? _cached;
  static const minimumCheckInterval = Duration(minutes: 15);

  Future<UpdateInfo> check({
    required String installedVersion,
    required int installedBuild,
    bool manual = false,
    UpdateDemoScenario? demoScenario,
  }) async {
    if (demoScenario != null) {
      return _demo(demoScenario);
    }
    if (!manual &&
        _cached != null &&
        _lastCheck != null &&
        DateTime.now().difference(_lastCheck!) < minimumCheckInterval) {
      return _cached!;
    }
    try {
      Map<String, dynamic> json;
      if (remoteManifestUrl.trim().isNotEmpty) {
        try {
          final response = await Dio(
            BaseOptions(
              connectTimeout: const Duration(seconds: 4),
              receiveTimeout: const Duration(seconds: 4),
            ),
          ).get<dynamic>(remoteManifestUrl);
          if (response.data is Map<String, dynamic>) {
            json = response.data as Map<String, dynamic>;
          } else if (response.data is String) {
            json = jsonDecode(response.data as String) as Map<String, dynamic>;
          } else {
            throw const FormatException('Manifest format');
          }
        } catch (_) {
          json =
              jsonDecode(
                    await rootBundle.loadString(
                      'assets/config/update_manifest.json',
                    ),
                  )
                  as Map<String, dynamic>;
        }
      } else {
        json =
            jsonDecode(
                  await rootBundle.loadString(
                    'assets/config/update_manifest.json',
                  ),
                )
                as Map<String, dynamic>;
      }
      final info = _parse(json, installedVersion, installedBuild);
      _lastCheck = DateTime.now();
      _cached = info;
      return info;
    } catch (_) {
      return const UpdateInfo(
        latestVersion: '',
        minimumSupportedVersion: '',
        buildNumber: 0,
        title: 'No fue posible comprobar actualizaciones',
        message: 'Puedes continuar usando la aplicación y tus datos locales.',
        status: UpdateStatus.unavailable,
      );
    }
  }

  UpdateInfo _parse(
    Map<String, dynamic> json,
    String installedVersion,
    int installedBuild,
  ) {
    final latestText = json['latestVersion'] as String;
    final latestBuild = (json['latestBuild'] ?? json['buildNumber']) as int;
    final minimumText = json['minimumSupportedVersion'] as String;
    final current = Version.parse(installedVersion);
    final latest = Version.parse(latestText);
    final minimum = Version.parse(minimumText);
    final required = (json['required'] as bool? ?? false) || current < minimum;
    final available =
        current < latest || current == latest && installedBuild < latestBuild;
    return UpdateInfo(
      latestVersion: latestText,
      minimumSupportedVersion: minimumText,
      buildNumber: latestBuild,
      title: json['title'] as String,
      message: json['message'] as String,
      status: required
          ? UpdateStatus.required
          : available
          ? UpdateStatus.optional
          : UpdateStatus.current,
      isRequired: required,
      androidUrl: json['androidUrl'] as String? ?? '',
      iosUrl: json['iosUrl'] as String?,
      publishedAt: DateTime.tryParse(json['publishedAt'] as String? ?? ''),
      sha256: json['sha256'] as String?,
      releaseNotes: (json['releaseNotes'] as List<dynamic>? ?? const [])
          .cast<String>(),
    );
  }

  UpdateInfo _demo(UpdateDemoScenario scenario) => switch (scenario) {
    UpdateDemoScenario.current => const UpdateInfo(
      latestVersion: '0.2.0',
      minimumSupportedVersion: '0.1.0',
      buildNumber: 3,
      title: 'Aplicación actualizada',
      message: 'Tienes instalada la versión disponible.',
      status: UpdateStatus.current,
    ),
    UpdateDemoScenario.optional => const UpdateInfo(
      latestVersion: '0.2.1',
      minimumSupportedVersion: '0.1.0',
      buildNumber: 4,
      title: 'Nueva versión disponible',
      message: 'Incluye correcciones de navegación, sincronización y mapa.',
      status: UpdateStatus.optional,
      androidUrl: demoAndroidUrl,
      releaseNotes: [
        'Navegación y control de Atrás',
        'Sincronización incremental',
        'Etiquetas visibles en mapa',
      ],
    ),
    UpdateDemoScenario.required => const UpdateInfo(
      latestVersion: '0.3.0',
      minimumSupportedVersion: '0.3.0',
      buildNumber: 5,
      title: 'Actualización obligatoria',
      message:
          'Debes actualizar para continuar creando o modificando diagnósticos.',
      status: UpdateStatus.required,
      isRequired: true,
      androidUrl: demoAndroidUrl,
      releaseNotes: ['Actualización requerida para nuevas capturas'],
    ),
    UpdateDemoScenario.error => const UpdateInfo(
      latestVersion: '',
      minimumSupportedVersion: '',
      buildNumber: 0,
      title: 'No fue posible comprobar actualizaciones',
      message: 'Puedes reintentar. Tus datos locales permanecen disponibles.',
      status: UpdateStatus.unavailable,
    ),
  };

  Future<bool> openAndroidDownload(UpdateInfo info) async {
    if (info.androidUrl.isEmpty ||
        info.androidUrl.contains('example.invalid')) {
      return false;
    }
    final uri = Uri.tryParse(info.androidUrl);
    if (uri == null) {
      return false;
    }
    return launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}
