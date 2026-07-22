# Etapa 2: arquitectura local y contratos futuros

Los documentos de REPORTE VISUAL se almacenan como JSON versionado en Hive. Las fechas se
escriben en UTC ISO-8601 y los enums usan nombres estables, nunca ordinales. El
índice `hydrantId:f02A` impide dos borradores activos del mismo tipo.

Las cajas heredadas `trace_events`, `sync_queue`, `media_sync_queue` y
`synced_trace_ids` no se limpian ni migran destructivamente. Las nuevas cajas
son `visual_inspections_v1`, `active_inspection_index_v1`,
`damage_records_v1`, `inspection_photos_v1`, `hydrant_configurations_v1`,
`local_hydrants_v1` y `media_work_queue_v1`. Una migración futura deberá leer
el documento anterior, escribir y releer el nuevo, y conservar el anterior
hasta validar la escritura.

## Asignaciones incrementales

El contrato remoto futuro recibe `userId`, `brigadeId`, `deviceId`, cursor
anterior y versión local de catálogos. Devuelve `nextCursor`, `hasMore`, altas,
actualizaciones, retiros, hidrantes modificados y versión de catálogos. No se
usará polling frecuente; las consultas automáticas tendrán intervalo mínimo.

## Navegación de inspección

Solo **Guardar y continuar** avanza. Atrás guarda el borrador y retrocede; en
el primer paso vuelve a la ficha. El swipe izquierdo no avanza y el swipe
derecho puede invocar el mismo retroceso protegido.

## Catálogos

Los catálogos demo están centralizados y versionados. Deben reemplazarse por
catálogos oficiales conservando las claves históricas ya persistidas.

## Evidencia

`flutter_image_compress` está encapsulado tras `ImageProcessingService`; no se
invoca desde pantallas. El warning conocido de Built-in Kotlin debe reevaluarse
antes de release. El perfil `f02a-jpeg-v1` usa JPEG, calidad 85, miniatura de
400 px y mínimo 640 × 480. El rango de tamaño es objetivo, no garantía; tampoco
se afirma conversión sRGB si el motor no la confirma. Solo `verified` equivale
a sincronizado. Las fotos reales quedan en `pendingUpload`.
