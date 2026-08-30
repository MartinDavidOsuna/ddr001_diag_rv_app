import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('flavors conservan producción y aíslan package/firma QA', () {
    final gradle = File('android/app/build.gradle.kts').readAsStringSync();

    expect(gradle, contains('create("production")'));
    expect(gradle, contains('applicationId = "com.aquafim.ddr001diag"'));
    expect(gradle, contains('signingConfigs.getByName("release")'));
    expect(gradle, contains('create("qa")'));
    expect(gradle, contains('applicationIdSuffix = ".qa"'));
    expect(gradle, contains('versionNameSuffix = "-qa"'));
    expect(gradle, contains('signingConfigs.getByName("debug")'));
    expect(gradle, contains('isDebuggable = false'));
  });

  test('FileProvider usa authority derivada del applicationId', () {
    final manifest = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();

    expect(manifest, contains(r'${applicationId}.diagnostic.files'));
    expect(
      manifest,
      isNot(contains('com.aquafim.ddr001diag.diagnostic.files')),
    );
  });

  test('FileProvider productivo no expone reportes QA', () {
    final productionPaths = File(
      'android/app/src/main/res/xml/diagnostic_file_paths.xml',
    ).readAsStringSync();
    final qaPaths = File(
      'android/app/src/qa/res/xml/diagnostic_file_paths.xml',
    ).readAsStringSync();

    expect(productionPaths, contains('camera-capture-staging/'));
    expect(productionPaths, isNot(contains('qa-diagnostic-reports/')));
    expect(productionPaths, isNot(contains('<cache-path')));
    expect(productionPaths, isNot(contains('<external-files-path')));
    expect(qaPaths, contains('camera-capture-staging/'));
    expect(qaPaths, contains('qa-diagnostic-reports/'));
  });

  test('manifest QA desactiva backup, cleartext y distingue nombre/icono', () {
    final manifest = File(
      'android/app/src/qa/AndroidManifest.xml',
    ).readAsStringSync();
    final strings = File(
      'android/app/src/qa/res/values/strings.xml',
    ).readAsStringSync();

    expect(manifest, contains('android:allowBackup="false"'));
    expect(manifest, contains('android:fullBackupContent="false"'));
    expect(manifest, contains('android:usesCleartextTraffic="false"'));
    expect(manifest, contains('android:name="android.permission.INTERNET"'));
    expect(
      manifest,
      contains('android:name="android.permission.CHANGE_NETWORK_STATE"'),
    );
    expect(manifest, contains('tools:node="remove"'));
    expect(manifest, contains('@drawable/qa_launcher_icon'));
    expect(manifest, contains('tools:replace='));
    expect(strings, contains('DDR001 RV QA'));
  });

  test('qaDebug conserva la barrera de red del flavor QA', () {
    final manifest = File(
      'android/app/src/qaDebug/AndroidManifest.xml',
    ).readAsStringSync();

    expect(manifest, contains('android:usesCleartextTraffic="false"'));
    expect(manifest, contains('android:name="android.permission.INTERNET"'));
    expect(manifest, contains('tools:node="remove"'));
    expect(manifest, contains('tools:replace="android:usesCleartextTraffic"'));
  });

  test('entrypoint productivo no importa QA ni fixtures', () {
    final production = File('lib/main.dart').readAsStringSync();

    expect(production, isNot(contains('main_qa')));
    expect(production, isNot(contains('/qa/')));
    expect(production, isNot(contains('QA · NO PRODUCCIÓN')));
  });

  test('botón de cierre QA obtiene contexto debajo de MaterialApp', () {
    final qaApp = File('lib/qa/qa_app.dart').readAsStringSync();

    expect(qaApp, contains('Builder('));
    expect(qaApp, contains('builder: (navigatorContext)'));
    expect(qaApp, contains('showRvInactiveClosureDialog('));
    expect(qaApp, contains('navigatorContext,'));
  });

  test('exportación QA usa el canal con authority derivada del package', () {
    final qaApp = File('lib/qa/qa_app.dart').readAsStringSync();
    final qaChannel = File(
      'android/app/src/qa/kotlin/com/aquafim/ddr001diag/'
      'DiagnosticReportChannelFactory.kt',
    ).readAsStringSync();
    final productionChannel = File(
      'android/app/src/production/kotlin/com/aquafim/ddr001diag/'
      'DiagnosticReportChannelFactory.kt',
    ).readAsStringSync();

    expect(qaApp, contains('com.aquafim.ddr001diag/diagnostic_report'));
    expect(qaApp, contains("invokeMethod<void>('share'"));
    expect(qaChannel, contains(r'"$packageName.diagnostic.files"'));
    expect(qaChannel, contains('Intent.FLAG_GRANT_READ_URI_PERMISSION'));
    expect(qaChannel, contains('ClipData.newRawUri'));
    expect(qaChannel, contains('application/json'));
    expect(productionChannel, isNot(contains('MethodChannel(')));
    expect(productionChannel, isNot(contains('ACTION_SEND')));
  });

  test('fixture de cámara conserva el scope exacto del usuario QA', () {
    final harness = File('lib/qa/qa_fixture_harness.dart').readAsStringSync();

    expect(harness, contains('fieldSessionId: user.id'));
    expect(harness, isNot(contains("fieldSessionId: 'qa-field-session")));
  });
}
