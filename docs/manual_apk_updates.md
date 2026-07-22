# Actualizaciones manuales mediante APK

## Publicación

El manifiesto y el APK de producción deben alojarse por HTTPS en infraestructura controlada. El manifiesto publica la versión disponible, build, compatibilidad mínima, URL y SHA-256; nunca contiene claves ni secretos.

Para cada entrega se debe:

1. Incrementar `versionName` (`major.minor.patch`).
2. Incrementar obligatoriamente `versionCode`/build. Android no instala como actualización un build igual o menor.
3. Conservar `applicationId` `com.aquafim.ddr001diag`.
4. Firmar con la misma clave digital que la instalación anterior.
5. Calcular y publicar SHA-256 del APK final.
6. Actualizar el manifiesto solo después de que el APK esté disponible.

Una actualización compatible conserva SharedPreferences, cajas Hive y archivos privados. Cambiar applicationId o firma provoca una instalación distinta o impide la actualización.

## Formatos de distribución

- APK debug: artefacto de desarrollo, firmado con clave debug; no es entrega productiva.
- APK release: instalación manual firmada para producción.
- AAB: paquete de publicación; no se instala directamente.
- Google Play Internal Testing: canal recomendado para distribuir builds controlados mediante Play sin instalar APK manualmente.

## Manifiesto

El ejemplo está en `docs/examples/update_manifest_example.json`. `latestVersion` y `latestBuild` identifican la entrega; `minimumSupportedVersion` y `required` determinan restricciones. `androidUrl` apunta al APK release HTTPS y `sha256` permite verificar integridad.

La demo usa un selector en Perfil → Revisar actualización para representar aplicación actual, actualización opcional, obligatoria y error. La versión instalada sigue siendo `0.2.0+3`. Una URL remota real será necesaria para detectar versiones publicadas fuera del APK; el manifiesto local solo funciona como fallback o demostración.

La aplicación abre la URL en un navegador externo. No descarga ni instala silenciosamente porque Android requiere consentimiento, una fuente confiable y validación explícita; hacerlo además aumenta el riesgo de suplantación o pérdida de control del usuario.
