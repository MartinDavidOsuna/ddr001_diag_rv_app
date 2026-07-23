# Adaptación funcional RV

Fecha: 2026-07-22. Rama: `feature/rv-catalog-and-checklist`. Versión conservada: `0.2.1+4`.

## Datos y offline

El repositorio de hidrantes cachea el mismo DTO con claves separadas `all:<id>` y `mine:<id>`. `scope=all` alimenta catálogo, mapa y nueva revisión; `scope=mine` alimenta Inicio e Hidrantes. Al reconstruir la lista personal se fusionan borradores locales cuyo hidrante esté en catálogo, sin eliminar trabajo pendiente. La creación usa `RvDraftRepository.openOrCreate`, por lo que doble toque o reapertura devuelve el borrador activo y conserva el snapshot exacto del checklist.

## Pantallas

- Inicio muestra inspector/cuadrilla, conectividad, CTA **Nueva revisión visual**, métricas personales, revisiones recientes y accesos a Mis hidrantes, Mapa general y Sincronización.
- Hidrantes usa exclusivamente la lista personal. La barra pública ya no contiene filtros RF.
- Nueva revisión busca cuenta exacta/parcial, localidad o municipio dentro del catálogo general, confirma el hidrante y crea/continúa el borrador local.
- Mapa usa solo catálogo general con WGS84 válido, cuenta filas sin coordenadas y muestra azul `pending` / verde `completed`. No interpreta `source_x/source_y` como lat/lng.
- El renderer sigue siendo completamente dinámico. Presenta una sección v2 por paso con progreso, Anterior/Siguiente; el resumen existente constituye el paso 10. Dependencias y respuestas se conservan en el snapshot.

## Contrato y estados

Flutter envía explícitamente `scope=all` y `scope=mine`. Mapea resumen de inspección, `rvStatus`, sección, ángulo, elevación y salidas. `submitted|validated` se presenta terminado; draft/in_progress/pending_sync se presenta en proceso; el resto pendiente. `hasLocalPendingData` se completa por la fusión local.

## Pruebas y pendientes

Se actualizaron pruebas de filtros RV y cachés separados. Pendientes de validación física: mapa con datos WGS84 reales, selección desde marcador directa, recorrido completo de los diez pasos y siete fotos. La hoja ATRIBUTOS no aporta CRS, por lo que sus filas no aparecerán en mapa hasta una transformación verificada.
