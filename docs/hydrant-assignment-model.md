# Modelo de asignación de hidrantes

- `all`: catálogo general activo autorizado.
- `mine`: asignaciones activas directas al usuario o a su brigada, más altas
  manuales propias. El cliente agrega trabajo local pendiente para conservarlo
  visible offline.
- `recent`: proyección local de elementos consultados o trabajados recientemente
  cuando se habilite el historial.
- `pending`: asignaciones `assigned` o `in_progress`.

La tabla `rv.hydrant_assignments` permite propietario usuario o brigada, estado,
fecha de asignación, vencimiento y actualización. Las inspecciones previas ya no
son sustituto de asignación. Un usuario sin filas recibe una lista válida vacía.

La migración es aditiva y no crea asignaciones por inferencia. La carga inicial
de asignaciones corresponde al proceso administrativo autorizado.
