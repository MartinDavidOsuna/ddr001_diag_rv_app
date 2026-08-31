# Toque accidental a producción durante smoke RV

## Estado

`PRODUCTION TOUCH CONTAINED: YES`

La aplicación implicada fue detenida y no se volvió a abrir. Se retiraron el
proxy global temporal y las reglas `adb reverse`; también se detuvieron la API
TEST local y el proxy local iniciados para la prueba.

## Qué ocurrió

El 30 de agosto de 2026, aproximadamente entre las 17:01:36 y las 17:01:43
hora local de Ciudad de México, una build instalada con el package productivo
`com.aquafim.ddr001diag` ignoró el proxy global de Android y usó directamente
la URL compilada `http://cifra.aquafim.com:3002/api/v1`.

La evidencia local de `logcat` identifica:

- revisión local: prefijo sanitizado `b1bdc598`;
- revisión remota reportada por el cliente: `0F9C1907-A138-4437-BF8A-7C371EBEDCB0`;
- cuenta/hidrante usado en el flujo: cuenta TEST rotulada `1833`;
- identidad de campo utilizada: usuario sintético de certificación
  `RvGateCompat`, cuadrilla `RVGATE30`;
- una creación de revisión, siete cargas fotográficas, `verify-batch`, contenido
  general, respuestas, configuración de válvulas, muestras de ubicación/señal y
  envío final.

No se incluyen coordenadas, tokens, contraseñas ni datos de conexión.

## Confirmación y límites

La base `DDR001_Hidrantes_TEST` fue consultada sólo en lectura. No contiene la
revisión remota anterior en la ventana temporal del incidente, lo que confirma
que ese flujo no llegó a TEST. No se realizó conexión de lectura ni escritura a
la base productiva; por tanto, la existencia final y el estado de cada entidad
en producción no se verificaron directamente.

No se borró ni modificó la revisión, sus fotos o su estado. No se ejecutó SQL de
limpieza.

## Causa

La prueba instaló el flavor productivo con una URL productiva compilada y confió
en un proxy Android externo para redirigir el tráfico. Dio abrió la conexión sin
atravesar ese proxy. La aplicación no tenía una barrera interna que asociara el
ambiente QA con una lista de hosts permitidos.

## Limpieza propuesta

Si el responsable operativo decide limpiar el dato, debe localizar en
producción la revisión remota indicada y sus fotos asociadas, validar que
pertenecen exclusivamente a esta certificación y ejecutar el procedimiento
administrativo/auditado habitual. Esta rama no realiza esa limpieza.
