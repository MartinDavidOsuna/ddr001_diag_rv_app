# Recuperación del mapa base de DDR001 RV

Fecha de reconstrucción: 2026-08-31

## Baseline y alcance

La recuperación parte exclusivamente de
`fc0dd19e572ac6c47b142b7ddf5e577b62901c5b`, versión `1.0.16+116`, en la
rama `recovery/rv-complete-intended-state`. El cambio del mapa se traslada a
`release/rv-1.0.17-map-final` sin sustituir el hardening, la persistencia, la
sincronización, los modelos ni la presentación reconstruida.

## Forensia local

Antes de modificar código se revisaron `status`, ramas, historia completa,
reflogs, stashes, worktrees y objetos no referenciados mediante `git fsck` de
solo lectura. No se ejecutaron `git gc`, `git prune` ni `git clean`.

La solución exacta quedó preservada en:

- rama y worktree local `fix/open-source-basemap-openfreemap`;
- commit `719cefa3941eda273c425f57a1ce064a1996d9a1`, creado el
  2026-08-29 sobre `b1caf61`;
- plan histórico `plans/open_source_basemap_migration_20260829.md`;
- APKs locales productivas `1.0.16+116` cuyo AOT contiene
  `https://tiles.openfreemap.org/styles/positron` y no la URL CARTO.

Los tres artefactos locales que corroboran el proveedor recuperado son:

- `DDR001_RV_1.0.16+116_OpenFreeMap_719cefa.apk`;
- `DDR001_RV_1.0.16+116_OpenFreeMap_production-configured_719cefa.apk`;
- `apk/DDR001_RV_1.0.16+116.apk`, el artefacto posterior con identidad Android
  final.

La APK citada como `dist/ddr001-rv-production-aligned-v61.apk` no permanece en
los worktrees, referencias Git ni objetos no referenciados disponibles. Su
validación registrada (`392d1ca-dirty-0f338730c022`, `0.2.39+61`, “Mapa abre
correctamente”) se conserva como evidencia conocida, pero no se presenta como
la fuente del código recuperado. La fuente verificable del delta exacto es
`719cefa` y sus APKs `1.0.16+116`.

## Antes: CARTO raster

El baseline todavía monta un `TileLayer` raster con:

```text
https://{s}.basemaps.cartocdn.com/light_all/{z}/{x}/{y}.png
subdomains: a, b, c, d
maxNativeZoom: 20
userAgentPackageName: com.aquafim.ddr001diag
```

La interfaz atribuye OpenStreetMap y CARTO. OpenStreetMap es la fuente de datos
cartográficos; `basemaps.cartocdn.com` es el servicio externo que renderiza y
sirve esas teselas. El mensaje `API KEY REQUIRED` procede de ese servicio de
teselas, no del catálogo de hidrantes ni de OpenStreetMap.

## Solución histórica recuperada

El commit `719cefa` reemplaza exclusivamente el basemap CARTO por:

```text
Proveedor: OpenFreeMap
Estilo: Positron
URL: https://tiles.openfreemap.org/styles/positron
Formato: estilo MapLibre y teselas vectoriales OpenMapTiles
API key: no requerida
Zoom declarado: 0 a 20
Subdomains: no aplica
```

La implementación mantiene `flutter_map` como controlador, cámara y contenedor
de capas, y agrega `flutter_map_vector_tiles` para renderizar el estilo
vectorial. `BasemapProvider` separa la imagen base de los markers, filtros,
selección, ubicación y carga regional.

No requiere cambios de Android ni de red. No agrega claves, tokens, headers de
autenticación, variables de entorno o secretos. `StyleReader` recibe solamente
la URL pública del estilo.

## Attribution

La atribución recuperada y visible es:

- OpenFreeMap — `https://openfreemap.org/`;
- © OpenMapTiles — `https://openmaptiles.org/`;
- © OpenStreetMap contributors —
  `https://www.openstreetmap.org/copyright`.

## Datos locales y degradación

Los hidrantes no provienen del proveedor de tiles. `HydrantRepository` conserva
el catálogo por ámbito en Hive y `MapPage` siembra sus items desde
`AppState.catalogHydrants`; `MarkerLayer` los representa por separado del
basemap. Las búsquedas regionales pueden actualizar el catálogo mediante la API
propia cuando existe conectividad, pero el mapa y los markers ya persistidos
siguen construyéndose sin esa API.

Si no se puede cargar el estilo, `BasemapLayer` muestra un fondo neutro y el
mensaje “Los hidrantes guardados siguen visibles”. El error del proveedor no
vacía, filtra ni oculta la capa local; tampoco reinicia la carga al cambiar
filtros o reconstruir widgets.

## Archivos del delta histórico

- `lib/features/map/basemap/basemap_config.dart`
- `lib/features/map/basemap/basemap_layer.dart`
- `lib/features/map/basemap/basemap_provider.dart`
- `lib/features/map/basemap/open_free_map_basemap.dart`
- `lib/features/map/map_page.dart`
- `pubspec.yaml` y `pubspec.lock`
- pruebas del proveedor y de degradación local-first

No se modifica ningún contrato de API, servidor, base de datos ni aplicación
externa.
