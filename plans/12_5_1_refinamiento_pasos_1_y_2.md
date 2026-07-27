# Etapa 12.5.1 — Refinamiento de pasos 1 y 2

## Diagnóstico inicial

La pantalla RV se compone de `RvInspectionPage`, un
`DynamicChecklistRenderer` con estado local del paso, y un bloque `_Evidence`
renderizado siempre después del checklist. Ese bloque permanente explica que la
ubicación/conectividad y las fotografías parezcan contenido residual al cambiar
de paso. El renderer coloca la navegación inmediatamente después de una
`ExpansionTile`; las secciones sin preguntas contestables quedan vacías.

`RvDraft` persiste respuestas, ubicación, señal y una referencia fotográfica por
slot en Hive. `RvInspectionController` captura ubicación y señal por separado y
adquiere imágenes mediante `ReliablePhotoService`, que copia, normaliza,
comprime, crea miniatura y registra el archivo en almacenamiento administrado.
`InspectionSyncCoordinator` sincroniza las partes en orden e idempotentemente.

La API expone creación de inspección, respuestas, ubicación, señal y fotografías.
La tabla `rv.photos` usa `photo_id` como identidad idempotente, pero tiene un
índice único activo por `(inspection_id, slot_code)`, por lo que todavía no
admite varias fotografías activas por rubro. No existe borrado remoto público.

## Archivos involucrados

- `lib/features/inspections/presentation/rv_inspection_page.dart`
- `lib/features/checklist/presentation/dynamic_checklist_renderer.dart`
- `lib/features/inspections/presentation/rv_inspection_controller.dart`
- `lib/features/inspections/domain/rv_draft.dart`
- `lib/features/inspections/data/inspection_capture_services.dart`
- `lib/features/inspections/data/inspection_sync_coordinator.dart`
- `lib/core/media/reliable_photo_service.dart`
- `lib/domain/media/inspection_photo.dart`
- `src/modules/photos/photo.routes.ts`
- scripts SQL y pruebas de integración relacionadas con `rv.photos`

## Estrategia

1. Hacer que el renderer exponga un único cuerpo por paso y coloque la
   navegación al final del contenido.
2. Especializar solamente los pasos 1 y 2: evidencia combinada en el primero y
   panel fotográfico fijo en el segundo; conservar intactos los pasos 3–10.
3. Mantener compatibilidad de lectura con el mapa fotográfico heredado y
   evolucionar la representación a listas ordenadas por slot.
4. Usar `photo_id` para idempotencia, retirar de forma migrable la unicidad por
   slot y añadir borrado lógico autenticado para fotos no pertenecientes a
   inspecciones enviadas.
5. Cubrir primero el comportamiento con pruebas de dominio/widget/integración,
   después validar en el Pixel sin borrar almacenamiento.

## Riesgos

- Compatibilidad con borradores Hive cuyo campo `photos` contiene un objeto por
  slot.
- Restricción SQL existente y semántica de envío que exige al menos una foto
  verificada por slot.
- Fotografías remotas sin archivo local durante operación offline.
- Permisos y metadatos de señal limitados por Android.
- La captura física depende de disponer de una escena segura.

## Criterios de aceptación

Se aplican los criterios de la instrucción 12.5.1: navegación final, renderizado
exclusivo, captura combinada y manual, conectividad accesible, panel fijo,
múltiples fotos, galería, cámara/selector, borrado coherente, compatibilidad,
calidad Flutter/API y ausencia de operaciones sobre producción.

## Resultado final

Implementado el patrón exclusivo para pasos 1 y 2. El paso 1 presenta una sola
captura tolerante a resultados parciales, detalle GPS, conectividad honesta y
captura manual validada. El paso 2 es fijo, contiene preguntas y siete rubros
fotográficos, permite cámara/galería, listas ordenadas, galería local, ampliación
y borrado confirmado.

`RvDraft` escribe listas por slot y lee sin migración destructiva el objeto único
heredado. La API elimina la unicidad por slot mediante una migración restringida
a la base de pruebas, conserva idempotencia por `photo_id` y añade borrado
lógico. La integración confirmó dos fotos en un rubro, reintento, borrado
idempotente y bloqueo cuando la inspección ya fue enviada.

Flutter quedó con análisis limpio, 155/155 pruebas y APK debug +7. La API quedó
con lint, tipos, 62/62 unitarias, 9/9 integración, build y health aprobados.

En Pixel se comprobó paso 1, captura combinada real, presentación sin inventar
operador/señal, validación manual, paso 2 exclusivo, alineación Sí/No, scroll
hasta navegación y regreso con datos conservados. No se tomaron ni seleccionaron
fotos nuevas porque no existía una escena/colección segura verificable; esa parte
física permanece pendiente, aunque dominio, widgets y API están cubiertos.
