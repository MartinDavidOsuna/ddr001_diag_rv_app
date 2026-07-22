# Sincronización incremental de asignaciones

La implementación demo solo se ejecuta bajo acción explícita y evita solicitudes concurrentes. No consulta automáticamente al abrir Hidrantes ni usa polling. Una futura consulta automática respetará un intervalo mínimo de 15 minutos.

Solicitud futura: `userId`, `brigadeId`, `deviceId`, cursor anterior y versión local de catálogos.

Respuesta futura: `nextCursor`, `hasMore`, asignaciones nuevas, actualizadas y retiradas, hidrantes modificados y versión de catálogos.

Las altas y modificaciones se aplican mediante upsert por ID. Un retiro nunca borra trabajo local, fotografías, trazabilidad ni hidrantes creados en campo; si existe actividad local, se conserva y se marca para revisión.
