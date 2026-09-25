# DDR001 RV 1.0.6+106 — diagnóstico y plan de certificación moto g14

## Baselines y adquisición

- App: `47dac60`, descendiente de `54ce12a` y del build instalado
  `151950d1bfb6c8889eee8221ed17fc2264f218f9`. No se usa el `main` antiguo.
- API: worktree aislado `ddr001_api_motog14`, rama
  `fix/motog14-rv-conflict-contract-20260827`, commit `6d83cfc`, sobre
  `9bf2678`.
- Dispositivo único: serial `ZY22HCL2TN`, Motorola moto g14, Android 14/API
  34, build `UTLBS34.102-91-5/54518607`.
- Package instalado: `com.aquafim.ddr001diag`, `1.0.1+101`, primera
  instalación 2026-08-11 08:01:33, actualización 2026-08-27 20:30:53.
- Actividad visible al adquirir: launcher; red predeterminada LTE validada;
  almacenamiento libre aproximado: 95 GB.
- Evidencia inicial copiada por ADB desde almacenamiento externo de la app sin
  usar `run-as` ni modificar Hive. Los hashes están junto a los artefactos en
  `dist/rv-android-in-place-certification-20260828/forensic-acquisition-initial`.

Invariantes confirmados: 27 documentos legibles, 1,340 respuestas, 263
referencias, 263 archivos presentes, cero archivos faltantes, cero huérfanos y
cero cuarentenas. El índice contenía 27 entradas: 22 apuntaban a revisiones
finalizadas y sólo 5 correspondían a trabajo activo.

## Causa raíz demostrada y réplica

El incidente no es una eliminación física. Es una combinación de proyecciones
locales y confirmaciones remotas no adoptadas:

1. La reconstrucción legacy del índice elegía una revisión canónica por grupo
   pero no excluía documentos finalizados. Así quedaron 22 finalizadas en el
   índice activo.
2. `LocalDataScope` comparaba propietario/ambiente/cuenta con casing exacto y
   rechazaba documentos 1.0.0+100 sin `dataScope`; los documentos sobrevivían
   pero podían quedar fuera de `accessible()`.
3. El dashboard compacto agrupaba por hidrante y filtraba conflictos/shells.
   El hidrante actuaba de hecho como identidad visual y ocultaba revisiones
   adicionales que sí existían por `clientInspectionId`.
4. El servidor serializa UUID de fotografías en mayúsculas y la app los
   buscaba en mapas con UUID locales en minúsculas. La réplica automatizada
   reproduce que un UUID idéntico con casing diferente no encuentra la
   referencia. Ésta es la causa directa de
   `REMOTE_VERIFIED_LOCAL_PENDING`: la confirmación existía pero no se aplicaba.
5. Las revisiones finalizadas/read-only estaban excluidas de la cola activa, de
   modo que sus 214 confirmaciones tampoco recibían un pase exclusivo de
   evidencia.
6. En 1011, `/photos/verify-batch` cerró la conexión antes de completar headers.
   Es un resultado ambiguo reintentable, no prueba de ausencia. El servidor
   mostraba 9 de 10 fotos verificadas y el archivo décimo seguía local.
7. En 2392, el servidor conserva la inspección y sus 10 fotos, pero guardar
   válvulas devuelve 409. Producción no envía código de dominio; `6d83cfc`
   conserva 409 y añade `PARCEL_VALVES_INSPECTION_LOCKED` con estado remoto.
8. `focusCases` consultaba una fuente remota parcial y podía declarar hidrante
   ausente aunque la proyección `hydrants` lo contuviera. `47dac60` unifica la
   fuente y normaliza cuenta/casing.

La réplica fue exacta para índice, UUID de fotos, scope legacy y dashboard; fue
parcial mediante dobles HTTP para timeout/conexión cerrada y códigos
401/403/404/408/409/422/429/5xx. No se provocaron fallos sobre datos reales.

## Matriz de impacto API y levantamientos

| Endpoint / contrato | Método | Consumidores conocidos | Request / response actuales | Datos internos | Cambio | Compatibilidad | Riesgo |
|---|---:|---|---|---|---|---|---|
| `/field-sessions/start` | POST | RV y levantamientos | Credenciales/dispositivo; sesión/tokens | usuarios, dispositivos, `rv.work_sessions` | ninguno | idéntica | compartido, alto |
| `/field-sessions/refresh` | POST | RV y levantamientos | refresh token; sesión/tokens | sesiones/tokens | ninguno | idéntica | compartido, alto |
| `/field-sessions/revoke-existing` | POST | RV y levantamientos | desafío/sesión; confirmación | sesiones/dispositivos/auditoría | ninguno | idéntica | compartido, alto |
| `/field-sessions/current`, `/:id/end` | GET/POST | RV; infraestructura común de sesión | estado/204 | sesiones/auditoría | ninguno | idéntica | compartido interno, medio |
| `/construction/...` y `/construction/photos/verify-batch` | varios | levantamientos exclusivamente | contratos de base survey, pasos, fotos y mapas observados en el repo de levantamientos y en la rama local de construcción de API | módulo/tablas construction y storage en esa rama; no presentes en `9bf2678` | ninguno | sin diff desde el baseline RV; no fue posible ejecutar contrato construction contra `9bf2678` | levantamientos, alto |
| `/hydrants`, `/hydrants/map`, `/hydrants/sync`, `/hydrants/:account` | GET | RV exclusivamente según repos accesibles | proyecciones de hidrante RV | `rv.hydrants`, inspecciones/reportes | ninguno | idéntica | RV, medio |
| `/checklists/rv/active` y catálogos RV | GET | RV | checklist/catálogos | tablas `rv.checklist_*`, brands, diameters, pressure ranges | ninguno | idéntica | RV, medio |
| `/inspections`, `/inspections/by-client/:id`, `/inspections/:id` | POST/GET | RV | creación idempotente y lectura con respuestas | `rv.inspections`, `rv.inspection_answers`; `rv.sp_create_inspection` | ninguno | idéntica | RV, alto |
| `/inspections/:id/answers` | PUT | RV | lote máximo 200; respuestas persistidas | answers/checklist/catálogos/auditoría | ninguno | idéntica | RV, alto |
| `/inspections/:id/parcel-valves` | PUT | RV | configuración; configuración persistida | `rv.inspections`, configuraciones, válvulas, diameters, brand element types | error RFC 7807 409 añade código/datos | éxito y HTTP 409 sin cambio; campos sólo aditivos | RV, bajo-medio |
| `/inspections/:id/photos`, `/photos/verify-batch` | POST/GET | RV | multipart/lista UUID; metadatos/integridad | `rv.photos`, storage, auditoría | ninguno | idéntica | RV, alto |
| `/inspections/:id/submit` | POST | RV | opción de checklist; resultado oficial/conflicto | inspecciones, respuestas, fotos, válvulas, reportes | ninguno | idéntica | RV, alto |
| `/visual-reports/...` | GET/POST | RV/admin RV | lectura/versionado | reportes/versiones/snapshots RV | ninguno | idéntica | RV, medio |

No se cambian DTO, validadores, middlewares, autenticación, filtros,
paginación, permisos, procedimientos ni esquemas compartidos con
levantamientos. El único cambio API está en el error de un servicio RV y no
requiere DDL. No se crea endpoint de recuperación porque las lecturas
existentes son exclusivas de RV según ambos repositorios y bastan para una
reconciliación idempotente; no se cambia su semántica.

La compatibilidad directa del módulo construction no puede declararse completa
contra `9bf2678`, porque ese baseline no contiene dicho módulo. Sí se verificó
que el diff `9bf2678..46b5ee5` no toca rutas construction ni contratos de sesión
compartidos, y se ejecutaron las pruebas disponibles de ambos repositorios.

## Plan ejecutable y criterios

1. Reparar el índice con snapshot confirmado, de forma reanudable e
   idempotente; excluir finalizadas, read-only, canceladas, archivadas y
   superseded sin borrar documentos.
2. Mantener historial lossless por `clientInspectionId`, comparación de scope
   y UUID case-insensitive, y archivado reversible.
3. Ejecutar un pase de evidencia separado para revisiones históricas. Sólo la
   respuesta `confirmed` de `verify-batch` cambia estado local; `not_found` o
   hash incompatible habilitan reenvío únicamente del archivo local exacto.
4. Exportar por revisión hashes canónicos local/remoto de respuestas,
   diferencias por item, hashes de fotos, evidencia de submit, request IDs y
   una de las seis clasificaciones autorizadas. Nunca exportar tokens ni
   inventar valores.
5. Probar upgrade, cierres/reintentos, todos los códigos HTTP solicitados,
   múltiples revisiones, casing/scope, JSON/colas/fotos y no pérdida.
6. Construir `1.0.6+106` production con package/firma existentes. Instalar con
   `adb install -r` únicamente después de PRE automático y de verificar firma.
7. Comparar PRE/POST 27/1,340/263/263, índice esperado 5, UI e inventario por
   revisión. Repetir sólo diferencias reintentables.

## Resultado ejecutado

La versión final es `1.0.6+106`, commit
`7c3e06dfef18b5201d3f9e68602c4c5321cd1a12`. Se instaló exclusivamente con
`adb install -r`; `firstInstallTime` permaneció en
`2026-08-11 08:01:33`, por lo que Android conservó el almacenamiento de la
aplicación. La firma v2 coincide con la instalada:
`d1d9ec17be22dff0320afed5c2e3031e013738beaee35c7303fd8ac18485af2c`.

Comparación automática del diagnóstico inicial contra el runtime final:

| Invariante | PRE | POST final |
|---|---:|---:|
| documentos RV | 27 | 27 |
| respuestas capturadas | 1,340 | 1,340 |
| referencias fotográficas | 263 | 263 |
| documentos fotográficos | 263 | 263 |
| archivos presentes | 263 | 263 |
| índice activo | 27 | 5 |
| cuarentena / huérfanos / faltantes | 0 / 0 / 0 | 0 / 0 / 0 |

No falta ningún `clientInspectionId`, ningún `photoId` ni existe transición de
archivo presente a ausente. Las 22 finalizadas permanecen en historial y
salieron del índice activo. La vista física **Todas mis revisiones** fue
verificada en el moto g14 y enumera trabajos por `clientInspectionId`, sin
colapsar cuentas/hidrantes repetidos.

El primer pase online adoptó las 214 confirmaciones históricas. La ejecución
completa y un reinicio no destructivo dejaron las 263 fotografías como
`REMOTE_VERIFIED_LOCAL_VERIFIED`, cero pendientes de foto y cero errores. No se
eliminó ningún archivo local. La aparente regresión observada durante la
certificación resultó ser un falso negativo del exportador al leer una cola
JSON versionada; la foto, referencia e integridad ya estaban verificadas. El
exportador final usa las cuatro fuentes canónicas y tiene prueba de regresión.

Cross-check final de las 27 revisiones:

- `CAPTURE_INCOMPLETE_REQUIRES_TECHNICIAN` (4): 993, 994, 995 y 1011. Los
  campos faltantes se muestran y no se autocompletaron.
- `CONTRACT_CONFLICT_REQUIRES_ACTION` (1): 2392. Conserva 53 respuestas, 10
  archivos y 10 fotos remotas; producción continúa devolviendo HTTP 409 sin
  código de dominio. El cambio API no desplegado añade
  `PARCEL_VALVES_INSPECTION_LOCKED` sin cambiar el status.
- `REMOTE_CONFIRMATION_PENDING` (22): 74, 963, 979, 987, 988, 998, 1008,
  1015, 1020, 1031, 1329, 1331, 1332, 1338, 1339, 1340, 2351, 2356, 2397,
  2415, 2422 y 2451. Todas están `submitted`, sin campos locales faltantes,
  pero el contrato remoto diverge en tres o cuatro reactivos compartidos; no se
  sobrescribieron respuestas en inspecciones enviadas. Algunas fotos legacy
  tienen confirmación remota por UUID pero no un hash cliente comparable, por
  lo que no se declara equivalencia byte a byte sin evidencia.

En 1011 las 10 fotos existen localmente y las 10 aparecen verificadas en el
servidor. Nueve tienen hash cliente comparable; la foto `back` está confirmada
por el servidor pero el hash normalizado remoto difiere del archivo cliente.
La captura contiene 13 respuestas y 13 requisitos aún no capturados. Se
mantiene visible para intervención humana. En 2392 no falta evidencia; el único
bloqueo operativo confirmado es el 409 de válvulas y las cuatro divergencias de
contrato de respuesta.

## Validación

- App: `flutter analyze` sin issues; `flutter test` 401/401; pruebas específicas
  de upgrade/recovery/índice/scope/dashboard/fotos/diagnóstico/no pérdida en
  verde; `git diff --check` en verde.
- `dart format` pasa para todos los archivos modificados. El chequeo global
  informa dos archivos no modificados por esta rama
  (`rv_work_dashboard_projection_test.dart` y
  `hydrant_account_resolution_test.dart`) que ya diferían del formatter en
  `47dac60`; no se mezcló ese cambio mecánico con la corrección certificada.
- API: `npm run type-check`, `npm run lint` y pruebas de contrato en verde;
  suite disponible 7/7, con 32 integraciones SQL omitidas por no existir DB de
  prueba. No se ejecutó migración.
- Levantamientos: `flutter analyze` sin issues y 96/96 pruebas. El worktree
  preexistente sucio no fue modificado.
- Build release production: package, URL, permisos, versionado, SHA/fecha y
  firma verificados. APK SHA-256:
  `621fea6aa87ef9905f64791c4125dc3418ccecb3736a0e5c876405aaa1a6611f`.

No se desplegó API. Para desplegarla: revisar `6d83cfc` y `46b5ee5`, ejecutar
las integraciones contra una base aislada, desplegar primero en staging,
confirmar que 2392 recibe el mismo HTTP 409 con el código de dominio aditivo y
volver a correr contratos de levantamientos antes de producción.

Rollback no destructivo: dejar de sincronizar y conservar `1.0.6+106` con sus
datos. Si se requiere revertir código, construir un APK con la misma firma y
un `versionCode` mayor que 106 que restaure el comportamiento anterior pero
mantenga lectura de los esquemas actuales. Nunca desinstalar, limpiar ni
restaurar cajas sobre datos más nuevos.

Recomendación: **NO-GO para declarar recuperación remota al 100% o desplegar
API a producción** mientras las 22 divergencias de respuestas y el 409 de 2392
no se resuelvan en staging. **GO para mantener 1.0.6+106 instalada en el moto
g14**, porque conservación, visibilidad, índice y confirmación de las 263 fotos
quedaron certificadas y los pendientes permanecen visibles y accionables.
