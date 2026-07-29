# Sesión manual ejecutable — Etapa 12.5.3-M

> No comenzar casos hasta registrar fecha y probador. Usar exclusivamente
> `TEST-12-5-3-NORMAL` y `TEST-12-5-3-OFFLINE`. Nunca limpiar datos de la app,
> desinstalarla ni enviar información productiva.

## Entorno preparado

- API: `http://192.168.1.111:3000/api/v1`
- Base exclusiva: `RevisionVisualStarter_Test`
- Pixel 7 Pro: `com.aquafim.ddr001diag`, versión `0.2.1+12`
- Usuario de campo: `Responsable Test` (`field.test@example.invalid`)
- Cuenta administrativa de pruebas activa: `admin.test@example.invalid`
- Hidrante normal: `TEST-12-5-3-NORMAL`
- Hidrante de resiliencia: `TEST-12-5-3-OFFLINE`

La contraseña se obtiene del canal seguro de pruebas o de
`RVS_TEST_ADMIN_PASSWORD`; no se copia en este documento.

## Recolección segura de evidencia

```powershell
$adb = 'C:\Users\Martin\AppData\Local\Android\Sdk\platform-tools\adb.exe'
& $adb logcat -c
& $adb logcat
& $adb shell screencap -p /sdcard/rv_test.png
& $adb pull /sdcard/rv_test.png .\rv_test.png
```

Antes de adjuntar evidencia, revisar que no contenga tokens, credenciales,
observaciones completas, datos personales, rutas privadas ni fotografías
sensibles. Registrar únicamente el fragmento asociado al `x-request-id`.

## Verificación SQL posterior a un envío sintético

Abrir:

```text
C:\DEV\AQAGS\ddr001_api_rv\database\diagnostics\12_5_3_manual_session_check.sql
```

Sustituir `@inspection_id` por el ID remoto sintético y ejecutar únicamente con
la conexión que muestre `RevisionVisualStarter_Test`. La consulta se niega a
operar sobre otra base y valida inspección, respuestas, válvulas, fotografías,
estado, auditoría y duplicados.

## Registro común de sesión

- Fecha: ____________________
- Probador: ____________________
- Dispositivo: Pixel 7 Pro / ____________________
- Versión: `0.2.1+12` / ____________________

---

## B-M01 — Cámara real

- [ ] Escena neutra confirmada
- [ ] Abrir y cancelar cámara conserva paso 2
- [ ] Capturar y aceptar conserva paso, rubro y estado
- Resultado: [ ] APROBADO [ ] FALLÓ [ ] BLOQUEADO
- Resultado observado: ______________________________________________
- Captura: ____________________
- ID local de inspección: ____________________
- ID remoto: ____________________
- x-request-id: ____________________
- Log relacionado: ____________________
- Observaciones: ______________________________________________

## B-M02 — Galería real

- [ ] Cancelar selector conserva paso y rubro
- [ ] Seleccionar fixture conserva el formulario
- Resultado: [ ] APROBADO [ ] FALLÓ [ ] BLOQUEADO
- Resultado observado: ______________________________________________
- Captura: ____________________
- ID local de inspección: ____________________
- ID remoto: ____________________
- x-request-id: ____________________
- Log relacionado: ____________________
- Observaciones: ______________________________________________

## B-M03 — Slot fotográfico correcto

- [ ] Seleccionar dos slots distintos
- [ ] Confirmar asociación independiente en resumen
- Resultado: [ ] APROBADO [ ] FALLÓ [ ] BLOQUEADO
- Resultado observado: ______________________________________________
- Captura: ____________________
- ID local de inspección: ____________________
- ID remoto: ____________________
- x-request-id: ____________________
- Log relacionado: ____________________
- Observaciones: ______________________________________________

## B-M04 — Zoom de fotografía

- [ ] Abrir visor, ampliar, reducir y cerrar
- [ ] Regresar al mismo paso y posición razonable
- Resultado: [ ] APROBADO [ ] FALLÓ [ ] BLOQUEADO
- Resultado observado: ______________________________________________
- Captura: ____________________
- ID local de inspección: ____________________
- ID remoto: ____________________
- x-request-id: ____________________
- Log relacionado: ____________________
- Observaciones: ______________________________________________

## B-M05 — Borrado fotográfico

- [ ] Cancelar conserva ambas fotos
- [ ] Confirmar elimina solo la seleccionada
- Resultado: [ ] APROBADO [ ] FALLÓ [ ] BLOQUEADO
- Resultado observado: ______________________________________________
- Captura: ____________________
- ID local de inspección: ____________________
- ID remoto: ____________________
- x-request-id: ____________________
- Log relacionado: ____________________
- Observaciones: ______________________________________________

## B-M06 — Scroll al control pendiente

- [ ] Abrir pendiente desde resumen
- [ ] Confirmar llegada al control exacto
- Resultado: [ ] APROBADO [ ] FALLÓ [ ] BLOQUEADO
- Resultado observado: ______________________________________________
- Captura: ____________________
- ID local de inspección: ____________________
- ID remoto: ____________________
- x-request-id: ____________________
- Log relacionado: ____________________
- Observaciones: ______________________________________________

## B-M07 — Teclado y foco

- [ ] Navegar con teclado abierto
- [ ] Confirmar cierre y ausencia de foco heredado
- Resultado: [ ] APROBADO [ ] FALLÓ [ ] BLOQUEADO
- Resultado observado: ______________________________________________
- Captura: ____________________
- ID local de inspección: ____________________
- ID remoto: ____________________
- x-request-id: ____________________
- Log relacionado: ____________________
- Observaciones: ______________________________________________

## B-M08 — Resaltado de reactivo

- [ ] Navegar desde pendiente
- [ ] Confirmar resaltado perceptible y temporal
- Resultado: [ ] APROBADO [ ] FALLÓ [ ] BLOQUEADO
- Resultado observado: ______________________________________________
- Captura: ____________________
- ID local de inspección: ____________________
- ID remoto: ____________________
- x-request-id: ____________________
- Log relacionado: ____________________
- Observaciones: ______________________________________________

## B-M09 — Legibilidad

- [ ] Revisar teléfono
- [ ] Revisar tablet si está disponible
- [ ] Confirmar ausencia de cortes u overflow
- Resultado: [ ] APROBADO [ ] FALLÓ [ ] BLOQUEADO
- Resultado observado: ______________________________________________
- Captura: ____________________
- ID local de inspección: ____________________
- ID remoto: ____________________
- x-request-id: ____________________
- Log relacionado: ____________________
- Observaciones: ______________________________________________

## B-M10 — Paso 8

- [ ] Probar 1, 2 y 3 válvulas
- [ ] Probar 3 de 4 pulgadas y Otro
- [ ] Revisar marcas, componentes y diámetros derivados
- Resultado: [ ] APROBADO [ ] FALLÓ [ ] BLOQUEADO
- Resultado observado: ______________________________________________
- Captura: ____________________
- ID local de inspección: ____________________
- ID remoto: ____________________
- x-request-id: ____________________
- Log relacionado: ____________________
- Observaciones: ______________________________________________

## B-M11 — Navegación desde resumen

- [ ] Crear varios pendientes
- [ ] Corregir uno y volver al resumen
- [ ] Confirmar que desaparece solo el resuelto
- Resultado: [ ] APROBADO [ ] FALLÓ [ ] BLOQUEADO
- Resultado observado: ______________________________________________
- Captura: ____________________
- ID local de inspección: ____________________
- ID remoto: ____________________
- x-request-id: ____________________
- Log relacionado: ____________________
- Observaciones: ______________________________________________

## C-M01 — Modo offline visible

- [ ] Usar `TEST-12-5-3-OFFLINE`
- [ ] Desconectar Wi-Fi y editar borrador
- [ ] Confirmar indicador y persistencia
- Resultado: [ ] APROBADO [ ] FALLÓ [ ] BLOQUEADO
- Resultado observado: ______________________________________________
- Captura: ____________________
- ID local de inspección: ____________________
- ID remoto: ____________________
- x-request-id: ____________________
- Log relacionado: ____________________
- Observaciones: ______________________________________________

## C-M02 — Recuperación de conexión

- [ ] Restaurar el mismo estado de red inicial
- [ ] Sincronizar cambios pendientes
- [ ] Confirmar reconciliación sin duplicados
- Resultado: [ ] APROBADO [ ] FALLÓ [ ] BLOQUEADO
- Resultado observado: ______________________________________________
- Captura: ____________________
- ID local de inspección: ____________________
- ID remoto: ____________________
- x-request-id: ____________________
- Log relacionado: ____________________
- Observaciones: ______________________________________________

## D-M01 — Reinicio físico

- [ ] Guardar borrador y registrar paso
- [ ] Reiniciar Pixel y abrir app
- [ ] Confirmar sesión, borrador y paso
- Resultado: [ ] APROBADO [ ] FALLÓ [ ] BLOQUEADO
- Resultado observado: ______________________________________________
- Captura: ____________________
- ID local de inspección: ____________________
- ID remoto: ____________________
- x-request-id: ____________________
- Log relacionado: ____________________
- Observaciones: ______________________________________________

## D-M02 — Batería baja

- [ ] Activar ahorro de energía de forma controlada
- [ ] Editar y guardar borrador
- [ ] Confirmar ausencia de pérdida
- Resultado: [ ] APROBADO [ ] FALLÓ [ ] BLOQUEADO
- Resultado observado: ______________________________________________
- Captura: ____________________
- ID local de inspección: ____________________
- ID remoto: ____________________
- x-request-id: ____________________
- Log relacionado: ____________________
- Observaciones: ______________________________________________

## D-M03 — Permisos retirados

- [ ] Retirar cámara o ubicación
- [ ] Reintentar operación
- [ ] Confirmar mensaje útil y borrador intacto
- Resultado: [ ] APROBADO [ ] FALLÓ [ ] BLOQUEADO
- Resultado observado: ______________________________________________
- Captura: ____________________
- ID local de inspección: ____________________
- ID remoto: ____________________
- x-request-id: ____________________
- Log relacionado: ____________________
- Observaciones: ______________________________________________

## D-M04 — Bloqueo durante cámara

- [ ] Confirmar escena segura
- [ ] Bloquear y desbloquear durante cámara
- [ ] Confirmar regreso seguro
- Resultado: [ ] APROBADO [ ] FALLÓ [ ] BLOQUEADO
- Resultado observado: ______________________________________________
- Captura: ____________________
- ID local de inspección: ____________________
- ID remoto: ____________________
- x-request-id: ____________________
- Log relacionado: ____________________
- Observaciones: ______________________________________________

## D-M05 — Llamada o notificación

- [ ] Interrumpir de forma controlada
- [ ] Regresar al formulario
- [ ] Confirmar paso y respuestas
- Resultado: [ ] APROBADO [ ] FALLÓ [ ] BLOQUEADO
- Resultado observado: ______________________________________________
- Captura: ____________________
- ID local de inspección: ____________________
- ID remoto: ____________________
- x-request-id: ____________________
- Log relacionado: ____________________
- Observaciones: ______________________________________________

## E-M01 — Revisión funcional del reporte

- [ ] Comparar resumen con la captura sintética
- [ ] Verificar significado técnico y cantidades
- Resultado: [ ] APROBADO [ ] FALLÓ [ ] BLOQUEADO
- Resultado observado: ______________________________________________
- Captura: ____________________
- ID local de inspección: ____________________
- ID remoto: ____________________
- x-request-id: ____________________
- Log relacionado: ____________________
- Observaciones: ______________________________________________

## E-M02 — Confirmación del inspector

- [ ] Revisar la matriz completa
- [ ] Registrar aceptación o bloqueo
- Resultado: [ ] APROBADO [ ] FALLÓ [ ] BLOQUEADO
- Resultado observado: ______________________________________________
- Captura: ____________________
- ID local de inspección: ____________________
- ID remoto: ____________________
- x-request-id: ____________________
- Log relacionado: ____________________
- Observaciones: ______________________________________________
