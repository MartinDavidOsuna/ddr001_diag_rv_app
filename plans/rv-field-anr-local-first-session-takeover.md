# Diagnóstico y plan: ANR local-first y takeover de sesión

Fecha: 2026-08-06  
Rama base verificada: `backup/first-on-field-test`  
Rama de trabajo: `fix/rv-field-anr-local-first-and-session-takeover`  
Aplicación observada: `0.2.26+39`  
Application ID verificado: `com.aquafim.ddr001diag`

## Estado inicial del repositorio

- Último commit base: `0652b95 Remove APK files`.
- Remoto: `origin https://github.com/MartinDavidOsuna/ddr001_diag_rv_app.git`.
- Cambios preexistentes que deben preservarse y excluirse de los commits de esta tarea: `pubspec.lock`, `node_modules/`, `package.json` y `package-lock.json`.
- Backend hermano inspeccionado: `../ddr001_api_rv`, rama `diagnostico-produccion-2026-07-28`, commit `90db0ce fix: valve diameter coinciliation`.
- No se harán merge, push, borrado de ramas, migraciones destructivas ni borrado de datos locales.

## Diagnóstico inicial basado en código real

No hay todavía una traza `lastanr`; por tanto no es válido afirmar una causa única demostrada. Los hallazgos se clasifican por riesgo:

### CRÍTICA — presión de CPU/memoria al volver de cámara

El hot path actual es:

`ImagePicker.pickImage` → compresión por plugin → `readAsBytes` del normalizado → `instantiateImageCodec` → segundo `readAsBytes` del mismo archivo → segundo `instantiateImageCodec` → thumbnail por plugin → `sha256.convert(buffer completo)` → dos `Hive.put` + journal → `draft.save` → `notifyListeners` global del controlador.

En `FlutterImageCompressProcessingService.normalize` el JPEG normalizado se lee completo y se decodifica para obtener dimensiones. En `ReliablePhotoService.acquire` se vuelve a leer y decodificar completo para una validación redundante, y el mismo buffer se retiene para tamaño y SHA-256. Esto crea copias de bytes y bitmaps full-resolution simultáneas o muy próximas, promueve GC y ejecuta coordinación/decode/hash desde el isolate principal. Aunque las APIs sean `async`, el hash y partes del decode/serialización siguen consumiendo el main isolate. Modo avión no elimina ninguna de estas operaciones y puede sentirse peor si además hay reconciliación/colas locales disparadas por cambios de estado.

### ALTA — recorridos y JSON decode repetidos desde getters/rebuilds

`AppState.accessiblePhotoIds` recorre y decodifica toda `inspection_photos_v1`. `pendingPhotos`, `verifiedPhotos` y `syncErrors` lo invocan separadamente; `pendingCount` y `allSynchronized` vuelven a encadenar esos getters. `pendingDiagnostics` recorre la cola. Hay recorridos adicionales de trazas y fotos por hidrante. Un solo build de sincronización puede decodificar la caja varias veces; con 17 diagnósticos y 50+ fotos el costo crece con cada `notifyListeners`.

### ALTA — I/O síncrono en rutas visibles y de sincronización

Hay `File.existsSync()` en widgets, contadores, validadores, galería, reconciliación, auditoría y `InspectionSyncCoordinator._photos`. En particular, usarlo desde `build`/getters puede bloquear el isolate principal por metadatos del filesystem. Se reemplazarán únicamente los casos de rutas calientes con estado persistido/cacheado o I/O asíncrono.

### ALTA — captura acoplada a estado global `busy`

`RvInspectionController.addPhoto` usa `_run`, establece `busy=true` antes de abrir cámara y notifica a todos los listeners al inicio y al final. Tras volver espera todo el procesamiento, journal, Hive y guardado del draft antes de liberar `busy`. La pantalla sigue viva, pero cualquier trabajo CPU síncrono dentro de esa cadena monopoliza el isolate y el rebuild abarca todo el controlador. Se separará `pickingPhoto`/`processingPhoto` del resto de acciones y se conservará el paso previo explícitamente.

### ALTA — “Revisar y enviar” aún espera red

`RvInspectionController.synchronize(submit: true)` llama catálogos, creación remota, fotos, reconciliación, contenido general, respuestas y submit dentro de la acción de UI. Aunque usa awaits, la experiencia y el estado `busy` quedan ligados al servidor. Debe cambiar a validación/persistencia/marcado local inmediato y lanzar sincronización independiente.

### ALTA — contrato de sesión insuficiente

El backend hermano sólo busca una sesión abierta para el mismo `installationId`. No detecta de forma segura una sesión del mismo usuario en otra instalación. El middleware no expone `code`, y Flutter aplana el error de login a `String`, perdiendo `domainCode`. No existe endpoint seguro de takeover. `/field-sessions/logout` sólo revoca el refresh token presentado y no sirve como takeover explícito.

### MEDIA — fotos generales

El coordinador normal intenta `saveGeneralContent` después de upload/reconcile, pero el repositorio serializa todas las referencias usando `serverPhotoId ?? photoId`. Una referencia aún no verificada puede llegar al servidor con ID local, causando “Each general photo must belong…”; la ruta de versiones sí comprueba previamente que todas estén verificadas. Se aplicará la misma precondición al flujo normal y el payload remoto sólo incluirá fotos verificadas con `serverPhotoId`.

### MEDIA — transporte y servicio mezclados

`ConnectivityMonitor` conserva internamente `ConnectivityResult`, pero lo descarta al construir el estado visible. La etiqueta pasa de “Internet disponible” a “Servidor no disponible”, por lo que la UI no puede mostrar simultáneamente “Red inalámbrica” y “Servidor no disponible”. Se modelarán transporte y servicio por separado sin convertir la captura en dependiente de la sonda HTTP.

### MEDIA — mensajes técnicos visibles

`ApiException` todavía usa `detail`/errores Zod del backend para 400/422. Se centralizará el mapeo español por código/campo; los detalles técnicos quedarán sólo en logs sanitizados.

## Fotografía: configuración y memoria

- Resolución original típica del S23 Ultra: debe medirse sobre el dispositivo; puede variar por modo/cámara y no se asumirá un valor único. El procedimiento ADB/perf registrará únicamente ancho, alto, bytes y tiempos, nunca contenido ni ruta sensible.
- Configuración actual: JPEG calidad 85, objetivo mínimo 1080×1080 mediante `flutter_image_compress`, EXIF eliminado; thumbnail calidad 75 y 400×400. El uso de `minWidth/minHeight` debe verificarse con imágenes landscape/portrait porque puede conservar una dimensión mayor de lo necesario.
- Objetivo propuesto: lado largo acotado aproximadamente a 1920 px, sin upscale, JPEG 85–88 para evidencia documental y placas; thumbnail con lado largo 400 px, JPEG 70–75. La selección final se validará con fixtures de placa/marca y tamaños reales antes/después.
- Tamaño esperado objetivo: aproximadamente 0.5–2.5 MB por normalizado y decenas de KB por thumbnail, dependiente del detalle. Se reportarán medidas reales de fixtures/dispositivo, no cifras inventadas.
- Memoria objetivo: nunca retener simultáneamente original + normalizado + segundo buffer + bitmap full-resolution. Dimensiones mediante parser de encabezado (`image_size_getter`) o resultado del procesamiento; SHA-256 por stream/chunks en isolate cuando resulte útil; codecs/buffers se liberarán inmediatamente. Los plugins/platform channels permanecerán en el isolate permitido y el trabajo Dart CPU-bound se aislará.

## Plan de implementación

1. Añadir instrumentación `[PERF][PHOTO]` en debug/profile para picker return, normalización, validación, hash, thumbnail, persistencia, draft y total; añadir métricas agregadas de caja/rebuild sin datos sensibles.
2. Rediseñar `ImageProcessingService` para que sea inyectable/fakeable y devuelva metadatos completos. Eliminar lecturas/decodes redundantes, usar I/O asíncrono y hash streaming/chunked; verificar si el plugin de compresión ya trabaja nativamente y no mover platform channels a isolates secundarios.
3. Separar adquisición, procesamiento, persistencia y actualización de UI. Mostrar “Procesando fotografía...” con estado específico y garantizar que el paso/formulario permanezca estable.
4. Reemplazar `existsSync` sólo en hot paths; convertir validaciones que requieren filesystem a snapshots/caches o funciones async fuera de `build`.
5. Crear snapshot/cache de métricas de sincronización por usuario, actualizado al cambiar cajas/cola, para que getters de UI sean O(1). Reducir `notifyListeners` redundantes y aplicar `context.select`/`Selector` en widgets de alto alcance donde aporte valor sin refactor masivo.
6. Cambiar “Revisar y enviar” a validación + persistencia local + estado listo/pendiente; arrancar sincronización independiente sólo si corresponde. Mantener “Sincronizar todo” reanudable, idempotente, con concurrencia limitada y backoff sin tormentas.
7. Separar `NetworkTransport` (none/mobile/wifi/ethernet/other) de `ServiceAvailability` (checking/available/unstable/unavailable) y adaptar textos/pruebas.
8. Filtrar fotos generales remotas a `verified + serverPhotoId`, respetar orden create → upload → verify → associate → save/version → submit, y conservar siempre el archivo local.
9. Crear traductor coherente de errores de UI en español basado en código estructurado; no mostrar excepciones, SQL, Zod, HTTP o textos backend crudos.
10. Backend: extender `AppError`/problem details con `code`; detectar sesión abierta del usuario en otra instalación después de validar la misma identidad usada en login; emitir conflicto `SESSION_ALREADY_ACTIVE` con challenge opaco, corto, de un solo propósito y expiración. Añadir endpoint conforme a convenciones reales para revocar sólo la sesión conflictiva, de forma idempotente y auditada, sin aceptar un simple userId/email. No se requiere migración destructiva; se preferirá challenge firmado si la infraestructura JWT lo permite.
11. Flutter: preservar `ApiException/domainCode` en `AppState`; sólo para `SESSION_ALREADY_ACTIVE` mostrar el texto exacto y enlace accesible “Presiona aquí”; modal de confirmación; llamada explícita de revoke; mensaje de éxito durante ~5 s; no auto-login. Timeout no asume éxito. La revocación detectada en el dispositivo anterior limpia únicamente credenciales activas, nunca `LocalDataScope`, Hive, drafts, fotos, journal o colas.
12. Pruebas: modo avión con 17 drafts/50+ fotos, formulario sin HTTP, procesamiento lento determinista y eventos UI, colas/backoff, transporte/servicio, español, general photos verificadas, ocho casos de takeover y conservación local. Añadir integración razonable y documentación de prueba física.
13. Crear `docs/android-anr-field-test.md` con `adb devices`, limpieza/captura logcat, `dumpsys activity lastanr`, `dumpsys meminfo com.aquafim.ddr001diag`, PID/CPU/threads y pasos de perfil en dispositivo real.
14. Ejecutar `dart format --set-exit-if-changed .`, `flutter analyze`, `flutter test` y suite backend correspondiente. Medir fixtures antes/después y dejar claramente separado lo demostrado por tests de lo que requiere validación física/ANR trace.

## Criterios de conservación

- No cambiar applicationId, bundle ID, nombres de cajas ni esquema Hive.
- No usar `Hive.clear()` ni eliminar evidencia, drafts, journal, queue, reportes o caches durante logout/revocación.
- No perder fotografías ante fallos de compresión, persistencia, red o takeover.
- Todo cambio de contrato será compatible con clientes anteriores: el nuevo `code` será aditivo y el inicio normal conservará su respuesta existente.

## Mediciones iniciales y finales

Pendientes de ejecutar con fixtures representativos y, para ANR real, con el S23 Ultra. Se registrarán aquí:

| Métrica | Antes | Después | Fuente |
|---|---:|---:|---|
| picker_return_ms | pendiente | pendiente | perfil/dispositivo |
| normalize_ms | pendiente | pendiente | fixture/perfil |
| hash_ms | pendiente | pendiente | fixture/perfil |
| thumbnail_ms | pendiente | pendiente | fixture/perfil |
| persist_ms | pendiente | pendiente | fixture/perfil |
| total_ms | pendiente | pendiente | fixture/perfil |
| buffers full-image simultáneos | al menos 2 lecturas + decode redundante | pendiente | inspección + perfil |

## Riesgos pendientes iniciales

- Sin `dumpsys lastanr` no puede atribuirse el ANR a una única función; el trabajo corrige riesgos críticos/altos demostrados en el hot path.
- El comportamiento exacto del plugin de compresión y el pico RSS deben verificarse en Android profile/release, no sólo con `flutter_test`.
- El backend hermano está en una rama distinta del Flutter; sus cambios se mantendrán separados, sin merge ni push, y se reportarán explícitamente.

## Informe final

### 1–4. Causa probable, modo avión, tiempos y memoria

No se obtuvo una traza ANR física, así que no se declara una causa única demostrada. La causa probable de riesgo **CRÍTICO** era el conjunto de doble `readAsBytes` + doble decode full-resolution + SHA-256 del buffer completo al volver de `ImagePicker`, seguido por persistencia y rebuild global. El riesgo **ALTO** adicional era repetir JSON decode/recorridos de todas las fotos desde getters y usar `existsSync` desde widgets. Modo avión seguía lento porque todo ese CPU, filesystem, Hive, JSON, GC y rebuild era local; la red sólo podía agravarlo.

La instrumentación productiva quedó preparada para medir picker/normalize/validate/thumbnail/hash/persist/draft/total en profile. No se inventan tiempos de cámara antes/después sin el S23 Ultra. Medición determinista disponible: SHA-256 streaming de fixture 8 MiB: **171 ms** en el host de pruebas, entregando eventos intermedios. Antes se retenían al menos dos buffers completos del normalizado y se creaban dos decodes; después no se crea ningún buffer Dart full-image ni bitmap para validación/hash. El pico RSS nativo del plugin queda pendiente de DevTools/`dumpsys meminfo` físico.

### 5–8. Imagen, Hive/rebuilds y 17 pendientes

- Normalización conservada: JPEG 87, orientación-aware 1920×1080/1080×1920, sin EXIF; thumbnail 400×400 calidad 75. Dimensiones se leen por encabezado, no mediante bitmap.
- SHA-256 usa `File.openRead()` por chunks mediante `StreamingFileDigestService`; se preservan flush/rename seguro, journal, `inspection_photos_v1` y `media_work_queue_v1`.
- `RvInspectionController` tiene estado `processingPhoto` separado de `busy`, conserva el paso y registra el tiempo de draft.
- Contadores de `AppState` son snapshots O(1), recalculados con debounce al cambiar cajas; ya no decodifican todas las fotos varias veces por build.
- Se retiró `existsSync` de contador/lista RV caliente y de upload; el filesystem se consulta async o la ausencia se representa como `missingLocal`/`errorBuilder`.
- Con 17 pendientes/50 fotos, los getters de UI ya no escalan por rebuild. Falta validar el criterio ANR real en el S23 Ultra; `flutter_test` no puede certificar Android ANR.

### 9–11. Local-first, sincronización y red

“Enviar revisión” ahora valida con el validador existente, persiste `submitPending` localmente, confirma inmediatamente y dispara `AppState.synchronize()` sin esperarlo. Offline muestra el texto requerido y no hace HTTP desde la acción. La sincronización unificada sigue serial (concurrencia 1), reanudable e idempotente, usa estados/backoff existentes y ahora hace submit de drafts `submitPending/readyToSubmit`.

El monitor separa transporte (`Sin red`, `Datos móviles`, `Red inalámbrica`, `Ethernet`, `Otra red`) de servicio (`Comprobando`, `Disponible`, `No disponible`). Wi-Fi + API caída queda representado como `Red inalámbrica · Servidor no disponible`.

### 12–13. Fotos generales y errores en español

El contenido general sólo se asocia si cada referencia está `verified` y posee `serverPhotoId`; el payload remoto excluye cualquier ID local/no verificado. El orden queda create → upload → verify → associate → save/version → submit, sin borrar copia local.

`ApiException` ya no expone `detail`/mensajes Zod en 400/422/409 genéricos. La UI recibe mensajes españoles; los logs técnicos siguen disponibles. `SESSION_REVOKED` muestra: “Tu sesión fue cerrada desde otro dispositivo. La información guardada en este equipo se conservará.”

### 14–16. Contrato takeover, backend y conservación

Backend hermano modificado en rama `fix/rv-field-session-takeover`:

- `AppError`/Problem Details incorpora `code` y datos estructurados aditivos.
- `/field-sessions/start` detecta sesión abierta del mismo email+teléfono validado en otra instalación y devuelve `409 SESSION_ALREADY_ACTIVE` con challenge JWT de audiencia específica, duración 5 minutos y vínculo a usuario, sesión conflictiva e instalación solicitante.
- `POST /field-sessions/revoke-existing` verifica el challenge, revoca sólo esa sesión/tokens, es idempotente si ya estaba cerrada/revocada y audita `work_session.takeover_revoked`.
- El dispositivo anterior obtiene `SESSION_REVOKED` al autenticar/refrescar.

Flutter actúa por `domainCode`, muestra únicamente para ese código el texto exacto y enlace accesible, modal Cancelar/Cerrar sesión, progreso anti-doble-click y éxito 5 s. No auto-login. Timeout no asume éxito. La operación sólo limpia credenciales activas en el dispositivo revocado cuando API lo detecta; nunca llama `Hive.clear`, nunca cambia cajas/esquemas y no borra drafts, fotos, journal, queue, reportes o cache.

### 17–20. Pruebas y resultados

- Nuevas pruebas Flutter: código/challenge de takeover, endpoint explícito sin limpiar storage, ocultamiento de inglés backend, transporte vs servicio, SHA-256 streaming/event loop y estado `missingLocal` sin I/O de build.
- Pruebas existentes ajustadas para mensaje de revocación y política de errores españoles.
- `dart format --set-exit-if-changed .`: ejecutado; inicialmente formateó tres archivos base no relacionados, cuyos cambios fueron retirados del diff.
- `flutter analyze`: **sin problemas**.
- Suite Flutter focalizada final: **40/40**; nuevas focalizadas: **8/8**.
- Suite local amplia, excluyendo el test opt-in de producción: llegó a **315 pruebas**, encontró dos expectativas antiguas; ambas fueron corregidas y sus archivos completos pasan después. El comando literal `flutter test` sigue incluyendo `production_endpoint_connectivity_test.dart`, que falla intencionalmente sin `ALLOW_PRODUCTION_CONNECTIVITY_TESTS=true`; no se contactó producción sin autorización explícita.
- Backend `npm run type-check`: aprobado. Backend unitarias: **108/108**. Integración SQL no ejecutada aún en este informe (requiere entorno DB y puede crear datos de prueba; no se ejecutaron migraciones).

### 21. Procedimiento ADB

Creado `docs/android-anr-field-test.md` con applicationId real, `lastanr`, logcat threadtime, meminfo, cpuinfo, PID, threads, SIGQUIT y perfil Flutter, sin borrar datos.

### 22. Riesgos pendientes

- **CRÍTICA (validación pendiente):** confirmar cero ANR y pico RSS en S23 Ultra profile/release con datos reales; requiere traza física.
- **ALTA:** `flutter_image_compress` usa platform channel/nativo; se mantuvo en isolate principal de Flutter por compatibilidad del plugin, aunque el trabajo pesado es nativo. Debe confirmarse con timeline que callbacks/copias nativas no producen pausa larga.
- **MEDIA:** todavía existen `existsSync` en rutas no modificadas (auditoría/recovery/funcional/galería); se evitó cambio indiscriminado y deben priorizarse con una traza si aparecen calientes.
- **MEDIA:** no se ejecutó integración SQL del takeover contra una DB real.
- **BAJA:** tamaño JPEG depende de escena; validar placa/marca con muestra de campo antes de distribuir.

### 23. Archivos modificados

Flutter: servicios de media/digest, `api_exception`, connectivity, `AppState`, login/repository de sesión, controller/resumen/pasos RV, coordinador/repositorio remoto, widgets de fotos, pruebas correspondientes, este plan y documentación ADB. Backend: `errors.ts`, middleware, JWT, rutas API y prueba unitaria de challenge.

### 24. Commits

Se completará con los hashes después de crear commits locales. No se hará push.
