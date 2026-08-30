# Migración del mapa base a OpenFreeMap

Fecha: 2026-08-29

## Problema original

El mapa de hidrantes usaba mosaicos raster `light_all` servidos por CARTO. La
URL, los subdominios y la atribución estaban escritos directamente en
`MapPage`, lo que acoplaba la experiencia del mapa a un proveedor externo y
dificultaba adoptar tiles propios u operación offline.

La lógica de hidrantes no dependía de CARTO: `FlutterMap`, `MapController`, los
marcadores Flutter, selección, filtros, ubicación, cámara, búsqueda por región
y el índice espacial ya estaban separados de la imagen del mapa base.

## Arquitectura nueva

```text
FlutterMap
  ├── BasemapProvider
  │     └── OpenFreeMap Positron (MapLibre vector style)
  ├── Hydrant MarkerLayer
  ├── Current Location Marker
  ├── filtros y selección
  └── carga por región
```

`lib/features/map/basemap/` concentra:

- identidad y tipo de fuente;
- URL del estilo;
- zoom mínimo y máximo;
- atribuciones;
- declaración explícita de si necesita API key;
- carga y ciclo de vida del estilo vectorial.

`MapPage` sólo monta el proveedor configurado y conserva un único
`FlutterMap`/`MapController`. El estilo se carga una vez por instancia del
basemap y no se vuelve a descargar por cambios de filtro, selección,
ubicación o `AppState`.

## Tecnología y dependencias

- Datos abiertos: OpenStreetMap.
- Esquema vectorial: OpenMapTiles.
- Servicio inicial: instancia pública de OpenFreeMap.
- Estilo: Positron,
  `https://tiles.openfreemap.org/styles/positron`.
- Controlador y capas propias: `flutter_map`.
- Render vectorial MapLibre-compatible: `flutter_map_vector_tiles`.

Se eligió `flutter_map_vector_tiles` porque se integra como una capa Flutter
normal de `flutter_map >= 8`. Mantiene la cámara, gestos y `MarkerLayer`
existentes, evita superponer una vista nativa con un segundo controlador y
decodifica tiles fuera del frame de UI. También ofrece caché persistente del
estilo y de áreas visitadas en Android/iOS.

No se eligió el bridge `flutter_map_maplibre` porque su capa embebida añade una
segunda superficie MapLibre y sincronización de cámaras. Esa complejidad no
aporta valor para este mapa 2D y aumenta el riesgo de taps interceptados,
desfase de marcadores y problemas de lifecycle.

## Atribuciones

La interfaz muestra enlaces para:

- OpenFreeMap;
- © OpenMapTiles;
- © OpenStreetMap contributors.

Esto sigue la atribución publicada por OpenFreeMap: OpenFreeMap, ©
OpenMapTiles y datos de OpenStreetMap. Se eliminó la atribución de CARTO.

Referencias oficiales:

- <https://openfreemap.org/quick_start/>
- <https://openfreemap.org/#attribution>
- <https://www.openstreetmap.org/copyright>

## Ausencia de API keys

OpenFreeMap no requiere registro, cuenta, token ni API key. La configuración
declara `requiresApiKey: false`; la URL no tiene parámetros de credenciales y
`StyleReader` se crea sin `apiKey` ni headers de autenticación. No se añadieron
variables de entorno, `dart-define`, metadatos de Android, propiedades Gradle
ni archivos secretos para el mapa.

## Degradación sin red

Los hidrantes locales y la ubicación continúan en capas Flutter independientes
del basemap. Si el estilo no está disponible se muestra un fondo neutro con el
mensaje de que los hidrantes guardados siguen visibles. Si ya existe caché, el
paquete conserva el style bundle y los tiles visitados mediante
stale-while-revalidate. Un fallo de tiles no elimina ni filtra datos locales.

## Evolución offline y self-hosted

`BasemapProvider` permite sustituir OpenFreeMap sin reescribir `MapPage`. Los
tipos previstos son MapLibre vector público/self-hosted, PMTiles y MBTiles.

- OpenFreeMap/OpenMapTiles self-hosted: otro style JSON en un proveedor nuevo.
- TileServer GL o Martin: style y fuentes MapLibre servidos internamente.
- PMTiles: soporte directo del paquete mediante
  `PmTilesVectorTileProvider` y estilos `pmtiles://`.
- MBTiles: complemento `flutter_map_vector_tiles_mbtiles` en plataformas
  nativas.

No se incluyó ningún archivo cartográfico grande ni se descargaron regiones en
esta migración.

## Pruebas

Las pruebas automatizadas cubren:

- OpenFreeMap/Positron como proveedor predeterminado;
- ausencia de credenciales y proveedores comerciales en la configuración;
- atribuciones de datos abiertos;
- degradación determinista sin Internet;
- una sola carga del estilo durante rebuilds y cambios de filtro;
- construcción de `MapPage` y conservación de sus controles;
- proyección, coordenadas, selección, filtros, cámara, índice espacial y
  navegación existentes.

La validación final incluye `flutter pub get`, formato, análisis estático,
suite Flutter completa y builds Android debug/release cuando la configuración
de firma local lo permite.
