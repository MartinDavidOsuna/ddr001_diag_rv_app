# Etapa 12.5.4 — datos reales y estadísticas de Perfil

## Inventario y diagnóstico

| Archivo/área | Tipo | Comportamiento encontrado | Decisión | Riesgo |
|---|---|---|---|---|
| `profile_pages.dart` | runtime productivo | Conteos fijos 5/5/2, conexión simulable, credenciales y manual de demostración, actualización simulada | Reemplazar por datos scoped, retirar controles y reescribir manual | Crítico: exposición cruzada y estado falso |
| `app_state.dart/synchronize` | runtime productivo | Retardos y marcado artificial de colas, fotos y trazas | Sincronizar solo mediante coordinador remoto; no confirmar otros elementos | Crítico: éxito falso |
| `update_service.dart` | runtime desacoplado | Escenarios y URL de demostración | Eliminar escenarios; desactivar toda la función con `appUpdatesEnabled=false` | Bajo mientras la bandera siga cerrada |
| `mock_assignment_sync_service.dart` | recurso de desarrollo en `lib/` | Generaba hidrantes/asignaciones en memoria | Eliminar de código productivo | Ninguno: no tenía consumidores |
| `data/mock/demo_data.dart` | recurso de desarrollo en `lib/` | Usuario e hidrantes precargados | Eliminar de código productivo | Ninguno: no tenía consumidores |
| repositorios Hive | runtime productivo | Algunas métricas recorrían cajas globales | Filtrar por `LocalDataScope`, propietario y ambiente | Crítico |
| RF, telemetría y tolerancias | código legado no alcanzable en build RV (`rvOnly=true`) | Terminología de prototipo | Conservar por compatibilidad histórica; no se expone en el flujo RV | Requiere etapa independiente antes de habilitar RF |
| pruebas bajo `test/` | fixtures automatizadas | Datos sintéticos controlados | Conservar | Sin exposición runtime |
| imports/diagnósticos API | herramientas explícitas | Muestras y fixtures de certificación | Conservar; no se ejecutan automáticamente | Sin exposición runtime |

## Fuentes reales

- Hidrantes: API autenticada y caché Hive namespaced del usuario.
- Inspecciones: API autenticada y documentos locales creados por el usuario.
- Perfil: `GET /profile/today-stats` para enviados/pendientes y cola/drafts
  locales scoped para elementos sin sincronizar.
- Conectividad: resultado efectivo de las llamadas a API/restauración de sesión;
  no existen interruptores visuales.
- Sincronización: confirmaciones del coordinador RV y estados persistidos; no se
  marcan colas, fotos o trazas mediante temporizadores.
- Versión: `PackageInfo` de la aplicación instalada.

## Definiciones

- **Enviados:** inspecciones `submitted` o `validated` cuyo `submitted_at`
  corresponde al día operativo de `America/Hermosillo`.
- **Pendientes:** inspecciones no enviadas/validadas iniciadas durante el día
  operativo actual.
- **Sin sincronizar:** identificadores únicos de borradores u operaciones
  pendientes accesibles para `environment/account/user`. No incluye colas
  ajenas ni duplica una inspección por varias operaciones.

## Estrategia y archivos afectados

1. Desactivar actualizaciones centralmente y retirar ruta/UI.
2. Reemplazar Perfil y manual.
3. Añadir endpoint autenticado de estadísticas.
4. Incorporar filtros parametrizados `Enviados hoy`, `Pendientes hoy` y
   `Sin sincronizar` a la lista existente.
5. Filtrar fotos, trazas y colas por sesión.
6. Mantener estados vacíos y errores reales.
7. Certificar Flutter, API y SQL únicamente contra la base autorizada.

## Riesgos

- SQL Server 2014 no ofrece `AT TIME ZONE`; Hermosillo usa UTC-07 sin horario de
  verano, por lo que la consulta usa el desplazamiento fijo documentado.
- La funcionalidad RF permanece deshabilitada. Sus prototipos no deben
  habilitarse sin una etapa específica de eliminación de tolerancias simuladas.
- Los registros TEST persistidos se diagnostican, no se eliminan.

## Resultado

- Se eliminaron los dos proveedores mock alojados en `lib/`.
- Perfil ya no contiene conteos fijos, credenciales de ejemplo, controles de
  simulación ni acceso a actualizaciones.
- `appUpdatesEnabled=false` evita consulta, banner, ruta, descarga y bloqueo de
  actualización. La versión instalada sigue visible.
- La sincronización RV solo avanza por respuestas reales del coordinador; ya no
  marca colas, fotos o trazas mediante temporizadores.
- Las fotos, trazas, colas y estadísticas locales se filtran por usuario.
- El endpoint `/profile/today-stats` calcula enviados/pendientes exclusivamente
  con `user_id` tomado del token y fecha de Hermosillo.
- Los tres filtros de Perfil abren la lista parametrizada, muestran chip,
  conteo y estado vacío, y pueden retirarse.
- El manual fue reemplazado por doce secciones operativas.
- El diagnóstico SQL reportó cero inspecciones sin propietario, propietarios
  inexistentes, duplicados por cliente/usuario e hidrantes sin cuenta. No
  encontró usuarios/hidrantes demo o mock. Conservó una fixture `TEST-*`.
- Flutter: formato y análisis aprobados; 223/223 pruebas aprobadas; APK debug
  generado.
- API Node 22: lint, type-check, 82/82 unitarias, 10/10 integraciones y build
  aprobados. Health live/ready HTTP 200.
- Pixel 7 Pro actualizado con `adb install -r` a `0.2.1+14`
  (`versionCode 14`) sin desinstalar ni limpiar datos.

## Corrección adicional — cambio seguro de usuario

1. **Regla eliminada.** Se retiró de `api_exception.dart` la traducción especial
   de `open-session-conflict` que indicaba usar el correo anterior o solicitar
   un cierre. La interfaz no contiene botones ni comparaciones de correo para
   vincular el dispositivo.
2. **Motivo original.** El cliente convertía un `409` de sesión abierta emitido
   por la API en una restricción de propiedad del dispositivo. Esto confundía
   la sesión remota con la conservación de datos offline.
3. **Comportamiento nuevo.** El inicio se envía sin el token anterior y la
   sesión activa se reemplaza únicamente después de recibir y validar una
   respuesta exitosa. Un intento inválido conserva sin cambios la sesión
   vigente en Secure Storage.
4. **Tokens.** Una autenticación válida sobrescribe access/refresh/session con
   una única identidad. El cierre local elimina esos valores incluso cuando el
   endpoint remoto no responde; `installation_id` permanece solo como dato de
   dispositivo para diagnóstico/auditoría.
5. **Datos offline.** El reinicio de sesión limpia listas, estadísticas,
   checklist, filtros y estados en memoria, pero no elimina cajas Hive. Los
   documentos y colas continúan filtrados por `LocalDataScope`
   (`environment/account/user`) y reaparecen solo para su propietario.
6. **Cambio de usuario.** Tras autenticar B se retira el alcance de A, se
   reinicia el estado visible, se aplica el alcance de B y se consultan sus
   asignaciones/checklist. No coexisten dos sesiones visibles.
7. **Estadísticas.** Los conteos remotos se invalidan inmediatamente y quedan
   en carga hasta obtener los de B; los conteos locales recorren repositorios
   scoped, sin reutilizar estadísticas de A.
8. **Pruebas A → B → A.** Las pruebas automatizadas cubren preservación de la
   sesión A ante un intento inválido, reemplazo exclusivo de tokens al aceptar
   B, ausencia del mensaje bloqueante, y conservación/ocultamiento de
   borradores y colas al alternar alcances.
9. **Validación física.** Pendiente repetir en Pixel con dos usuarios reales y
   el backend actualizado; debe hacerse con
   `adb install -r`, sin `pm clear` ni desinstalación.
10. **API y riesgos pendientes.** En `ddr001_api_rv`, el endpoint
    `/field-sessions/start` dejó de rechazar un correo distinto por
    `installationId`: dentro de una transacción cierra la sesión anterior,
    revoca sus refresh tokens y crea la nueva, conservando el dispositivo para
    auditoría. La prueba SQL A → B confirmó HTTP 201 para ambos usuarios, una
    sola sesión abierta y HTTP 401 para el token anterior. Falta desplegar esta
    versión en el ambiente usado por el Pixel y completar la validación física.

### Validación física

La instalación y preservación de datos fueron verificadas. La inspección visual
final de Perfil quedó bloqueada porque el Pixel permaneció durante la sesión en
una llamada activa y Android dejó la actividad Flutter en negro aunque el
proceso siguió vivo; adicionalmente, la API conservaba una sesión abierta del
usuario anterior y rechazó la identidad sintética nueva. No se cerró ni alteró
esa sesión desde SQL y no se borraron datos para sortear el bloqueo.

### Referencias restantes

La búsqueda final encuentra terminología `demo/simulated` únicamente en el
módulo histórico F02-B/funcional y sus reglas de tolerancia. Ese módulo está
fuera del runtime navegable mediante `AppConfig.rvOnly=true`; no aparece ni
puede iniciarse en esta aplicación RV. Se conserva para compatibilidad de
modelos históricos y requiere una etapa propia antes de habilitar F02-B.
`RtkStatus.simulated*` también se conserva como valor de deserialización
histórica, no como proveedor activo.
