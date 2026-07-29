# Rendimiento de carga de hidrantes

Fecha de medición: 2026-07-28. Ambiente autorizado: base y proceso de pruebas
locales del proyecto. No se consultó ni modificó producción.

## Instrumentación

La API registra `requestId`, ruta, estado, duración SQL/total, filas, bytes,
pageSize, hasMore y coincidencia ETag. Flutter registra estrategia
snapshot/fallback/caché, duración de solicitud, decodificación, escritura local,
páginas, elementos y consulta del mapa. No se registran tokens ni PII.

## Mediciones reales

| Operación | Cantidad | SQL | API | HTTP aprox. | Flutter | Hive | Marcadores | Resultado |
|---|---:|---:|---:|---:|---:|---:|---:|---|
| Snapshot `/hydrants/sync` en integración | 1,169 | 43 ms | 52 ms | 334,920 bytes | No medido físicamente | No medido físicamente | N/A | 200 |
| Revalidación ETag | 1,169 evaluados, 0 transferidos | 30 ms | 33 ms | 0 bytes | No medido físicamente | 0 escrituras por contrato | N/A | 304 |
| Radio de 2 km, primera implementación | 0 | 1,205 ms | 1,205 ms | 148 bytes | No medido físicamente | No medido físicamente | 0 | 200; se detectó cuello SQL |
| Radio de 2 km, consulta corregida | 0 | 14 ms | 14 ms | 148 bytes | No medido físicamente | No medido físicamente | 0 | 200 |
| Bounding box, consulta corregida | 0 | 12 ms | 12 ms | 148 bytes | No medido físicamente | No medido físicamente | 0 | 200 |
| Prueba unitaria de snapshot Flutter | 1 | N/A | fake: 8 ms | ~101 bytes | decode: 0 ms | write: 3 ms | N/A | 200 |
| Prueba unitaria de mapa Flutter | 1 | N/A | fake: 5 ms | ~187 bytes | incluido | 1 ms | 1 | 200 |

La medición de 1,205 ms confirmó que construir objetos `geography` era
desproporcionado para el conjunto. Se sustituyó por bounding box y distancia
local cuadrática para radios pequeños. La repetición final de integración bajó
a 14 ms y la consulta por límites midió 12 ms. Debe repetirse con una región que
contenga marcadores y con el volumen productivo antes de aprobar despliegue.

## Diagnóstico

- El snapshot evita diez consultas paginadas y transfiere una sola respuesta
  compacta; ETag evita transferencia y escrituras si no cambió.
- El fallback paginado existe solo para servidores anteriores y no bloquea la
  navegación ni borra la caché hasta completar.
- El índice espacial local usa cuadrícula y evita recorrer el catálogo en cada
  frame.
- El mapa consulta 2 km al inicio y límites visibles por acción del usuario.
- El clustering reduce widgets cuando el zoom está alejado.
- No hay medición física de FPS ni del Pixel en esta ejecución; permanece como
  validación obligatoria previa a distribución.

## Procedimiento de medición física pendiente

1. Ejecutar build de diagnóstico con instrumentación habilitada.
2. Medir primer frame, caché dentro de 2 km, primera página y carga completa.
3. Registrar páginas, bytes, decode, Hive, marcadores, clusters y frames lentos.
4. Desplazar el mapa sin tocar el botón y confirmar cero solicitudes.
5. Buscar/actualizar zona y correlacionar request ID con SQL/API.
6. Repetir con caché caliente, ETag, sin red y API no disponible.
