# Auditoría RV con escritura en producción — Pixel 7 Pro

Fecha: 2026-08-08  
Repositorio: `ddr001_diag_rv_app`  
Rama: `fix/rv-main-reconciliation-and-map-sync`  
Base auditada: `22d619a`  
Ambiente: producción (`http://cifra.aquafim.com:3002/api/v1`)  
Dispositivo: Google Pixel 7 Pro, paquete `com.aquafim.ddr001diag`  
Versión final instalada: `0.2.34+47`

## Resultado ejecutivo

Se auditó la aplicación desde login, se inició una sesión real, se escribieron datos de prueba y se tomaron fotografías. No se reprodujo ANR ni congelamiento al regresar de Google Camera tras tres capturas consecutivas.

Se comprobaron y corrigieron tres regresiones reales:

1. El mapa arrancaba centrado en el GPS y solicitaba una zona de 2 km, en lugar de mostrar el catálogo local completo. Ahora abre encuadrando todos los hidrantes con coordenadas y deja **Mi ubicación** como acción explícita.
2. Producción devolvió al menos un hidrante con estado RV terminal y, simultáneamente, `availableForRv=true`. La app ahora aplica una defensa local: un estado global terminal nunca se proyecta como disponible.
3. La pantalla de sincronización fallaba cuando existía un ID de foto accesible sin proyección en `mediaBox`. Ahora lo trata de forma conservadora como `pendingUpload` y sigue renderizando.

La cuenta exacta **1497** quedó validada en el dispositivo como **Ya revisado**. Al tocarla abre **Reporte RV**, versión 1, creado por otro inspector; no abre ni crea una revisión nueva.

## Escrituras de prueba

### Hidrante manual local

Se creó el identificador de prueba `AUDIT-RV-20260808-124300-P7P`, con ID local `9e752b43-f19b-4484-91cf-56e339ebde07`, y se capturaron tres fotografías:

- `2c57930c-f8e5-463f-86c6-e72f8719d7b0`
- `bdfce528-95d2-4dcd-93a2-fb84bf3be0f9`
- `e888b5f9-1f77-42ae-a373-602e55658393`

El `POST /hydrants/manual` no obtuvo confirmación remota. El hidrante, el borrador y sus fotografías permanecen solamente en el Pixel y aparecen pendientes. La interfaz traduce incorrectamente este fallo como **Sin conexión**, aun cuando la API está disponible.

### Cuenta existente 1130

Sobre la cuenta **1130**, marcada disponible por el servidor, se creó un borrador parcial, se capturó GPS/conectividad y una fotografía. Se ejecutó sincronización individual y la foto alcanzó estado remoto `verified`, confirmando escritura en la API/almacenamiento de producción y verificación de integridad.

No se envió oficialmente el formulario: no se contestaron los campos obligatorios restantes y no se generó deliberadamente un reporte oficial completo.

Las coordenadas exactas y el contenido de las fotografías no se registran en este informe.

## Auditoría del mapa

Antes del refresco forzado, la caché contenía **1,169 hidrantes y 0 coordenadas utilizables**. La versión anterior intentaba localizar el dispositivo y cargar solo un radio de 2 km.

Tras omitir una vez el ETag heredado y solicitar el snapshot completo, producción entregó:

- 1,170 registros totales;
- 21 hidrantes con coordenadas WGS84 válidas;
- 1,149 hidrantes sin coordenadas.

La pantalla final abre mostrando y encuadrando los 21 puntos disponibles, incluidos estados pendientes y terminados. No solicita ni centra automáticamente la ubicación personal. **Mi ubicación**, **Mostrar todos los hidrantes** y **Actualizar zona** continúan disponibles.

El hecho de que solo 21 de 1,170 hidrantes tengan coordenadas confirma que el backfill SQL de producción todavía no cubre el universo; es un problema de datos/API, no del encuadre Flutter.

## Exclusividad RV global

Evidencia observada en producción:

- mapa: cuenta 1497, **RV terminada**;
- contrato cacheado: estado terminal y bandera de disponibilidad contradictoria;
- lista de nueva revisión antes del parche: **Disponible para revisión**;
- lista tras el parche: **Ya revisado**;
- acción tras el parche: abre el reporte oficial de otro inspector.

La app ahora considera terminales `submitted`, `completed`, `validated`, `conflict`, `returned` y `rejected`, aunque la API marque disponibilidad verdadera. La corrección definitiva también debe hacerse en la API para que `availableForRv` sea coherente en todas las versiones cliente.

La lista inicial sigue mostrando hasta 100 hidrantes disponibles. Los ya revisados no aparecen en esa lista normal; una búsqueda por cuenta exacta sí los muestra para consulta, que es la regla solicitada.

## Fotografías y estabilidad

- Tres capturas consecutivas sobre el hidrante manual regresaron a la misma pantalla.
- Una captura sobre la cuenta 1130 se procesó, subió y verificó.
- No hubo ANR, pantalla congelada ni reinicio de paso.
- La reinstalación mediante `adb install -r` conservó sesión, Hive, borradores y fotografías.
- La pantalla de sincronización muestra 1 diagnóstico local pendiente, 3 fotos pendientes y 1 foto verificada sin volver a producir la pantalla gris.

## Cambios realizados

- `lib/features/map/map_page.dart`: catálogo completo local como vista inicial, `CameraFit.bounds`, refresco forzado si la caché tiene cero coordenadas y GPS solo bajo petición.
- `lib/features/hydrants/data/hydrant_repository.dart`: opción de snapshot forzado sin `If-None-Match`.
- `lib/core/services/app_state.dart`: recarga controlada del catálogo y su proyección.
- `lib/features/hydrants/data/hydrant_api_models.dart`: estado global terminal prevalece sobre disponibilidad contradictoria.
- `lib/features/sync/sync_page.dart`: tolerancia a proyecciones de foto Hive faltantes.
- `pubspec.yaml`: versión incremental `0.2.34+47`.
- Pruebas unitarias/regresión para mapa completo, snapshot sin ETag, exclusividad global y foto sin estado Hive.

## Validaciones finales

| Validación | Resultado |
|---|---|
| Instalación firmada con `adb install -r` | Correcta; datos conservados |
| Inicio de sesión en producción | Correcto |
| Fotografías reales | 4 capturas; sin ANR |
| Escritura remota | Foto de cuenta 1130 verificada |
| Mapa inicial | 21 marcadores encuadrados, no GPS |
| Cuenta 1497 | Ya revisado; abre reporte oficial |
| Sincronización | Renderiza sin excepción |
| `flutter analyze` | Sin problemas |
| `flutter test` | 313 pruebas correctas, 0 fallos |
| Build release producción | Correcto, APK de 58.5 MB |

## Rollback y riesgos

El archivo `rv-produccion-pixel-7-pro-escritura-2026-08-08-rollback.sql` contiene el procedimiento seguro para identificar el borrador/foto de la cuenta 1130 por usuario y ventana temporal antes de eliminar. Arranca en modo inspección y no debe cambiarse a aplicación hasta confirmar los IDs y el esquema desplegado.

Los artefactos `AUDIT-RV-20260808-124300-P7P` y sus tres fotos son locales; SQL no puede eliminarlos del Pixel. Deben eliminarse con la función de borrado local una vez cerrado el rollback remoto. No se debe limpiar Hive globalmente.

Riesgos pendientes:

- solo 21 hidrantes tienen coordenadas remotas utilizables;
- la API puede emitir estado terminal junto con `availableForRv=true`;
- el alta de hidrante manual falla y su mensaje visible confunde fallo de endpoint con falta de red;
- no se obtuvo desde la UI release el ID remoto de la foto verificada; el rollback exige descubrimiento previo y confirmación manual para evitar borrar evidencia real;
- los warnings de build sobre versiones futuras de Gradle/AGP/Kotlin y ausencia de Cupertino Icons no afectan esta ejecución, pero deben atenderse antes de futuras actualizaciones mayores.

## Reconciliación posterior: eliminación local y datos territoriales

Se auditó nuevamente el historial después de detectar que la acción de
eliminación no era visible desde las rutas normales:

- La funcionalidad de borrado pertenece a `6a44d53` y su versión reconciliada
  más completa es `4cbafc0` (`feat(rv): manage local drafts and dashboard
  groups`). El repositorio actual ya conservaba sus reglas de propiedad y
  limpieza, pero la acción estaba disponible solamente al final del resumen.
- La UI sin localidad/municipio corresponde al comportamiento de `main`. Las
  ramas posteriores de catálogo reintrodujeron esos campos en búsqueda, tarjetas,
  confirmación y alta manual. No se copió `main` ciegamente porque perdería las
  funcionalidades RV acumulativas.

Integración final:

- **Eliminar revisión local** aparece también en la ficha accesible desde
  Inicio, Revisiones recientes y los rubros del dashboard.
- Solo aparece al creador, para una revisión editable que nunca obtuvo
  `serverInspectionId`.
- Al confirmar elimina documento, índice activo, fotografías propias, archivos,
  cola de medios, cola de sincronización y operation journal relacionados.
- Después reconstruye la proyección de hidrantes para retirarla inmediatamente
  de Revisiones recientes, Sin sincronizar y contadores. Si existe estado remoto,
  vuelve a quedar visible ese estado.
- Localidad y municipio dejaron de mostrarse y de participar en búsquedas, el
  modal de confirmación y el alta manual.
- Los campos se conservan internamente en modelos/cache y contrato para leer
  datos históricos sin migración destructiva ni ruptura de compatibilidad.

Validación posterior: `flutter analyze` sin problemas, 316 pruebas aprobadas,
build release de producción correcto e instalación `adb install -r` conservando
los datos. En el Pixel se verificó visualmente la acción sobre
`AUDIT-RV-20260808-124300-P7P` sin pulsar **Eliminar**; también se verificó la
ausencia de localidad/municipio en selección y alta manual.

## Diagnóstico de conectividad y sesión — 8 de agosto, 15:13

La API de producción sí fue alcanzable. `GET /health/live` respondió HTTP 200;
`/field-sessions/current`, `/hydrants/sync`, `/hydrants`,
`/profile/today-stats` y `/checklists/rv/active` respondieron HTTP 401 sin
credenciales, confirmando conectividad y existencia de las rutas protegidas.
Android reportó la red Wi-Fi `AGRIENLACE` conectada, validada y utilizable.

La causa del aviso **Sesión sin verificar — modo sin conexión** fue una sesión
persistida cuyo access token y refresh token ya no eran aceptados. El refresh
respondía 401 sin código de dominio y la app lo conservaba erróneamente como
una falla recuperable sin Internet. Además, un `DioException` no capturado podía
dejar `assignmentSyncing=true`, manteniendo indefinidamente el indicador de
progreso.

Correcciones verificadas:

- todo HTTP 401 emitido por `/field-sessions/refresh` invalida únicamente las
  credenciales de sesión; Hive, borradores, fotos y colas permanecen intactos;
- un rechazo de autenticación ya no activa el modo sin conexión: vuelve al login
  con un mensaje español de sesión vencida;
- la sincronización de hidrantes libera siempre su indicador mediante `finally`;
- al iniciar se retiran proyecciones manuales huérfanas del borrado antiguo solo
  si son del creador, no tienen ID remoto, conservan una cola no sincronizada y
  ya no existe ninguna revisión asociada. Esto cubre el residuo
  `AUDIT-RV-20260808-124300-P7P` sin borrar evidencia válida.

Se instaló la compilación `0.2.34+47` mediante `adb install -r`. En el Pixel la
app abrió el login, mostró **Red inalámbrica** y no presentó el banner falso de
modo sin conexión. `flutter analyze` terminó sin problemas y las 329 pruebas
automatizadas finalizaron correctamente.

## Reconciliación del estado 1497

Se reprodujo que 1497 aparecía simultáneamente como **Sincronizado** y dentro de
**Pendientes hoy** / **Sin sincronizar**. No era una transición nueva del reporte
oficial: el reporte vigente tiene último cambio el 6 de agosto de 2026. Existían
proyecciones obsoletas de una captura posterior y tres reglas incompatibles:

- el dashboard priorizaba correctamente el estado global oficial;
- Perfil contaba borradores locales y el escalar de `/profile/today-stats`;
- el filtro Sin sincronizar trataba una traza de auditoría pendiente como si
  fuera información del diagnóstico;
- la pantalla Sincronización solo contaba `sync_queue`, por lo que indicaba cero.

Se centralizó la precedencia: un reporte oficial remoto prevalece sobre un
borrador normal obsoleto, excepto cuando existe trabajo explícito de nueva
versión. Las trazas ya no convierten al hidrante en pendiente y los contadores de
sincronización incluyen borradores vigentes, deduplicados con la cola. Los IDs
devueltos por estadísticas remotas permiten excluir un borrador pendiente que ya
fue superado por el reporte global oficial.

Validación en el Pixel después de reinstalar sin borrar datos:

- Perfil: **0 Enviados, 0 Pendientes, 0 Sin sincronizar**;
- filtro **Sin sincronizar**: 0 resultados;
- filtro **Pendientes hoy**: 0 resultados;
- dashboard general: 1 Enviado (1497);
- 0 Enviados en Perfil es correcto porque esa tarjeta es exclusivamente del día
  actual y el reporte oficial de 1497 cambió el 6 de agosto, no el 8 de agosto.
