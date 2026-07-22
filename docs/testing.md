# Ejecución de pruebas — DIAGNOSTICO HIDRANTES

## Requisitos

- Flutter compatible con el SDK declarado en `pubspec.yaml`.
- Ejecutar desde la raíz del proyecto.
- Para integración Android: emulador o dispositivo Android 10 o superior.
- Los tests Hive crean directorios temporales y nunca abren las cajas productivas del dispositivo.

## Orden obligatorio

```text
flutter pub get
flutter analyze
flutter test --reporter expanded
flutter test --coverage
flutter test integration_test --reporter expanded
flutter run
flutter build apk --debug
```

No ejecutar en paralelo suites que manipulen un mismo directorio Hive. Cada test usa una raíz temporal propia y el teardown cierra Hive y elimina únicamente esa raíz.

## Evidencia

Conservar:

- salida completa y código de retorno;
- archivo `coverage/lcov.info`;
- versión de Flutter/Dart;
- dispositivo/Android para integración;
- captura o video de casos P2;
- fecha, ejecutor y observaciones en `docs/stage4_manual_test_matrix.md`.

Una suite creada pero no ejecutada se reporta como **no certificada**. Un test MethodChannel en host certifica el contrato Dart, no que Android haya aislado físicamente la solicitud sobre la interfaz celular.

## Diagnóstico de fallos

- Fallo de apertura Hive: confirmar que no existe otra suite usando la misma raíz temporal.
- Plugin no registrado en widget test: usar el fake/handler de la prueba; no conectar red, GPS o cámara real.
- Fallo de `integration_test`: registrar plataforma y revisar servicios/plugin registration; no sustituirlo con delays arbitrarios.
- Diferencia documentación/código: registrar en `docs/stage4_automated_test_coverage.md` antes de cambiar la regla productiva.

