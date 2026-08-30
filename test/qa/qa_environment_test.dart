import 'package:ddr001diag/core/config/app_config.dart';
import 'package:ddr001diag/core/network/api_client.dart';
import 'package:ddr001diag/features/auth/data/field_session_models.dart';
import 'package:ddr001diag/features/auth/data/session_secure_storage.dart';
import 'package:ddr001diag/main_qa.dart';
import 'package:ddr001diag/qa/qa_app_config.dart';
import 'package:ddr001diag/qa/qa_network_policy.dart';
import 'package:ddr001diag/qa/qa_runtime_guard.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('configuración QA aislada', () {
    test('usa .invalid, fixtures y sincronización deshabilitada', () {
      final config = createQaAppConfig();

      expect(config.environment, 'qa');
      expect(config.isQa, isTrue);
      expect(config.fixtureMode, isTrue);
      expect(config.syncEnabled, isFalse);
      expect(config.allowsProductionNetwork, isFalse);
      expect(config.apiBaseUrl.host, 'ddr001-rv-qa.invalid');
      expect(config.buildLabel, 'QA · NO PRODUCCIÓN');
    });

    test('la configuración productiva conserva endpoint y capacidades', () {
      final config = AppConfig.fromEnvironment(
        environmentOverride: 'production',
        apiBaseUrlOverride: '',
        debugMode: false,
      );

      expect(config.apiBaseUrl.toString(), AppConfig.productionBaseUrl);
    });

    for (final endpoint in [
      'http://cifra.aquafim.com:3002/api/v1',
      'https://cifra.aquafim.com/api/v1',
      'https://sub.cifra.aquafim.com/api/v1',
      'https://cifra.aquafim.com.evil.invalid/api/v1',
      'https://127.0.0.1/api/v1',
      'https:///api/v1',
    ]) {
      test('rechaza endpoint QA no autorizado: $endpoint', () {
        expect(
          () => QaNetworkPolicy.validateConfiguredEndpoint(
            _qaConfigWith(endpoint),
          ),
          throwsA(isA<QaNetworkBlockedException>()),
        );
      });
    }

    test('rechaza fallback QA que habilite sync o quite fixtures', () {
      expect(
        () => QaNetworkPolicy.validateConfiguredEndpoint(
          _UnsafeQaConfig(syncEnabled: true),
        ),
        throwsA(isA<QaNetworkBlockedException>()),
      );
      expect(
        () => QaNetworkPolicy.validateConfiguredEndpoint(
          _UnsafeQaConfig(fixtureMode: false),
        ),
        throwsA(isA<QaNetworkBlockedException>()),
      );
    });
  });

  group('barrera de red QA', () {
    test('exige bandera QA y bloquea antes de abrir conexión', () async {
      final adapter = _CountingAdapter();
      final config = createQaAppConfig();
      final dio = Dio(BaseOptions(baseUrl: config.apiBaseUrl.toString()))
        ..httpClientAdapter = adapter;
      final client = ApiClient(
        config: config.apiClientConfig,
        sessionStorage: _NoCredentialStorage(),
        dio: dio,
      );
      QaNetworkPolicy.install(client.dio, config);

      await expectLater(
        client.dio.get<void>('/health/live'),
        throwsDioException,
      );
      await expectLater(
        client.dio.get<void>(
          '/health/live',
          options: Options(extra: const {QaNetworkPolicy.requestFlag: true}),
        ),
        throwsDioException,
      );
      expect(adapter.requests, 0);
    });

    test('rechaza redirect absoluto o engañoso a producción', () {
      final config = createQaAppConfig();
      for (final target in [
        Uri.parse('http://cifra.aquafim.com:3002/api/v1'),
        Uri.parse('https://cifra.aquafim.com/api/v1'),
        Uri.parse('https://cifra.aquafim.com.evil.invalid/api/v1'),
      ]) {
        expect(
          () => QaNetworkPolicy.validateRedirect(config, target),
          throwsA(isA<QaNetworkBlockedException>()),
        );
      }
    });
  });

  group('guardia package/config', () {
    test('acepta únicamente package QA con configuración QA', () {
      expect(
        QaRuntimeGuard.verify(
          config: createQaAppConfig(),
          packageName: QaRuntimeGuard.packageName,
        ).allowed,
        isTrue,
      );
      expect(
        QaRuntimeGuard.verify(
          config: createQaAppConfig(),
          packageName: 'com.aquafim.ddr001diag',
        ).code,
        'QA_PACKAGE_MISMATCH',
      );
    });

    testWidgets('mismatch muestra pantalla segura sin bootstrap', (
      tester,
    ) async {
      await tester.pumpWidget(const QaBlockedApp(code: 'QA_PACKAGE_MISMATCH'));

      expect(
        find.text('QA bloqueada por configuración insegura'),
        findsOneWidget,
      );
      expect(find.text('QA_PACKAGE_MISMATCH'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });
  });
}

QaAppConfig _qaConfigWith(String endpoint) =>
    QaAppConfig(apiBaseUrl: Uri.parse(endpoint));

class _UnsafeQaConfig extends QaAppConfig {
  _UnsafeQaConfig({bool? syncEnabled, bool? fixtureMode})
    : overrideSyncEnabled = syncEnabled,
      overrideFixtureMode = fixtureMode;

  final bool? overrideSyncEnabled;
  final bool? overrideFixtureMode;

  @override
  bool get syncEnabled => overrideSyncEnabled ?? false;

  @override
  bool get fixtureMode => overrideFixtureMode ?? true;
}

class _CountingAdapter implements HttpClientAdapter {
  int requests = 0;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests++;
    return ResponseBody.fromString('{}', 200);
  }

  @override
  void close({bool force = false}) {}
}

class _NoCredentialStorage implements SessionStorage {
  @override
  Future<void> clear() async {}

  @override
  Future<String> installationId() async => 'qa-installation';

  @override
  Future<FieldSession?> read() async => null;

  @override
  Future<void> save(FieldSession session) async {
    throw StateError('No credentials in QA.');
  }
}

Matcher get throwsDioException => throwsA(isA<DioException>());
