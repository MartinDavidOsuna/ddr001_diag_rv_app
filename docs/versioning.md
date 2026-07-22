# Versionamiento

DIAGNOSTICO HIDRANTES utiliza `major.minor.patch+build` desde `pubspec.yaml`.

- `major`: cambios incompatibles o una nueva generación del producto.
- `minor`: funcionalidad compatible agregada.
- `patch`: correcciones compatibles.
- `build`: artefacto distribuible incremental.

La interfaz obtiene la versión con `package_info_plus`; no debe escribirse manualmente en widgets. Cada artefacto Android/iOS distribuido incrementa `build` y registra sus cambios en `CHANGELOG.md`.

El manifiesto local en `assets/config/update_manifest.json` modela los estados actual, opcional y obligatorio. Una actualización obligatoria puede impedir crear o editar diagnósticos, pero nunca consultar datos locales o entrar a sincronización. La aplicación no descarga ni instala paquetes automáticamente.
