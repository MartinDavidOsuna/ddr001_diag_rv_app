# Validación UX de RV — pasos 1 y 2

## Corrección 12.5.1-A de telefonía

La captura ya no confunde transporte con red celular. `connectivity_plus`
permanece para Wi-Fi/móvil, mientras un canal Kotlin consulta la suscripción de
datos, operador, `TelephonyDisplayInfo`, servicio y señal durante una ventana
asíncrona breve. El modelo conserva valores nativos y motivos específicos.

La prueba física obtuvo TELCEL/LTE/75% con datos móviles y, con Wi-Fi, mostró
simultáneamente conexión Wi-Fi y red móvil TELCEL 5G NSA/75%. La denegación de
telefonía no bloqueó GPS. Véase `docs/android-telephony-diagnostics.md`.

## Antes y después

Antes, la evidencia se dibujaba fuera del paso activo, la navegación aparecía
inmediatamente bajo el indicador y el paso 2 usaba una sección colapsable. Cada
slot guardaba una sola referencia y una captura reemplazaba la anterior.

Ahora cada cambio sustituye el `KeyedSubtree` del paso. El orden es encabezado,
avance, contenido, mensajes, espacio y navegación. El paso 1 contiene ubicación
y conectividad; el paso 2 contiene preguntas fijas y fotografías. Los pasos
3–10 no recibieron el patrón nuevo.

## Estructura de datos

`photos` es `Map<String, List<RvPhotoReference>>`. El lector acepta también el
objeto único anterior y lo envuelve en una lista, sin reescribir ni perder
evidencia. El orden de captura es el orden de la lista. La foto completa y la
miniatura permanecen en almacenamiento administrado por la app.

La migración `03_rv_multiple_photos_per_slot.sql` sustituye el índice único por
un índice de consulta `(inspection_id, slot_code, captured_at, photo_id)`. La
API usa `photo_id` como identidad idempotente y `DELETE` marca
`upload_status=deleted`/`deleted_at`; no borra archivos remotos de forma
silenciosa.

## Evidencia automatizada

- Orden de navegación para pasos 1 y 2.
- Sustitución exclusiva del contenido y regreso.
- Panel fijo sin `ExpansionTile`.
- Coordenadas válidas, vacías, no numéricas y fuera de rango.
- GPS/manual y precisión ausente.
- Wi-Fi/LTE/5G/sin servicio/desconocida.
- Nivel 0–100, clasificación textual e indicador semántico.
- Singular/plural, varias fotos y formato heredado.
- Pantalla estrecha y botones Sí/No con targets de 48 px.
- Integración: dos fotos por slot, reintento del mismo UUID, listado, borrado
  repetido, conservación de las demás y bloqueo tras envío.

## Evidencia física

En Pixel 7 Pro con APK debug +7 se observó captura combinada, GPS detallado,
limitaciones de señal presentadas honestamente, validación manual, exclusividad
de pasos, panel fijo, rubros fotográficos, controles cámara/galería, navegación
al final y retorno con datos.

No se obtuvieron fotos nuevas: no existía escena/colección segura verificable.
La parte física de contador creciente, visor y borrado queda pendiente.

## Patrón recomendado para 12.5.2

Después de aprobar este piloto, reutilizar `RvStepLayout` y el reemplazo keyed
para pasos 3–10. Mantener cada cuerpo autónomo, persistir estado fuera del árbol
visual, evitar paneles colapsables cuando oculten obligatorios y conservar la
navegación al final. No trasladar automáticamente los controles específicos de
ubicación o fotografía.
# Integración 12.5.2

El paso 2 comparte ahora la misma fuente persistente de paso activo que el resto
del checklist. Cámara y galería no pueden reiniciar el índice por reconstrucción.
La navegación quita foco y restaura el encabezado después del frame.
