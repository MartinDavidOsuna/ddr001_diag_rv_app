# Diagnóstico GPRS y evaluación Wi-Fi — Etapas 4/4C

## Separación de conceptos

El diagnóstico automático evalúa exclusivamente la red celular del teléfono. En Android solicita un `Network` con `TRANSPORT_CELLULAR`, consulta por separado `NET_CAPABILITY_INTERNET` y `NET_CAPABILITY_VALIDATED`, y abre la conexión HTTPS mediante `Network.openConnection`. No usa `bindProcessToNetwork`, por lo que no cambia la ruta global de la aplicación y Wi-Fi no puede satisfacer la prueba.

La prueba describe el teléfono y no certifica el módem instalado en el hidrante. Wi-Fi se evalúa manualmente; no se escanean SSID, RSSI ni redes cercanas.

## Endpoint y privacidad

`CellularProbeConfiguration.demo` centraliza temporalmente `https://connectivitycheck.gstatic.com/generate_204`, método GET, respuesta esperada 204, límites de conexión/lectura de 12 segundos, máximo 1024 bytes y versión `cellular-network-http-demo-v1`. En Etapa 5 debe sustituirse por un endpoint controlado.

La solicitud no incorpora hidrante, ubicación, usuario, tokens, fotografías ni datos del reporte. La persistencia conserva solo host, método y versión; no una URL parametrizada.

## Resultados independientes

- Red adquirida: Android entregó un objeto `Network` celular.
- Capacidad INTERNET: la red declara configuración para internet; no prueba acceso efectivo.
- Capacidad VALIDATED: Android informa validación general; no sustituye la prueba de la app.
- HTTP real: solo un código esperado recibido mediante `Network.openConnection` confirma internet celular para esta prueba.
- Endpoint inaccesible, timeout parcial, TLS o código inesperado: la red puede existir, pero internet queda “No confirmado”.
- Sin red: solo 60 segundos completos sin adquirir una red celular producen `noCellularNetworksAvailable`.
- Error/restricción: produce `indeterminate`; cancelar produce `cancelled`.

El canal libera `NetworkCallback`, `HttpURLConnection`, streams, tarea y timeout al completar, fallar, cancelar o destruir la Activity. La UI conserva un contador máximo de 60 segundos y progreso asociado a eventos nativos reales.

## Calidad y efectividad DEMO

La calidad 1–10 solo se calcula si existe una señal dBm real. Sin ella se muestra “No calculable”. La efectividad `cellular-effectiveness-demo-v2` pondera red adquirida (20), transporte celular (15), INTERNET (15), VALIDATED (15), HTTP esperado (25), latencia (10) y estabilidad histórica (5). Requiere al menos cuatro indicadores; registra utilizados, no disponibles, porcentaje y motivo. Nunca incluye Wi-Fi.

## Wi-Fi manual y condicional

La pregunta principal es “¿Hay una red Wi-Fi cercana?”.

- Sí: muestra y exige “¿Es posible conectarse?”.
- Conexión Sí: muestra y exige señal aparente e internet mediante Wi-Fi.
- Conexión No o No verificado: oculta señal/internet y persiste ambas como `notApplicable`.
- Wi-Fi No o No verificado: oculta todas las dependientes, las normaliza a `notApplicable` y no bloquea avance.
- Cambiar una rama a Sí inicializa sus dependientes sin respuesta; no recupera silenciosamente valores obsoletos.

Las reglas están en `WifiAssessmentRules`; `null` significa sin responder y no representa “No verificado”. Las observaciones son opcionales y solo se muestran en la rama Sí.

## Plataformas y permisos

Android requiere `INTERNET`, `ACCESS_NETWORK_STATE` y el permiso normal `CHANGE_NETWORK_STATE` para solicitar temporalmente un transporte celular; ninguno accede a identidad de SIM o telefonía. No se agregan permisos de telefonía ni Wi-Fi. En iOS y plataformas donde no se garantiza el aislamiento, el adaptador devuelve `platformRestricted`/`indeterminate`; no se afirma paridad.
