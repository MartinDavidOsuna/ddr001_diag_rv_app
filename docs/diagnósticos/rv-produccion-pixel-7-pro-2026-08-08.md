# Auditoría RV en producción — Pixel 7 Pro

Fecha: 2026-08-08  
Repositorio auditado: `ddr001_diag_rv_app`  
Rama: `fix/rv-main-reconciliation-and-map-sync`  
Commit: `22d619a fix(android): restore production startup config and launcher icon`  
Ambiente configurado: `http://cifra.aquafim.com:3002/api/v1`  
Dispositivo: Google Pixel 7 Pro (`cheetah_beta`, serial ADB `27301FDH3004R7`)  
APK instalada: `com.aquafim.ddr001diag`, versión `0.2.33+46`

## Alcance y preservación

Se hizo una auditoría sin modificar código, configuración, datos locales ni datos remotos. No se inició ni envió ninguna revisión, no se tomaron fotografías, no se revocaron sesiones y no se generaron registros de prueba en producción. Los únicos entregables nuevos son este informe y el SQL de reversión sin operaciones.

La inspección incluyó:

- ejecución real de la APK instalada en el Pixel;
- evidencia de arranque y red mediante ADB/logcat;
- navegación no destructiva por Inicio, Nueva revisión, Hidrantes, Sincronización y Mapa;
- contraste de las ramas RV acumulativas contra la rama instalada;
- revisión de la proyección global, filtro de nueva revisión, caché y refresco de sesión;
- `flutter analyze` y la suite completa `flutter test`.

## Resultado ejecutivo

La regla funcional solicitada sí está implementada en la rama actual, pero no se aplica con los datos que la APK tiene disponibles en el dispositivo. La pantalla **Nueva revisión visual** mostró 100 resultados y todos como **Disponible para revisión**. El catálogo local contiene 1,169 hidrantes; ninguno expuso estado global revisado en la interfaz observada.

No fue posible demostrar que la API de producción esté devolviendo incorrectamente el estado global, porque la sesión persistida en el Pixel no pudo renovarse: en cada arranque se produjeron tres respuestas 401 no controladas. Por ello la app siguió operando con un snapshot local previo. La API está accesible, pero rechazó las solicitudes autenticadas de esa sesión.

La causa comprobada del comportamiento actual es la combinación de:

1. sesión persistida inválida/revocada cuyo refresh responde 401;
2. catálogo local que permanece disponible aunque no pudo refrescarse;
3. contrato Flutter tolerante a datos antiguos: si faltan `rvStatus` o `availableForRv`, el hidrante se interpreta como `available`/`true`.

Esto es un comportamiento *fail-open*: un snapshot viejo o una respuesta API sin los campos globales convierte visualmente todos los hidrantes en capturables.

## Hallazgos por severidad

### CRÍTICA — exclusividad global no efectiva con snapshot heredado/incompleto

En `CachedHydrant.fromApi`, los campos ausentes se convierten en:

- `rvStatus = 'available'`;
- `availableForRv = true`.

La regla de UI oculta correctamente los revisados solamente cuando `availableForRv` llega como `false`. Con el catálogo actual del Pixel, todos los registros visibles quedaron disponibles. Esto permite iniciar un borrador sobre un hidrante potencialmente revisado si el servidor no vuelve a bloquearlo en una operación posterior.

### ALTA — refresh 401 no controlado durante el arranque

Se reprodujo dos veces mediante cierre forzado y relanzamiento. Logcat registró tres `Unhandled Exception: DioException [bad response]` con HTTP 401 por arranque; la traza llega a `ApiClient._performRefresh`, línea 254.

Aun así, Inicio muestra al usuario local **Martin Osuna / TEST** y el indicador verde **En línea**. La pantalla de sincronización muestra **Conexión disponible / Conectado a la API**, aunque las solicitudes autenticadas no pueden completarse. La app no distingue de forma visible entre “servidor accesible” y “sesión autenticada utilizable”.

### ALTA — no hay evidencia fresca para decidir disponibilidad

`synchronizeAssignments()` conserva la caché cuando las solicitudes fallan. Eso es correcto para local-first, pero no existe en la pantalla de nueva captura una advertencia que impida tratar como libres estados globales desconocidos/antiguos. La caché offline sirve para consultar, pero su ausencia de proyección global no debe autorizar una nueva revisión.

### MEDIA — mapa sin puntos utilizables

El mapa informó **0 hidrantes · 1169 sin coordenadas**. También mostró el mensaje de trabajo sin conexión mientras el encabezado indicaba **En línea**. El snapshot completo está persistido, pero la información geográfica del catálogo almacenado no permite dibujar marcadores.

### MEDIA — estado visual de conectividad contradictorio

Durante la misma sesión se observaron simultáneamente:

- Inicio: **En línea**;
- Sincronización: **Conectado a la API**;
- Mapa: **Sin conexión**;
- logcat: refresh autenticado rechazado con 401.

Los indicadores no representan una fuente única de verdad.

## Evidencia funcional en el Pixel

| Prueba | Resultado |
|---|---|
| Arranque limpio | Renderiza Inicio; `first_frame_ms=37`, `local_storage_recovery_ms=684`, `bootstrap_total_ms=1129` |
| Renovación de sesión | Falla: tres excepciones 401 no controladas |
| Nueva revisión sin búsqueda | 100 resultados visibles, todos disponibles |
| Búsqueda exacta de cuenta 960 | Un resultado; aparece disponible |
| Regla de cuenta exacta | Implementada: una cuenta exacta puede mostrarse aunque esté revisada |
| Mis hidrantes | 0 asignados; sincronización no actualiza por sesión inválida |
| Dashboard | Todos los seis rubros en 0; sin revisiones recientes |
| Sincronización | Cola local en 0; no se generaron operaciones |
| Mapa local-first | Abre desde caché; 1,169 registros sin coordenadas y 0 marcadores |
| Persistencia tras reinicio | Conserva usuario y catálogo local |

La cuenta 960 se usó solo como consulta exacta y no se abrió ni modificó un borrador.

## Validación del contrato de producción

Una solicitud no autenticada directa a `GET /api/v1/hydrants/sync` respondió 401 con el formato Problem Details esperado y confirmó que el endpoint existe y exige token. No se extrajo ni alteró el almacenamiento seguro del equipo.

Conclusión sobre API:

- confirmado: producción está accesible y rechaza el refresh persistido en este Pixel;
- confirmado: la APK no recibió una proyección global fresca durante las pruebas;
- no confirmado: que una respuesta autenticada actual de `/hydrants/sync` omita `rvStatus`/`availableForRv`;
- muy probable: el snapshot local fue creado con un contrato anterior o con filas sin proyección/backfill global;
- para separar definitivamente contrato API de caché heredada se requiere iniciar sesión nuevamente y capturar una respuesta autenticada fresca, sin borrar previamente la caché.

## Reconciliación de ramas Flutter

Las ramas remotas antiguas no son ancestros Git directos del HEAD: sus implementaciones fueron reintegradas semánticamente en commits nuevos sobre la línea actual. No falta la superficie de código de esas funcionalidades.

| Funcionalidad | Rama fuente histórica | Implementación en rama actual | Estado auditado |
|---|---|---|---|
| Sesión permanente | `feature/permanent-field-session` | `1fee9f9`, ampliada por `c202f4a` y `0c896d9` | Presente; regresión runtime 401 |
| Estado RV global/exclusividad | `feature/global-rv-status-exclusivity` | `9df7b5f` | Presente; datos runtime no efectivos |
| Versionado inmutable | `feature/immutable-rv-versioning` | `eb36072` | Presente; pruebas pasan |
| Visor móvil de reporte | `feature/mobile-rv-report-viewer` | `493d3ab` | Presente; no accesible sin un hidrante marcado revisado |
| Rangos globales de presión | `feature/global-pressure-ranges` | `84bd81e` | Presente; pruebas pasan |
| Marca ilegible | `feature/rv-illegible-brand` | `7ae1902` | Presente; pruebas pasan |
| Filtro no definido | `feature/rv-filter-element-undefined` | `bd05f80` | Presente; pruebas pasan |
| Conexión piloto | `feature/rv-pilot-connection` | `87a87b9` | Presente; pruebas pasan |
| Fotos/observaciones generales | `feature/rv-general-photos-observations` | `385ed88` | Presente; pruebas pasan |
| Endurecimiento operativo | `feature/rv-operational-hardening` | `0cf6c95` | Presente; pruebas pasan |
| ANR/local-first/takeover | rama acumulativa posterior | `c202f4a` | Presente; pruebas de contrato pasan |
| Medidor/cable/fotos | rama acumulativa posterior | `fef06ef` | Presente |
| Borradores/dashboard | rama acumulativa posterior | `4cbafc0` | Presente; pruebas de proyección pasan |
| Snapshot/mapa incremental | reconciliación actual | `0c896d9` | Presente; caché funciona, coordenadas faltantes |
| Configuración/icono Android | reconciliación actual | `22d619a` | Presente en recursos y APK instalada |

## Reglas de código verificadas

`hydrantVisibleForNewRv` implementa:

1. cuenta exacta: siempre visible;
2. borrador/trabajo local: visible;
3. resto: visible solo si `isActive && availableForRv`.

El CTA implementa:

- `availableForRv == true`: iniciar/continuar revisión;
- `availableForRv == false`: abrir `/visual-report/:account`.

Por tanto, el defecto observado no es que la fusión haya eliminado el filtro. El filtro recibe `availableForRv=true` para todo el snapshot disponible.

## Pruebas automatizadas

- `flutter analyze`: **sin problemas**, 85.1 s.
- `flutter test`: **309 pruebas aprobadas**, 0 fallas, aproximadamente 37 s de ejecución reportada por Flutter.
- Subsuite dirigida de estado global, caché, visor, endurecimiento y submit: **34 pruebas aprobadas**.

Las pruebas confirman el comportamiento esperado con fixtures que sí incluyen los campos globales. No cubren una migración de caché real donde esos campos no existan ni una sesión persistida cuyo refresh sea rechazado durante el bootstrap.

## Registros generados y reversión

Registros remotos generados: **0**.  
Borradores locales generados: **0**.  
Fotografías generadas: **0**.  
Sesiones creadas/revocadas: **0**.

El archivo `rv-produccion-pixel-7-pro-2026-08-08-rollback.sql` es deliberadamente no operativo y deja evidencia de que no existen IDs de prueba que borrar. No debe eliminarse información productiva para esta auditoría.

## Recomendaciones para corrección posterior

Estas recomendaciones no se implementaron por la restricción de auditoría:

1. Tratar proyección global ausente como estado `unknown`, nunca como disponible.
2. Impedir una nueva captura normal mientras el estado global sea desconocido o el snapshot no haya sido actualizado/autorizado, conservando consulta offline.
3. Manejar un refresh 401 sin futuras no observadas y llevar la UI a reautenticación preservando Hive, fotos, drafts y colas.
4. Separar `servidor accesible`, `sesión válida` y `datos actualizados` en los indicadores.
5. Tras reautenticar, verificar en la respuesta fresca de `/hydrants/sync` que cada registro incluya `rvStatus`, `availableForRv`, `officialInspectionId` y `lastStatusChangedAt`.
6. Verificar el backfill productivo de la proyección global para las más de 100 revisiones ya oficiales.
7. Añadir una prueba de migración de caché heredada y una prueba de bootstrap con refresh 401.

## Limitaciones

No se hizo re-login porque implicaba modificar el estado remoto de sesión y podía activar takeover. Tampoco se envió una revisión artificial a producción. En consecuencia, el contrato autenticado fresco y el bloqueo final de duplicados en submit no pudieron validarse de extremo a extremo en esta sesión.
