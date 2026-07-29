# Defecto crítico 12.5.3-M01 — Aislamiento de datos

## Diagnóstico inicial

La inspección reveló una mezcla de fuentes:

1. La API `GET /hydrants?scope=all` construía `latestRvInspectionId`,
   `latestRvStatus` y el agregado de enviados sobre todas las inspecciones. El
   token se validaba, pero `scope=all` anulaba el filtro por usuario.
2. `VisualInspectionRepository` y `RvDraftRepository.pending()` recorrían todas
   las entradas de `visual_inspections_v1` sin ámbito de sesión.
3. `AppState._applySession` usaba `work_session_id` como `AppUser.id`; este valor
   cambia en cada inicio de sesión y no representa la identidad estable del
   usuario contenida en el token.
4. `SyncQueueItem` no conservaba propietario, cuenta ni ambiente. Una sesión
   podía considerar pendientes operaciones heredadas.
5. El cierre de sesión retiraba tokens, pero no invalidaba el ámbito de los
   repositorios ni vaciaba listas en memoria.

Por tanto, los registros visibles procedían de una combinación de API, Hive y
estado en memoria. No es un defecto exclusivamente visual.

## Regla implementada

- Identidad estable: `userId` emitido por la API, nunca un valor aportado por
  Flutter.
- Borradores: solo propietario.
- Escrituras, fotos, válvulas y submit: solo propietario.
- Enviadas: propietario; la ampliación por cuadrilla requiere permiso explícito
  y no se infiere en el cliente.
- Administración: rutas `/admin/*` y bandeja separada.
- Documentos históricos sin propietario estable: no visibles/sincronizables en
  la bandeja de campo; quedan disponibles para revisión administrativa.
- Hive y colas se conservan físicamente, pero se filtran por
  `environment/account/user`.

## Evidencia inicial sanitizada

| Identidad | Rol | Endpoint/fuente | Resultado previo |
|---|---|---|---|
| `admin.test@example.invalid` | admin | `/admin/*` | alcance administrativo |
| `field.test@example.invalid` | field | `/hydrants?scope=all` | estados globales |
| usuario nuevo | field | `visual_inspections_v1` | documentos de otros propietarios |
| usuario nuevo | field | memoria de `AppState` | lista anterior no invalidada |

No se registran tokens, observaciones, fotografías ni datos personales
completos.

## Archivos y estrategia

- API: contrato de sesión estable, alcance de listados y guardas por recurso.
- Flutter: ámbito local central, filtrado de documentos, fotos y colas, y
  reinicio de estado al cambiar de sesión.
- SQL: diagnóstico de propietarios, sesiones/cuadrillas y registros ambiguos.
- Pruebas: matrices A/B, acceso por ID, cola offline y cambio de ambiente.

## Resultado final

### Implementación

- La API deriva identidad y alcance exclusivamente del token/sesión resuelta en
  servidor. El catálogo global de hidrantes ya no adjunta inspecciones ajenas.
- Las lecturas y escrituras por ID, respuestas, válvulas, fotografías y envío
  aplican propiedad del recurso. Una colisión idempotente entre propietarios no
  reutiliza la inspección ajena.
- Flutter utiliza `LocalDataScope` y conserva `environment`, `accountId`,
  `ownerUserId` y `brigadeId` en documentos y operaciones sensibles.
- Los repositorios de inspecciones, borradores, hidrantes, fotografías y cola
  filtran antes de entregar o sincronizar datos.
- Al cerrar/cambiar sesión se invalidan selección, listas, checklist,
  controladores y alcance activo, sin eliminar datos persistidos.
- Las entradas históricas sin ámbito confiable quedan conservadas pero ocultas
  para usuarios de campo y señaladas para revisión administrativa.

### Evidencia automatizada

- Flutter: formato aprobado; análisis sin incidencias; 220/220 pruebas
  aprobadas; APK debug generado.
- API con Node 22.17.1: lint, type-check, 82/82 unitarias, 10/10 de integración
  y build aprobados.
- Las pruebas de integración verificaron que el usuario intruso no recibe el
  identificador/estado ajeno en `/hydrants?scope=all`, no abre la inspección y
  no puede escribir respuestas.
- SQL ejecutado exclusivamente en `RevisionVisualStarter_Test`: cero
  inspecciones sin creador, propietarios inexistentes, sesiones inexistentes,
  diferencias propietario/sesión, cuadrillas requeridas ausentes o referencias
  de cuadrilla huérfanas.

### Evidencia física

- Pixel 7 Pro actualizado mediante `adb install -r` a `0.2.1+13`, sin
  desinstalar ni limpiar almacenamiento.
- Usuario A creó el borrador `TEST-12-5-3-NORMAL`.
- Usuario B inició una sesión nueva: recibió cero borradores y no vio el de A.
- Usuario B creó `TEST-12-5-3-OFFLINE`.
- Al volver a A reapareció únicamente `TEST-12-5-3-NORMAL`; el borrador de B
  permaneció oculto.
- Los documentos históricos anteriores, carentes de `dataScope`, no se
  mostraron al usuario de campo y no fueron eliminados.

### Límites y pendientes

- La administración permanece deliberadamente separada en rutas `/admin/*`;
  esta aplicación de campo no implementa una bandeja administrativa. Su
  autorización global se cubre en API, no como pantalla física de este APK.
- El cambio A→B mientras el dispositivo continúa offline no es posible con el
  modelo actual de una sola sesión segura: iniciar otra identidad requiere
  autenticación. El aislamiento de colas offline sí está cubierto
  automáticamente; cada operación queda disponible solo para su propietario.
  Certificar cambio físico multiusuario completamente offline requeriría una
  funcionalidad nueva de perfiles autenticados almacenados, fuera de este
  defecto.
- El permiso por cuadrilla no se infiere. Por seguridad, el flujo de campo usa
  propiedad estricta hasta que exista una concesión explícita persistida en el
  modelo de autorización.

El defecto de exposición cruzada reproducido queda corregido para el alcance de
campo. La certificación física A/B está aprobada; los dos límites anteriores no
amplían acceso y se mantienen documentados como decisiones conservadoras.
