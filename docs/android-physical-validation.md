# Evidencia de validación física Android

## Actualización 12.5.1-A — telefonía real

Se instaló el APK debug +8 mediante `adb install -r`, sin `pm clear` ni
desinstalación. El Pixel conservó sesión y borradores.

- Datos móviles: TELCEL, LTE, nivel 3/4, 75%, -106 dBm.
- Wi-Fi activo: transporte Wi-Fi y red móvil TELCEL 5G NSA, 3/4, -106 dBm.
- Recaptura: TELCEL LTE, nivel 4/4 y -94 dBm.
- Permiso denegado: GPS conservado y explicación específica visible.
- Permiso restaurado: lectura real recuperada.
- Persistencia: valores técnicos serializados en el borrador.
- Callbacks: cada captura registró desregistro y `callbackReleased=true`.

Las coordenadas y los identificadores de SIM no se incorporaron a evidencias.
`cmd phone list-sims` no existe en Android 17; se usaron las APIs de suscripción
y dumpsys filtrado. No se envió la inspección.

## Actualización etapa 12.5.1 — 24 de julio de 2026

Se instaló `0.2.1+7` mediante `adb install -r`, sin desinstalar ni ejecutar
`pm clear`. La sesión y los borradores anteriores permanecieron disponibles.

En un borrador de prueba se verificó:

- paso 1 con un único botón y estado `Capturando…`/actualización;
- captura GPS con altura, precisión, fecha y origen automático;
- conectividad capturada parcialmente: Android no expuso operador, tecnología
  celular ni nivel comparable, y la UI mostró `Desconocido`/`No disponible`;
- formulario manual, validación visible ante longitud vacía y conservación de la
  ubicación automática al no guardar valores inválidos;
- botones después del contenido y `Anterior` deshabilitado en el primer paso;
- paso 2 sin contenido del paso 1, sin expansión y con Sí/No alineados;
- siete rubros, contador plural, cámara y selector de galería;
- navegación al final del panel y regreso al paso 1 con datos conservados.

El teléfono estaba usando 4G sin acceso a la IP privada de la LAN, por lo que no
se repitió sincronización física. La integración SQL sí validó el flujo nuevo.
No se capturaron ni eligieron fotos porque no había una escena ni colección
segura verificable. No se enviaron inspecciones.

## Alcance

Validación realizada el 23–24 de julio de 2026 en Pixel 7 Pro
(`2730…04R7`), Android 17/API 37, contra
`RevisionVisualStarter_Test` mediante la API local
el endpoint inyectado mediante `API_BASE_URL`. No se incluyeron secretos, coordenadas exactas ni
fotografías.

## Matriz ejecutada

| Área | Resultado |
|---|---|
| Instalación, arranque y actualización | Aprobado; `adb install -r` conservó sesión y datos hasta `0.2.1+6`. |
| Login | Aprobado para credenciales válidas, rechazo inválido, logout y persistencia. |
| Catálogos y búsqueda | Aprobado para general/personal, exacta, parcial y sin resultados. |
| Borradores | Aprobado; estado local y remoto conservado, sin doble creación. |
| Checklist RV v2 | Nueve secciones recorridas; SQL confirma 77 elementos (63 contestables, 14 evidencia/solo lectura); resumen accesible. |
| GPS | Permiso denegado/concedido, reintento, servicio apagado/restaurado, persistencia y sync aprobados. |
| Fotografía | Permiso, apertura/cancelación, archivo, miniatura, integridad, persistencia y sync aprobados sobre evidencia segura existente. |
| Offline/reconexión | Guardado y reapertura aprobados; cola finalmente en cero. |
| Mapa/preselección | Sin marcadores falsos; preselección y mensaje requeridos aprobados. |
| Resiliencia | Cinco reaperturas, cinco foreground/background, rotación, navegación y sync repetidas sin crash ni duplicados. |

## Evidencia fotográfica no sensible

La foto de prueba asociada a `front_closed` mide 174 135 bytes, es JPEG
1080 × 1434 y tiene una miniatura de 11 670 bytes. El hash del archivo local
coincide con el `client_sha256` verificado por la API. El servidor registró una
sola fotografía `verified`. El tamaño anterior a la compresión no se persiste,
por lo que no se presenta como medido. No se efectuó una sustitución destructiva
de la evidencia sincronizada sin un operador que garantizara un nuevo encuadre
seguro.

## HTTP 500 y corrección

`TEST-RVS-001` es un borrador local heredado cuyo hidrante no existe en la base.
La creación remota producía 500 y ese resultado quedaba cacheado por
idempotencia. Se agregó validación explícita del hidrante (404) y descarte de
resultados idempotentes 5xx. Una prueba de integración reproduce el 500
histórico y confirma que el reintento llega a 404. La prueba física confirmó el
404 y ninguna fila remota para ese borrador.

## Datos remotos

La inspección física sincronizada de la cuenta 351 permanece `in_progress`,
RV v2, con 51 respuestas, una ubicación, una señal, una foto verificada y
`submitted_at` nulo. No hay duplicado por `client_inspection_id`. Los
identificadores, usuario y coordenadas se mantienen enmascarados.

## Calidad y límites

Flutter: formato correcto, análisis limpio, 125/125 pruebas y APK debug
compilado. API: lint, tipos, 62/62 unitarias, 9/9 integración, build y ambos
health checks aprobados. La advertencia futura de Kotlin del plugin de compresión
no bloquea.

La recaptura completa con una nueva escena no sensible y la métrica del tamaño
precompresión requieren una sesión presencial controlada. No se envió ninguna
inspección, no se tocó producción ni se ejecutaron importaciones.
# Etapa 12.5.2

La compilación APK debug se valida de forma automatizada. La ejecución física
debe conservar datos (`adb install -r`, nunca `pm clear`) y cubrir cámara,
cancelación, galería, visor, borrado, pasos 1–10, marcas, diámetros y resumen.
No se autoriza confirmar el envío de una inspección real. Si no hay dispositivo
o escena segura, la prueba queda pendiente y no se sustituye por una simulación.

## Resultado 12.5.2-A

- Pixel 7 Pro conectado.
- APK `0.2.1+9` instalado correctamente con `adb install -r`.
- `firstInstallTime` preservado; no hubo uninstall, `pm clear` ni downgrade.
- Hive de inspecciones, índice activo, almacenamiento seguro y evidencias
  permanecen presentes tras la actualización.
- El dispositivo estaba bloqueado con credencial/biometría. No fue posible abrir
  la UI para cámara, galería, scroll, foco, catálogos y resumen.
- Sin escena segura confirmada; no se tomó fotografía ni se envió inspección.
# Resultado 12.5.2-B (2026-07-25)

`adb install -r` instaló `0.2.1+10` (`versionCode=10`) en el Pixel 7 Pro sin
desinstalar ni limpiar datos. El proceso inició y permanecieron 157 archivos
privados. La pantalla estaba bloqueada con `NotificationShade` enfocada, por
lo que cámara, galería, paso 8, offline y resumen no pudieron operarse de
forma verificable. No se tomó ninguna foto ni se envió inspección física.
