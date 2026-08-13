# Plan de diagnóstico productivo — incidente de sincronización RV

Fecha de inicio: 2026-08-12

## Restricciones

- No desplegar ni modificar producción.
- Toda consulta a SQL Server será de solo lectura.
- No borrar inspecciones, drafts, fotografías, Hive, caché, sesiones ni evidencia.
- No limpiar ni desinstalar la app del dispositivo Android.
- No cambiar a `main` ni descartar cambios locales.
- No implementar correcciones funcionales antes de completar el prediagnóstico formal.

## Línea base

- Repositorio app: `C:\DEV\AQAGS\ddr001_diag_rv_app`
- Rama verificada: `fix/rv-main-reconciliation-and-map-sync`
- HEAD inicial: `0dad2b14150f1f97e64daf35059a95fabc60c783`
- Estado inicial: limpio antes de crear este documento.
- Repositorio API localizado en: `C:\DEV\AQAGS\ddr001_api_rv`
- Rama API verificada: `fix/rv-main-reconciliation-and-map-sync`
- HEAD API inicial: `9c3f02689614c09423d7bd4732114eaeae5ed025`
- Cambios API preexistentes a preservar: `database/migrations/20260809_expand_parcel_valves_to_five.sql` y `tests/unit/parcel-valves-five-migration.test.ts` sin seguimiento.
- Dispositivo conectado: Pixel 7 Pro, serial `27301FDH3004R7`.

## Fases

1. Inventariar el pipeline Flutter desde `Sincronizar y enviar`, sus pasos, excepciones, persistencia local, reintentos e idempotencia.
2. Inspeccionar Hive y logs del Pixel mediante métodos no destructivos; registrar versión/build y drafts de las cuentas afectadas si los permisos del dispositivo lo permiten.
3. Auditar API, esquema SQL, endpoints administrativos, idempotencia de create/submit, claims, sesiones, historial, auditoría y cálculo del dashboard.
4. Construir y ejecutar herramientas READ ONLY para las 73 inspecciones y los 11 hidrantes; SQL Server será la fuente definitiva ante discrepancias.
5. Calcular distribución de antigüedad y clasificar cada inspección sin inventar un umbral stale previo a observar los datos.
6. Comparar casos exitosos 1142, 1161 y 937 nuevo con los casos parciales, locales y duplicados; identificar el último paso persistido de cada uno.
7. Reproducir fallos por etapa y demostrar por qué excepciones no API terminan como `Error desconocido`.
8. Entregar prediagnóstico formal: tablas de 11 y 73 casos, diagrama del pipeline, causas demostradas y número real de activas.
9. Después del prediagnóstico, definir cambios mínimos, archivos, riesgos, rollback y compatibilidad con datos ya existentes.
10. Implementar recuperación/reconciliación, observabilidad persistente, semántica de actividad y eliminación de prioridad en la experiencia.
11. Validar con análisis, pruebas Flutter/API, escenarios de respuesta perdida, reinicio, Android y evidencia de no pérdida.

## Artefactos previstos

- Informe productivo y anexos sanitizados en `plans/`.
- Scripts administrativos READ ONLY en la API.
- Fixtures y pruebas automatizadas sin datos sensibles.
- Matriz de recuperación de drafts existentes.
- Política propuesta para stale/superseded que preserve auditoría y no haga cambios destructivos automáticos.

