# Informe de hardening

## Extensión 12.5.1

Se eliminó el apilamiento visual causado por evidencia fuera del renderer y se
introdujo un cuerpo keyed exclusivo por paso. La navegación forma parte del
scroll y queda después del contenido. El paso 2 usa panel fijo.

La captura de ubicación/conectividad conserva cada resultado aunque el otro
falle. La ubicación manual valida límites y no inventa precisión. La señal se
normaliza solamente cuando Android entrega nivel 0–4; en caso contrario se
muestra `No disponible`.

La evidencia fotográfica evolucionó de una referencia a una lista por rubro,
con lectura compatible del formato anterior. La API admite varias filas por
slot, conserva identidad por UUID, ordena por captura y dispone de borrado lógico
autenticado e idempotente. Una inspección enviada permanece inmutable.

Riesgo remanente: falta repetir cámara/galería/galería por rubro y borrado en el
Pixel con material no sensible. No se forzó una captura insegura.

Fecha: 24 de julio de 2026.

## Incidencias y correcciones

1. Un hidrante local inexistente provocaba HTTP 500 al crear inspecciones.
   La API valida ahora su existencia y devuelve 404.
2. El middleware de idempotencia repetía respuestas 5xx almacenadas. Ahora
   descarta esos resultados y permite un reintento limpio.
3. La sincronización mostraba “Simulación local” aunque utilizaba la API real.
   Se reemplazó por mensajes de conexión y persistencia offline.

Las regresiones quedan cubiertas por una prueba de integración que recupera una
clave 500 histórica y por dos pruebas Flutter del mensaje de conexión.

## Pruebas ejecutadas

- Validación física de autenticación, catálogos, borradores, nueve secciones del
  checklist, GPS, cámara, persistencia, offline/reconexión, mapa y actualización.
- Cinco cierres/arranques, cinco transiciones foreground/background, rotación,
  navegación repetida y tres sincronizaciones consecutivas.
- Integridad local/remota de una evidencia JPEG segura; una única inspección y
  una única fotografía remotas, ambas abiertas/no enviadas.
- Flutter: formato, análisis, 125 pruebas y APK debug.
- API: lint, type-check, 62 pruebas unitarias, 9 de integración, build y health.

## Resultados de memoria y rendimiento

El PSS del proceso debug se mantuvo en un intervalo de aproximadamente 2,4 MB
entre ciclos (385–388 MB), sin crecimiento monotónico. La inspección del
controlador de diagnóstico confirmó cancelación de timer y recurso nativo en
`dispose`; el listener de pantalla se elimina al destruirse el controlador.

El arranque frío fue de 3,144 s y los siguientes de 2,038–2,944 s. En la red
local, catálogo y checklist respondieron en decenas de milisegundos; el guardado
masivo de respuestas tardó 635 ms y la fotografía 488 ms. No se detectó un
cuello de botella que justifique optimización en esta etapa.

## Riesgos y recomendaciones

- `flutter_image_compress_common` aún aplica KGP y Flutter avisa de una
  incompatibilidad futura. Actualizar el plugin cuando exista una versión
  compatible con Built-in Kotlin, en un cambio separado.
- La aplicación conserva el tamaño JPEG final, no el tamaño previo a compresión.
  Si esa métrica se vuelve requisito operativo, instrumentarla explícitamente.
- Completar presencialmente una recaptura con escena segura para validar el
  reemplazo extremo a extremo sin destruir la evidencia existente.
- Tratar los borradores cuyo catálogo ya no existe como recuperables: mostrar el
  404 y permitir reasignación/cancelación en una tarea de producto posterior.

No hubo importaciones, cambios en producción, commit, push ni Pull Request.
# Adición 12.5.2

- El paso activo se persiste en el documento local.
- Los retornos externos generan logs debug sin rutas ni imágenes.
- Catálogos usan UUID local, normalización, idempotencia y desactivación lógica.
- El envío requiere confirmación, bloquea doble pulsación y solo cambia a
  `submitted` tras confirmación remota.
- No se ejecutaron migraciones, importaciones ni operaciones productivas.

## Certificación 12.5.2-A

- La migración 04 rechaza explícitamente bases distintas de
  `RevisionVisualStarter_Test`.
- Dos ejecuciones preservaron conteos de evidencia y no duplicaron seeds.
- Respuestas aceptan y validan referencias opcionales de marca/diámetro.
- Suite E2E confirma reconciliación, `submitted_at`, unicidad y bloqueo.
- API ejecutada con Node 22; health live/ready aprobados.
# Actualización 12.5.2-B

Se eliminó la exposición cruzada de marcas genéricas, se validan tipos de
elemento tanto en cliente como en SQL/API y el paso 8 usa integridad
referencial para válvulas individuales. Node 22, health, suites y builds
quedaron aprobados. Persiste el pendiente de validación física interactiva por
bloqueo del dispositivo.
