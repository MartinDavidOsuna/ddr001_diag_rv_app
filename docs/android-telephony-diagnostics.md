# Diagnóstico de telefonía Android para RV

## Causa raíz

La implementación anterior dependía de `connectivity_plus`, que solo devuelve
transportes. Por ello `mobile` se convertía en una muestra `UNKNOWN` sin
operador, radio ni señal, aunque SystemUI sí tuviera esos datos.

## Implementación

`CellularTelephonyChannel.kt` expone
`com.aquafim.ddr001diag/cellular_telephony`. Cada llamada:

1. verifica `READ_PHONE_STATE`;
2. obtiene suscripciones activas;
3. selecciona `SubscriptionManager.getDefaultDataSubscriptionId()`;
4. usa `createForSubscriptionId`;
5. registra `DisplayInfoListener`, `SignalStrengthsListener` y
   `ServiceStateListener`;
6. espera datos o un timeout de 3.5 s;
7. desregistra el callback;
8. devuelve un mapa sin identificadores personales.

El canal se libera además desde `MainActivity.onDestroy`.

## Mapeo y persistencia

- GPRS, EDGE, GSM, CDMA, 1xRTT e iDEN → 2G.
- UMTS, HSPA, HSDPA, HSUPA, HSPAP, EVDO y TD-SCDMA → 3G.
- LTE → LTE.
- NR → 5G SA.
- LTE con override NR NSA/NR Advanced → 5G NSA.
- IWLAN → Wi-Fi.

La prioridad de operador es estado de servicio registrado, nombre de red y
nombre de la suscripción. No existe catálogo cerrado de compañías.

La señal conserva nivel Android 0–4, dBm, ASU y clase fuente. El porcentaje es
0/25/50/75/100. Un nivel cero sin servicio no se presenta como medición
concluyente. Transporte de Internet y red celular se almacenan por separado.

El modelo también conserva tipos brutos, override, slot, cantidad de
suscripciones, roaming, timestamp y motivo de indisponibilidad. Los campos
técnicos se envían dentro de `technicalData`, ya admitido por la API. Los
borradores históricos continúan abriendo.

## Evidencia física enmascarada

Pixel 7 Pro, Android 17/API 37:

| Condición | Transporte | Operador | Radio | Nivel | dBm |
|---|---|---|---|---:|---:|
| Datos móviles | Red móvil | TELCEL | LTE | 3/4 (75%) | -106 |
| Wi-Fi activo | Wi-Fi | TELCEL | 5G NSA | 3/4 (75%) | -106 |
| Recaptura | Red móvil | TELCEL | LTE | 4/4 (100%) | -94 |

Los valores varían naturalmente con el módem. La captura Wi-Fi demuestra que
el transporte no reemplaza al operador. Logcat registró `callbackReleased=true`
y “telephony callback unregistered” en cada captura.

Al denegar el permiso, GPS se guardó y la interfaz mostró:
“No se autorizó el acceso a la información de red móvil.” Después de concederlo
de nuevo se recuperó la lectura real.

No se guardaron coordenadas, IMSI, ICCID, teléfono ni identificadores de SIM.

## Dual SIM y limitaciones

En dual SIM se usa la suscripción predeterminada de datos aunque no sea la
primera; si no está activa se usa la primera activa y se registra esa condición.
La prueba física tuvo una suscripción activa dentro de un dispositivo DSDS; dos
suscripciones activas están cubiertas por pruebas de modelo.

`cmd phone list-sims` no está disponible en Android 17 del dispositivo. Se
usaron `SubscriptionManager` dentro de la app y dumpsys filtrado como
alternativas. OEMs pueden limitar nombres, callbacks o métricas; el resultado
distingue permiso denegado, sin SIM, sin servicio, timeout, excepción y dato no
reportado.

