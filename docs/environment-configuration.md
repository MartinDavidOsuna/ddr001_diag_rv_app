# Configuración de ambientes

La aplicación no contiene fallback de red. `APP_ENV` acepta `development`,
`qa`, `test`, `staging` o `production`; `API_BASE_URL` siempre es obligatorio.

Ejemplo genérico:

```text
flutter run \
  --dart-define=APP_ENV=development \
  --dart-define=API_BASE_URL=https://api.example.com/api/v1
```

Una configuración ausente, inválida o HTTP no autorizada muestra el shell de
configuración inválida con acción de reintento. No se deben versionar secretos,
hosts internos ni endpoints privados.

Para E2E Android local se usa exclusivamente el flavor/package QA y loopback
mediante `adb reverse`:

```text
flutter run --flavor qa -t lib/main.dart \
  --dart-define=APP_ENV=qa \
  --dart-define=API_BASE_URL=http://127.0.0.1:3003/api/v1
```

El cliente rechaza antes de crear `ApiClient` cualquier combinación entre
package QA, ambiente y host que pudiera dirigir esta build a producción.
