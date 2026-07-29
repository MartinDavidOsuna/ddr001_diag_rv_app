# Configuración de ambientes

La aplicación no contiene fallback de red. `APP_ENV` acepta `development`,
`test`, `staging` o `production`; `API_BASE_URL` siempre es obligatorio.

Ejemplo genérico:

```text
flutter run \
  --dart-define=APP_ENV=development \
  --dart-define=API_BASE_URL=https://api.example.com/api/v1
```

Una configuración ausente, inválida o HTTP no autorizada muestra el shell de
configuración inválida con acción de reintento. No se deben versionar secretos,
hosts internos ni endpoints privados.
