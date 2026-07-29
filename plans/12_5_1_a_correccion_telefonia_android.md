# Etapa 12.5.1-A — Corrección de telefonía Android

## Diagnóstico inicial

La captura RV usaba `connectivity_plus.checkConnectivity()`. Esa API identifica
el transporte activo (`mobile`, `wifi`, `none`), pero no consulta operador,
suscripción, tecnología de radio ni señal. No existía un canal nativo para la
captura RV y `READ_PHONE_STATE` no estaba declarado ni concedido.

El Pixel de prueba usa Android 17/API 37 y DSDS. `cmd phone list-sims` no existe
en esta versión. Las alternativas `dumpsys telephony.registry`, configuración
de suscripción de datos y `dumpsys connectivity` confirmaron, sin almacenar
identificadores de SIM:

- una suscripción activa y seleccionada para datos;
- servicio móvil activo;
- operador TELCEL;
- LTE como tecnología base;
- overrides LTE-CA y NR NSA observados en capturas distintas;
- señal LTE real con nivel Android y dBm válidos.

## Estrategia implementada

1. Mantener `connectivity_plus` para el transporte de Internet.
2. Solicitar `READ_PHONE_STATE` desde Flutter.
3. Consultar Android mediante un MethodChannel Kotlin.
4. Elegir primero la suscripción de datos predeterminada y, si no existe,
   la primera suscripción activa.
5. Crear un `TelephonyManager` asociado al `subscriptionId`.
6. Registrar temporalmente listeners de `TelephonyCallback` para display info,
   señal y estado de servicio.
7. Resolver al recibir los tres callbacks o al vencer 3.5 segundos.
8. Desregistrar el callback antes de devolver cualquier resultado.
9. Persistir valores originales y mapeados, sin IMSI, ICCID, teléfono ni
   identidad de celda.

## Permisos

- `ACCESS_NETWORK_STATE`: transporte de Internet; permiso normal.
- `ACCESS_FINE_LOCATION` y `ACCESS_COARSE_LOCATION`: captura GPS ya existente.
- `READ_PHONE_STATE`: selección/consulta de telefonía; peligroso y solicitado
  en tiempo de ejecución.

No se agregaron permisos de SMS, contactos, número telefónico ni permisos
privilegiados. La denegación de telefonía no impide capturar o guardar GPS.

## Criterios y resultado

- Operador, tecnología y señal reales: aprobado físicamente.
- LTE, 5G SA/NSA, 3G y 2G: cubiertos por mapeo y pruebas.
- Datos móviles y Wi-Fi con SIM activa: aprobados físicamente.
- Permiso denegado y recuperación: aprobados físicamente.
- Datos técnicos y compatibilidad de borradores: aprobados.
- Callback liberado: probado por estructura idempotente y confirmado en logcat.
- Flutter format/analyze/test/build: aprobado.
- API: sin cambios requeridos; el contrato existente ya admite
  `technicalData`.

## Riesgos

Android presenta `READ_PHONE_STATE` con la etiqueta del grupo “hacer y
administrar llamadas”, aunque la implementación no realiza llamadas ni lee el
número. Algunos fabricantes pueden omitir callbacks o limitar datos. En esos
casos se conserva un motivo explícito y nunca se inventa tecnología o señal.

