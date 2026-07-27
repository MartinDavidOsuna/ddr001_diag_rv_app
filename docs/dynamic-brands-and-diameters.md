# Catálogos dinámicos de marcas y diámetros

## Inventario

Se detectaron 12 reactivos de marca y 9 de diámetro. Sus códigos completos están
en el plan 12.5.2. La detección de UI se basa en los identificadores estables
`brand` y `diameter`; no se modificaron los 77 IDs.

## Persistencia y compatibilidad

`DynamicCatalogRepository` usa Hive `rv_dynamic_catalogs_v1`. Las altas generan
UUID local, quedan visibles inmediatamente y conservan estado pendiente,
sincronizado o error. Una respuesta nueva guarda `catalogId`, `localCatalogId`,
`displayValue`, categoría/unidad y marca de creación por usuario. Valores
históricos de texto/número siguen mostrándose y se conservan como `legacyText`.

Las marcas se normalizan por caja, bordes, espacios repetidos y puntuación
equivalente. Los diámetros se normalizan a tres decimales: 3, 3.0 y 3.00 son el
mismo valor. Solo se precargan 3 y 4 pulgadas.

Con menos de seis opciones se usan botones adaptables; con seis o más, selector.
Siempre existe el alta alternativa. Los catálogos pendientes se sincronizan antes
de las respuestas con UUID e idempotencia; una falla mantiene el dato local.

## API y SQL

La migración incremental `04_dynamic_brands_diameters.sql` crea tablas, índices,
unicidad, desactivación lógica y referencias históricas opcionales. Expone GET,
POST y PATCH bajo `/api/v1/catalogs/brands` y `/diameters`, autenticados y
protegidos por el middleware RFC Problem/idempotencia existente.

La migración no fue aplicada a ninguna base.

## Certificación 12.5.2-A

La migración fue aplicada posteriormente, solo en
`RevisionVisualStarter_Test`, y repetida sin duplicados. Se verificaron tablas,
índices, UUID cliente, FK y seeds exclusivos 3/4. Las integraciones crean,
normalizan, filtran, desactivan y limpian fixtures sintéticas; el flujo E2E
comprueba IDs de catálogo persistidos en respuestas antes del envío.
# Actualización 12.5.2-B

Las marcas se filtran ahora por `elementType` exacto. `generic` ya no actúa
como comodín. Una marca sin clasificación confiable se conserva, pero no se
muestra en selectores específicos. La unicidad lógica es nombre normalizado
más tipo. Los diámetros mantienen su contrato remoto/local y una selección
offline válida no se clasifica como respuesta faltante.
