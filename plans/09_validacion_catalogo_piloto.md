# Validación del catálogo piloto

Fecha: 2026-07-23. Rama: `test/rv-hydrant-pilot-import`. Versión conservada:
`0.2.1+4`, paquete `com.aquafim.ddr001diag`.

## Integración validada

La API de pruebas contiene 20 hidrantes importados desde manifiesto. `scope=all`
devuelve los 20 y `scope=mine` no los trata como propios hasta existir una inspección.
Una inspección piloto sobre la cuenta `1` usa RV v2 y aparece exclusivamente para su
propietario. Los 20 tienen `source_crs=UNKNOWN`, latitud/longitud nulas; la app no usa
`source_x/source_y` como WGS84 y los contabiliza como hidrantes sin coordenadas.

La separación de cachés existente queda vigente:

- catálogo general: mapa, búsqueda y nueva revisión;
- lista personal: Inicio e Hidrantes, fusionada con borradores locales.

## Correcciones de validación

Se corrigió la ruta `/hydrants/new`: `rvOnly=true` la redirigía erróneamente a la lista,
impidiendo el CTA principal. RV ahora puede abrir la selección; F02-B continúa bloqueado
por el control de tipos.

Desde un marcador, “Iniciar nueva revisión” añade `hydrantId` a la ruta. La pantalla
recibe el argumento, pone ese hidrante primero y lo identifica como seleccionado desde
el mapa, sin exigir una nueva búsqueda. Existe una prueba para preservar el argumento.

## Resultados

- Flutter `3.44.5`, Dart `3.12.2`.
- `dart format .`: correcto.
- `flutter analyze`: sin observaciones.
- `flutter test`: 120/120 aprobadas.
- La búsqueda exacta/parcial, separación `mine/all`, cachés, checklist/ETag y modo
  offline están cubiertos por la suite existente.
- La nueva prueba cubre preselección desde mapa.

## Validación física

Pendiente. `flutter devices` agotó el tiempo y `adb` no está disponible en `PATH`; no
se declaró un Pixel ni otro Android como conectado. Por ello no se afirma haber abierto
ni operado manualmente Inicio, Hidrantes, búsqueda o borrador en el dispositivo.

Para completar:

```powershell
flutter run --dart-define=APP_ENV=development --dart-define=API_BASE_URL=http://192.168.1.111:3000/api/v1
```

Validar sesión, búsqueda de una cuenta del manifiesto, creación/restauración del borrador,
contador sin coordenadas y la preselección usando un marcador WGS84 existente. Los 20
hidrantes piloto no deben dibujarse hasta identificar y transformar su CRS.
