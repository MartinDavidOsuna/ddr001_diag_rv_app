# Etapa 12.5.3 — Reporte de certificación automatizada

Fecha: 2026-07-27  
Rama: `feature/rv-crs-and-catalog-resolution`

## Entorno

- Flutter `3.44.5`, Dart `3.12.2`.
- Java de compilación disponible: Temurin `17.0.8`; Java global heredado: 8.
- Node usado en todas las tareas API: `22.22.1`; npm `11.17.0`.
- SQL Server `12.0.4237.0` SP1 Standard, servidor
  `WIN-5RQE8N8NQ9V`, base exclusiva `RevisionVisualStarter_Test`.
- Pixel 7 Pro (`cheetah_beta`), Android 17, conectado y autorizado.
- Android: `com.aquafim.ddr001diag`, `versionName 0.2.1`;
  actualización de `versionCode 11` a `12`.
- API health: proceso Node 22 PID `18800`, puerto `3000`.

## Matriz A–E resumida

| Grupo | Cobertura automatizada | Cobertura ADB | Pendiente manual | Resultado |
|---|---|---|---|---|
| A | Contratos, sincronización, 422, catálogos, válvulas, fotos, submit | — | — | APROBADO AUTOMATIZADO |
| B | Arranque sin crash | Instalación, apertura y background/foreground | Cámara, galería y UX | PARCIAL; MANUAL PENDIENTE |
| C | Persistencia/recuperación de repositorios | Ciclo Wi-Fi restaurado | Verificación visual offline | PARCIAL; MANUAL PENDIENTE |
| D | RFC Problem, clasificación, reintento e idempotencia | Cierre y reapertura | Interrupciones físicas | APROBADO AUTOMATIZADO/PARCIAL |
| E | Integración, fixtures y diagnósticos SQL | — | Revisión funcional | APROBADO AUTOMATIZADO |

## Evidencia y resultados

| ID | Grupo | Escenario | Tipo | Resultado esperado | Resultado obtenido | Evidencia | Estado | Riesgo |
|---|---|---|---|---|---|---|---|---|
| A1 | A | Flujo sintético completo | AUTOMATED | Catálogos → respuestas → válvulas → fotos → submit | Secuencia E2E completada; inspección enviada y solo lectura | `rv-flow.integration.test.ts` | APROBADO | Bajo |
| A2 | A | Marca local/reconciliación | AUTOMATED | ID remoto, tipo conservado, sin duplicado | Creación, normalización, consulta cruzada e idempotencia aprobadas | `dynamic-catalogs.integration.test.ts` | APROBADO | Bajo |
| A3 | A | Diámetros | AUTOMATED | Seeds, normalización y unicidad | Seeds 3/4; cero duplicados | Integración y diagnóstico SQL | APROBADO | Bajo |
| A4 | A | Paso 8 | AUTOMATED | 1, 2, 3, 3×4 y Otro válidos | Dominio/serialización cubiertos por suite Flutter y API | 216 Flutter, 82 API | APROBADO | Medio |
| A5 | A | Componentes por válvula | AUTOMATED | Tipo correcto y rechazo del incorrecto | Esquemas y servicios aprobados | Unitarias API/Flutter | APROBADO | Bajo |
| A6 | A | HTTP 422 | AUTOMATED | RFC Problem con path/request ID y sin retry | Contratos y política aprobados | Unitarias API/Flutter | APROBADO | Bajo |
| A7 | A | Idempotencia | AUTOMATED | Sin duplicados en reintentos | Catálogo, fotos y submit repetidos de forma controlada | Integración; SQL 0 duplicados | APROBADO | Bajo |
| B1 | B | Instalación incremental | ADB_ASSISTED | `adb install -r`, datos preservados | Instalación exitosa 11→12; Hive y evidencias presentes; sin desinstalar/clear | dumpsys/run-as/ADB | APROBADO | Bajo |
| B2 | B | Apertura y lifecycle básico | ADB_ASSISTED | Proceso abre y sobrevive a background | PID activo; sin `FATAL EXCEPTION` de la app | pidof/logcat sanitizado | APROBADO | Bajo |
| B3 | B | Capturas de pasos | MANUAL_REQUIRED | Evidencia visual de cada estado | No automatizado para evitar exposición de datos del borrador | Matriz manual | PENDIENTE | Medio |
| B4 | B | Cámara/galería | MANUAL_REQUIRED | Conservación de paso y slot | No se abrió cámara sin confirmar escena segura | Matriz manual | PENDIENTE | Alto |
| C1 | C | Repositorio offline | AUTOMATED | Persistencia, orden, reconciliación | Suite Flutter completa aprobada | 216/216 | APROBADO | Bajo |
| C2 | C | Ciclo Wi-Fi | ADB_ASSISTED | Detectar corte y restaurar estado | Wi-Fi enabled→disabled→enabled; proceso permaneció activo | ADB `svc wifi`/pidof | APROBADO TÉCNICO | Medio |
| C3 | C | UX offline tras reapertura | MANUAL_REQUIRED | Datos visibles después de cierre | Requiere interacción humana con borrador | Matriz manual | PENDIENTE | Alto |
| D1-D10 | D | Errores/interrupciones | AUTOMATED | Clasificación, borrador e idempotencia | 401/403/409/422/429/5xx/red cubiertos a nivel servicio; corrupción e interrupción física quedan manuales | Unitarias e integración | PARCIAL APROBADO | Medio |
| E1-E8 | E | Consistencia servidor | AUTOMATED | Sin huérfanos/duplicados; auditoría y solo lectura | 10/10 diagnósticos con cero incidencias; submit bloquea mutación | SQL e integración | APROBADO | Bajo |

### Suites finales

- `dart format lib test`: 165 archivos inspeccionados; 5 formateados.
- `flutter analyze`: sin incidencias.
- `flutter test`: 216 aprobadas, 0 fallidas, 0 omitidas inesperadas.
- `flutter build apk --debug`: aprobado; APK no versionado.
- `npm run lint`: aprobado con Node 22.
- `npm run type-check`: aprobado.
- `npm test`: 82 aprobadas en 9 archivos.
- `npm run test:integration`: 10 aprobadas en 4 archivos, sin omisión SQL.
- `npm run build`: aprobado.
- `/api/v1/health/live`: HTTP 200, `{"status":"ok"}`.
- `/api/v1/health/ready`: HTTP 200; database, storage y configuration `ok`.

### SQL

Las migraciones 04, 05 y 06 se certificaron con segunda ejecución segura. Para
SQL Server 2014 se movió la creación nullable de `normalized_name` a la
migración 05, evitando la compilación anticipada de la 06. La migración de
mayúsculas quedó idempotente: cero nombres no canónicos y cero marcas sin tipo.

Los 10 diagnósticos finales devolvieron cero para: respuestas duplicadas,
índices de válvula duplicados, marcas tipificadas duplicadas, diámetros
duplicados, marcas sin tipo/no canónicas y huérfanos de respuestas, válvulas o
fotos. Permanecen únicamente los seeds `3 in` y `4 in`.

### Error 422

La regresión queda cubierta en ambos clientes del contrato. Los objetos de
válvulas se envían por `/parcel-valves`, no por `/answers`; las referencias
locales no reconciliadas bloquean antes de la petición; `422` se interpreta como
determinista, conserva el borrador y no activa reintento automático. La
integración completa terminó sin 422 inesperado.

## Fixtures

Las nuevas fixtures usaron `TEST-12-5-3`. Un marcador heredado excedía una
columna SQL y se acortó conservando el prefijo. La suite limpió sus IDs, aliases,
fotos y archivos; el diagnóstico final confirmó que no quedaron catálogos de
prueba sin tipo.

## Riesgos

No se declara certificación física total. Cámara, galería, legibilidad,
teclado, percepción del scroll, corte durante captura, batería/permisos y
confirmación del inspector requieren la matriz manual.

El conteo bruto de archivos privados cambió de 357 a 349 durante la actualización
porque el runtime depuró archivos temporales/cache; la evidencia durable
relevante (boxes Hive, almacenamiento seguro y fotografías) permaneció. No se
realizó una comparación semántica del contenido para evitar exponer datos.

## Recomendación para piloto

El backend, SQL y la lógica automatizable están listos para pasar a la matriz
manual supervisada. No autorizar piloto hasta completar especialmente cámara,
galería, paso 8, navegación desde resumen, offline visible y firma del
inspector.
