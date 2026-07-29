# Certificación 12.5.2-A

Fecha: 2026-07-25  
Rama app/API: `feature/rv-crs-and-catalog-resolution`

## Versionado e instalación

- Origen del versionado: `pubspec.yaml` → propiedades Flutter de Gradle.
- Anterior: `0.2.1+4`.
- Nuevo: `0.2.1+9`.
- APK verificado con AAPT: package `com.aquafim.ddr001diag`,
  `versionName=0.2.1`, `versionCode=9`.
- Pixel 7 Pro detectado y actualización instalada mediante `adb install -r`.
- Android reporta `versionCode=9`; `firstInstallTime` se conservó desde
  2026-07-24, por lo que no hubo desinstalación ni limpieza de datos.
- Después de actualizar siguen presentes almacenamiento seguro, índice de
  inspección activo, Hive de inspecciones, catálogo dinámico y evidencias
  fotográficas. No se inspeccionó contenido sensible.

## Node, API y health

- Runtime aislado: Node `v22.17.1`; npm `10.9.2`.
- PID de certificación: `12036`.
- Comando: Node 22 portátil + `dist/server.js`, puerto 3000.
- `health/live`: HTTP 200, `{"status":"ok"}`.
- `health/ready`: HTTP 200 con `database`, `storage` y `configuration` en `ok`.
- No se utilizó Node 24 para instalar, probar, compilar ni levantar la API.

## SQL de pruebas

- Servidor lógico reportado por SQL: `WIN-5RQE8N8NQ9V`.
- Base: `RevisionVisualStarter_Test`.
- Esquema `rv` confirmado.
- La migración 04 ahora rechaza cualquier `DB_NAME()` distinto de la base de
  pruebas.
- Se ejecutó exclusivamente `04_dynamic_brands_diameters.sql`, dos veces.
- Conteos antes/después: 3 inspecciones, 52 respuestas y 1 foto.
- Segunda ejecución: segura y sin duplicados.
- Tablas, columnas, PK, índices únicos filtrados, desactivación lógica,
  `client_id`, FK desde respuestas y auditoría verificadas.
- Seeds: exclusivamente 3 y 4 pulgadas, activos y de origen `system`.

## Pruebas automatizadas

Flutter, ejecución final desde cero:

- `dart format lib test`: aprobado.
- `flutter analyze`: sin incidencias.
- `flutter test`: 173 aprobadas, cero omitidas inesperadamente.
- `flutter build apk --debug`: aprobado.
- Duración aproximada del bloque: 202 segundos.
- Las 18 pruebas focalizadas forman parte de las 173; el total no aumentó porque
  esta subetapa certificó y corrigió contratos, sin agregar archivos de prueba
  Flutter nuevos.

API con Node 22:

- lint y type-check: aprobados.
- unitarias: 67 aprobadas.
- integración SQL/API: 10 aprobadas en 4 archivos, ninguna omitida.
- build TypeScript: aprobado.
- La fixture sintética verificó marca y diámetro referenciados en respuestas,
  fotografías sintéticas, `submitted_at`, un único registro, segundo submit
  rechazado y bloqueo posterior. Las fixtures fueron limpiadas por `afterAll`.

## Validación física

La actualización, proceso de app y persistencia de archivos quedaron verificadas.
La pantalla del Pixel estaba protegida por bloqueo biométrico/credencial. Codex
no dispone de esa credencial y no intentó evadir el bloqueo.

Por ello no fue posible certificar manualmente:

- cámara y cancelación;
- selector/galería/visor/borrado;
- scroll y foco de pasos 1–10;
- rotación y foreground/background;
- controles online/offline de marcas y diámetros;
- resumen y navegación a pendientes.

Tampoco existía una escena segura confirmada para tomar una fotografía. No se
capturó imagen nueva y no se envió ninguna inspección física.

## Resultado

Certificación automatizada, SQL, API, health, versionado, instalación y
persistencia: aprobadas. Certificación visual/interactiva física: pendiente por
bloqueo seguro del dispositivo y ausencia de escena confirmada. La subetapa no se
declara cerrada mientras esa matriz manual no se ejecute.
