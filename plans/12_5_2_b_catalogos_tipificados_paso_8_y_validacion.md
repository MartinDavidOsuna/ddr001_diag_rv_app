# Etapa 12.5.2-B — Catálogos tipificados, paso 8 y validación

## Diagnóstico inicial

- Ambos repositorios están en `feature/rv-crs-and-catalog-resolution`.
- Se preservan los cambios locales de 12.5.2 y 12.5.2-A.
- `git diff --check` no reporta errores.
- Flutter filtraba marcas por `category` incluyendo siempre `generic`.
- API filtraba con `category IN(@category, 'generic')`.
- Las respuestas de catálogo son mapas, pero el validador exigía primitivas:
  `String` para marca y `num` para diámetro. Esta incompatibilidad explica los
  pendientes inválidos observados después de seleccionar botones.
- El paso 8 usa ocho respuestas planas compartidas por todas las válvulas; no
  puede representar componentes por válvula.
- El resumen conserva paso, pero no un destino estable de reactivo/subcampo.
- Los nombres se muestran con el valor original sin formato de presentación.

## Causa raíz

1. Taxonomía libre/inconsistente y comodín `generic`.
2. Contrato de selección de catálogo no reconocido por validación.
3. Modelo de checklist plano insuficiente para una colección repetible.
4. Navegación del resumen limitada a `sectionId`.

## Inventario de tipos

- `VALVE`: válvulas manuales, parcelarias y de drenaje.
- `SOLENOID`: todos los solenoides.
- `FILTER`: filtros.
- `PILOT`: pilotos reguladores.
- `PRESSURE_GAUGE`: manómetros.
- `FLOW_METER`: medidores/flujómetros.
- `REGULATING_VALVE`: válvula reguladora/sostenedora.
- `COMMUNICATION_DEVICE`: comunicación.
- `POWER_DEVICE`: alimentación/energía.
- `OTHER`: solo cuando el reactivo no permite clasificación confiable.

Mapeo de los 12 campos existentes: flow meter→FLOW_METER; filter→FILTER;
solenoid→SOLENOID; pilot→PILOT; reg/sust principal→REGULATING_VALVE; restantes
de válvula→VALVE.

## Archivos afectados

- Flutter: repositorio dinámico, renderer, borrador/controlador, validador,
  sincronización, resumen y utilidad de nombres.
- API: catálogo, respuestas, rutas de inspección.
- SQL: migración incremental 05 para tipos y válvulas parcelarias.
- Pruebas: dominio/widgets Flutter y unitarias/integración API.

## Diseño de datos

- `rv.brand_element_types(brand_id, element_type)` con PK compuesta.
- Marcas sin clasificación confiable permanecen en `rv.brands` pero no se
  exponen en selectores tipificados.
- `ParcelValveConfiguration` persistente en el borrador.
- `rv.inspection_parcel_valve_configurations` y
  `rv.inspection_parcel_valves`, con unicidad inspección/índice y FK de
  catálogos.
- Las respuestas de catálogo aceptan ID remoto, ID local pendiente o legado
  visible; sincronización pendiente no equivale a captura faltante.

## Estrategia

1. Introducir enum estable de tipos en Flutter/API/SQL.
2. Migrar asociaciones solo cuando la categoría previa sea confiable.
3. Renderizar paso 8 mediante editor especializado y conservar respuestas
   históricas planas.
4. Validar individualmente configuración y válvulas.
5. Persistir destino estable del resumen y desplazar post-frame al campo.
6. Formatear nombres solo al presentarlos.

## Migraciones

- Migración 05 repetible, restringida a `RevisionVisualStarter_Test`.
- No modifica producción ni elimina marcas sin clasificar.
- Conserva 04 y todos los datos históricos.

## Pruebas

- Catálogos estrictos por tipo, duplicados por tipo y compatibilidad histórica.
- Selecciones de mapa válidas, reapertura y separación de sync/captura.
- Configuraciones 1/2/3/otro, componentes y validación detallada.
- Navegación exacta y formato de nombres.
- Suites completas Flutter y Node 22 con integración SQL real.

## Resultado final

Implementación terminada y certificación automatizada aprobada el
2026-07-25. La migración 05 fue aplicada dos veces solo en
`RevisionVisualStarter_Test`. Flutter quedó en 179/179 y API en 80/80
unitarias más 10/10 de integración. APK `0.2.1+10` instalado con `adb
install -r`. La validación física interactiva quedó bloqueada porque el Pixel
estaba bloqueado y no podía verificarse una escena fotográfica segura; no se
envió inspección física.

Pendiente de implementación y certificación.
