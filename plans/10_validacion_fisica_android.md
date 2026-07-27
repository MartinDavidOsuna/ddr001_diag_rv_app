# Validación física Android y hardening

Fecha de cierre: 24 de julio de 2026.

## Entorno

- Pixel 7 Pro, serie enmascarada `2730…04R7`, autorizado por ADB.
- Android 17/API 37, `arm64-v8a`; ADB 1.0.41.
- Flutter 3.44.5, Dart 3.12.2.
- Aplicación `com.aquafim.ddr001diag`, actualización local probada hasta `0.2.1+6`.
- API local `192.168.1.111:3000/api/v1`; base exclusiva
  `RevisionVisualStarter_Test`.
- Usuario de prueba enmascarado. No se registran credenciales, tokens,
  coordenadas exactas, serie completa ni imágenes.

## Resultado funcional

Se validaron instalación, arranque, autenticación correcta e incorrecta,
persistencia de sesión, catálogo general/personal, búsquedas exactas/parciales/sin
resultados, creación de borrador, GPS, modo offline, reconexión, sincronización,
mapa, preselección y actualización por `adb install -r`. Ninguna inspección
física fue enviada.

El checklist RV v2 se recorrió físicamente en sus nueve secciones, con navegación
anterior/siguiente y acceso al resumen. La consulta estructural confirmó 77
elementos: 63 contestables y 14 de evidencia/solo lectura. Se comprobaron
persistencia del progreso, comentario, cambio de respuesta y visibilidad
condicional; no se capturaron datos reales para completar cada elemento.

## Fotografía

Se observaron denegación y concesión del permiso, apertura y cancelación de la
cámara, miniatura, reapertura del borrador, persistencia local y sincronización.
La evidencia de prueba existente, sin personas ni documentos, quedó asociada al
slot `front_closed` de una inspección RV v2 de la cuenta de prueba 351:

- JPEG, 1080 × 1434;
- archivo local comprimido: 174 135 bytes;
- miniatura local: 11 670 bytes (93,30 % menor que el archivo persistido);
- integridad local/remota: el SHA-256 local coincide con `client_sha256`;
- estado remoto: `verified`, una sola foto, sin reemplazo;
- tiempo HTTP observado de carga/proceso: aproximadamente 488 ms.

El servicio no conserva el tamaño de la captura antes de comprimir; por ello no
es posible informar un porcentaje original→comprimido reproducible. Tampoco se
reemplazó la evidencia ya sincronizada: la recaptura destructiva queda pendiente
de una nueva foto segura con operador presencial.

## Incidencia TEST-RVS-001

El borrador heredado `TEST-RVS-001` contiene un identificador de hidrante local
que no existe en SQL. El endpoint `POST /api/v1/inspections` delegaba esa
condición a `RAISERROR`, que se convertía en HTTP 500. Además, el middleware de
idempotencia conservaba y repetía respuestas 5xx durante 24 horas.

La API ahora comprueba primero el hidrante y responde RFC Problem HTTP 404. Las
claves cuyo resultado fue 5xx se eliminan y una clave 5xx histórica puede volver
a ejecutarse. La prueba de integración precarga un 500 histórico y confirma la
recuperación a 404. La repetición desde el Pixel devolvió 404; no se creó una
inspección remota para TEST-RVS-001.

## UX, resiliencia, memoria y rendimiento

“Simulación local” fue sustituido por mensajes que distinguen conexión real y
persistencia offline. Se agregaron dos pruebas de widget.

Cinco ciclos de cierre forzado/arranque tardaron 2,038–2,944 s después del primer
arranque de 3,144 s. El PSS se mantuvo entre 385 357 y 387 752 KB, sin tendencia
ascendente. Cinco ciclos foreground/background, rotación/restauración,
navegación repetida y tres sincronizaciones consecutivas no causaron cierres ni
duplicados. Los temporizadores y listeners críticos revisados se cancelan en
`dispose`.

Tiempos aproximados observados: catálogo API 33–71 ms; checklist API 51–75 ms;
creación 86 ms; respuestas 635 ms; GPS 85 ms; señal 83 ms; fotografía 488 ms.
Son mediciones de una ejecución debug en red local, no benchmarks.

## Calidad

- `dart format lib test`: 143 archivos, cero cambios.
- `flutter analyze`: sin hallazgos.
- `flutter test`: 125/125.
- `flutter build apk --debug`: aprobado.
- API, Node 22.23.1/npm 11.17.0: lint, type-check, 62/62 unitarias,
  9/9 integración y build aprobados.
- `health/live`: `ok`; `health/ready`: `database`, `storage` y
  `configuration` en `ok`.
- Ningún APK versionado; `git diff --check` aprobado.

La advertencia de `flutter_image_compress_common` sobre Built-in Kotlin es futura
y no bloquea el build. Se recomienda actualizar el plugin en una tarea aislada,
sin mezclarla con este hardening.

## Estado de los datos y límites

La inspección de cuenta 351 permanece `in_progress`, RV v2, revisión 1, con 51
respuestas, una ubicación, una señal y una foto; `submitted_at` es nulo y existe
una sola fila por `client_inspection_id`. La inspección de cuenta 2455 también
permanece abierta. No se borraron datos, no se ejecutó `pm clear`, no hubo
importaciones, producción, commit, push ni PR.

Riesgo restante: ejecutar presencialmente una recaptura con encuadre seguro y
registrar el tamaño previo a compresión requerirá instrumentación adicional o
un contador temporal; no es un defecto de estabilidad.
