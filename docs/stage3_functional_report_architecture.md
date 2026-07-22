# Etapa 3: REPORTE FUNCIONAL

## Arquitectura y operación offline

REPORTE FUNCIONAL (RF) es un agregado independiente de REPORTE VISUAL (RV), relacionado por `hydrantId`. Puede reutilizar identificación, ubicación, configuración, componentes, daños y evidencia como referencias, pero nunca sobrescribe el documento visual. Las diferencias se guardan mediante procedencia de campo y pueden exigir revisión.

El flujo tiene diez pasos: identificación/preparación; instrumentos/montaje; presión/caudal; válvulas/reductora; solenoides/actuación; energía; comunicaciones/telemetría; alarmas/estanqueidad/fugas; evidencias/revisión; resultado/cierre. El índice interno `hydrantId:f02B` impide dos RF activos. Las pruebas paralelas permanecen bloqueadas.

Los controladores y repositorios funcionales contienen el estado del flujo; `AppState` conserva sesión, conectividad y coordinación global. `TelemetryService`, `ModbusService` y `RemoteActuationService` son contratos futuros y no realizan conexiones en esta etapa.

## Persistencia y migración

Cajas nuevas:

- `functional_eligibility_v1`
- `functional_inspections_v1`
- `active_functional_inspection_index_v1`
- `measurement_series_v1`
- `instrument_records_v1`
- `functional_valve_tests_v1`
- `alarm_tests_v1`
- `functional_results_v1`
- `functional_test_records_v1`

Se conservan todas las cajas previas. Los documentos usan JSON versionado, UTC ISO-8601, UUID, `schemaVersion` y enums por nombre. La estrategia es read-old/write-new: un campo ausente recibe un valor seguro, los textos heredados se conservan y un cambio de esquema guarda la versión anterior antes de confirmar la escritura nueva. No se permiten `clear`, `deleteFromDisk` ni migraciones destructivas.

## Unidades y cálculos

Unidades base: kPa, L/s, L, s, V, A, Ω, W y ms. Toda lectura conserva texto y unidad capturados, valor normalizado, unidad base, precisión y versión de conversión. La presentación puede redondear, pero no modifica el original.

Las series admiten lecturas manuales, calculadas e importadas. Bluetooth, Modbus y dispositivos externos quedan modelados, no conectados. Los cálculos incluyen mínimo, máximo, promedio, rango, desviación estándar muestral, error absoluto/porcentual, diferencia contra patrón, diferencial de presión y volumen derivado. Una división entre cero produce “No calculable”.

## Tolerancias DEMO

Las tolerancias están centralizadas y versionadas en `FunctionalCatalogs`. Son exclusivamente DEMO y no constituyen aprobación técnica oficial. Los widgets no contienen valores técnicos. Un catálogo oficial podrá reemplazarlas conservando el ID y la versión usados por cada resultado.

## Instrumentos y flujómetros

Solo el tipo de instrumento usa catálogo. Marca y Modelo son texto libre para el flujómetro instalado, caudalímetro patrón y equipos auxiliares. No existen catálogos precargados, IDs de marca/modelo, listas desplegables ni sugerencias demo. El número de serie también es libre y su condición se guarda separadamente: identificado, no identificable, no legible, sin placa o no identificado.

Los campos nuevos `brandText` y `modelText` leen como fallback los campos heredados `brand` y `model`. El texto anterior no se normaliza, borra ni convierte en IDs. En una etapa posterior podrán añadirse sugerencias, normalización, deduplicación o inventario, siempre conservando entrada libre hasta aprobar un catálogo oficial.

## Seguridad

La aplicación registra verificaciones, no sustituye procedimientos de seguridad y no prescribe presiones, conexiones ni maniobras. Una precondición crítica bloquea la prueba y permite guardar visita sin prueba con motivo, evidencia y reprogramación. Manómetros y caudalímetros patrón vencidos o desconocidos bloquean mediciones oficiales demo. La acción Suspender prueba permanece accesible durante una prueba activa.

## Matriz de evidencia

Cuando se ejecuta una prueba son obligatorios montaje general, banco instalado, instrumentos y estado final. Presión, caudal, válvulas, reductora, solenoide, energía, comunicaciones, alarmas, fugas y componentes fallidos exigen evidencia según ejecución/resultado. `No aplica` y `No realizada` son estados diferentes y ambos exigen motivo; `No realizada` afecta el resultado. Si no puede instalarse el banco, se exige evidencia de la condición impeditiva.

RF reutiliza `InspectionPhoto`, almacenamiento privado, miniaturas, SHA-256, `inspection_photos_v1` y `media_work_queue_v1`. Las asociaciones funcionales son opcionales para no romper fotos anteriores. Solo `verified` cuenta como sincronizado; el simulador no verifica automáticamente fotos reales.

## Filtros y navegación

Inicio publica un `HydrantFilterRequest` y cambia a la rama Hidrantes ya existente. `AutoVisibleFilterBar` mantiene una clave estable por filtro, espera el frame y usa `Scrollable.ensureVisible` cuando el chip no está totalmente visible. Cada `requestId` se consume una sola vez, no mueve la lista vertical y no usa offsets hardcodeados.

## Sincronización y trazabilidad

`SyncQueueItem` representa elementos tipados y dependencias. El orden lógico es hidrante, elegibilidad, RF, instrumentos, pruebas, series, lecturas, resultado, fotografías y trazabilidad. Cualquier elemento pendiente, fallido o foto sin verificar impide mostrar el estado global completo.

`TraceEvent` admite contexto estructurado opcional de inspección, entidad, motivo, metadatos y correlación sin romper eventos anteriores.

## Estado de implementación de esta etapa

Implementado y funcional en almacenamiento local: elegibilidad, un RF activo por hidrante, borrador recuperable, diez pasos, visita sin prueba, pausa/suspensión/cancelación, instrumentos con retiro lógico, series manuales, aceptación/rechazo de lecturas, cálculos, resultado versionado, evidencia sobre el pipeline existente, cola tipada y trazabilidad. Nuevo levantamiento crea RV, RF o ambos como documentos independientes y conserva una operación recuperable cuando ocurre un error.

Implementado parcialmente: la interfaz captura y persiste una prueba por tipo al guardar cada paso. Los modelos y repositorios admiten colecciones, pero la UI todavía no administra múltiples válvulas, múltiples corridas de reductora ni una batería de varias alarmas dentro del mismo paso. Las reglas DEMO calculan un resultado preventivo, pero no reemplazan tolerancias ni criterios oficiales.

Simulado por decisión de alcance: telemetría, Modbus y actuación remota. Sus contratos manuales/mock no abren conexiones ni envían comandos reales. La sincronización sigue siendo una cola local simulada; no existe backend remoto.

Pendiente de validación manual: cámara y recuperación tras interrupción en dispositivo, rotación con autocentrado de filtros, consistencia de contadores con datos reales, persistencia tras cierre forzado, integridad de fotografías y ciclo completo de sincronización simulada. No se agregaron pruebas automatizadas conforme a la restricción de la etapa.

## Correcciones de estabilización Etapa 4

RF resuelve el último REPORTE VISUAL finalizado mediante `CompletedVisualReportResolver`. La consulta usa el identificador canónico, ignora borradores y conserva un fallback tipado para proyecciones demo heredadas que no poseen documento RV. El caso del hidrante 1104 se cubre por esta regla general, sin excepciones por código.

En el primer paso, Atrás guarda el borrador y navega explícitamente a la ficha. Esto evita reinterceptar `context.pop()` dentro de `PopScope(canPop: false)`.
