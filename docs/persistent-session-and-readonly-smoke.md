# Sesión persistente y smoke tests de solo lectura

## Sesión móvil

El access token puede expirar. `ApiClient` comparte una única renovación entre
solicitudes concurrentes y reintenta la solicitud original una sola vez.

Una falla de red, timeout, respuesta 5xx o cuerpo temporalmente inválido durante
la renovación no elimina la sesión segura. Solamente un `401` o `403` devuelto
por `/field-sessions/refresh` se considera rechazo definitivo.

Los borradores, fotografías y colas están aislados por usuario y no se eliminan
al perder autorización. Un reporte afectado queda como
`requiresAuthentication` y se reanuda tras autenticar nuevamente al propietario.

## Smoke remoto protegido

Sin credencial, la suite consulta solamente salud y versión:

```powershell
flutter test integration_test/production_readonly_smoke_test.dart `
  --dart-define=API_BASE_URL=http://cifra.aquafim.com:3002/api/v1 `
  --dart-define=ALLOW_PRODUCTION_READONLY_TESTS=true
```

Para habilitar las lecturas autenticadas opcionales se proporciona
`READONLY_ACCESS_TOKEN` desde el entorno de ejecución. No se debe guardar el
token en archivos, consola compartida ni documentación.

La suite no contiene métodos POST, PUT, PATCH o DELETE y no ejecuta logout.

## HTTP temporal

Android permite cleartext únicamente para `cifra.aquafim.com` mediante
`network_security_config.xml`. El resto de los dominios continúa bloqueado. La
solución definitiva es publicar la API mediante HTTPS y retirar esta excepción.

## Validación manual

1. Iniciar sesión y dejar que venza el access token.
2. Completar un levantamiento y pulsar **Sincronizar y enviar**.
3. Confirmar un único log `refresh iniciado` y `result=success`.
4. Interrumpir red durante el refresh y comprobar que el reporte permanece
   visible y pendiente.
5. Reabrir la aplicación: debe restaurar la sesión y el borrador local.
6. Ante revocación real, autenticar nuevamente con el mismo usuario; la cola
   debe reanudar el reporte.
