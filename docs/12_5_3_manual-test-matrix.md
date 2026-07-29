# Etapa 12.5.3 — Matriz manual previa al piloto

Todas las filas son `MANUAL_REQUIRED`; no forman parte de la aprobación
automatizada.

| ID | Grupo | Escenario | Tipo | Precondiciones | Pasos | Resultado esperado | Resultado obtenido | Evidencia | Estado | Riesgo |
|---|---|---|---|---|---|---|---|---|---|---|
| B-M01 | B | Cámara real | MANUAL_REQUIRED | Escena neutra segura; paso 2 | Abrir, cancelar; abrir, capturar | Retorna al mismo paso y conserva estado | Pendiente | Captura y log sanitizado | PENDIENTE | Medio |
| B-M02 | B | Galería real | MANUAL_REQUIRED | Imagen fixture local | Abrir, cancelar; seleccionar fixture | Retorna al mismo rubro sin pérdida | Pendiente | Captura | PENDIENTE | Medio |
| B-M03 | B | Slot fotográfico | MANUAL_REQUIRED | Dos slots y fixture | Capturar/seleccionar en slot indicado | Evidencia asociada solo al slot correcto | Pendiente | Resumen de evidencias | PENDIENTE | Alto |
| B-M04 | B | Zoom de fotografía | MANUAL_REQUIRED | Foto fixture guardada | Abrir visor, ampliar y cerrar | Zoom fluido; regreso al mismo paso | Pendiente | Video corto | PENDIENTE | Bajo |
| B-M05 | B | Borrado fotográfico | MANUAL_REQUIRED | Dos fotos fixture | Cancelar borrado; confirmar una | Cancelar conserva; confirmar elimina solo una | Pendiente | Antes/después | PENDIENTE | Medio |
| B-M06 | B | Scroll al reactivo | MANUAL_REQUIRED | Resumen con pendiente | Pulsar “Ir al paso” | Llega al control exacto | Pendiente | Video | PENDIENTE | Medio |
| B-M07 | B | Teclado | MANUAL_REQUIRED | Campo enfocado | Avanzar y retroceder | Teclado cierra y foco no se hereda | Pendiente | Video | PENDIENTE | Bajo |
| B-M08 | B | Resaltado | MANUAL_REQUIRED | Pendiente navegable | Ir al reactivo | Resaltado perceptible y no molesto | Pendiente | Captura | PENDIENTE | Bajo |
| B-M09 | B | Legibilidad | MANUAL_REQUIRED | Teléfono y tablet | Recorrer pasos y resumen | Texto, logos y controles legibles, sin cortes | Pendiente | Capturas | PENDIENTE | Medio |
| B-M10 | B | Paso 8 | MANUAL_REQUIRED | Borrador sintético | Probar cinco configuraciones | Formularios y derivados comprensibles | Pendiente | Video/capturas | PENDIENTE | Alto |
| B-M11 | B | Navegación desde resumen | MANUAL_REQUIRED | Varios pendientes | Corregir uno y volver | Desaparece solo el pendiente resuelto | Pendiente | Video | PENDIENTE | Alto |
| C-M01 | C | Modo offline visible | MANUAL_REQUIRED | Wi-Fi apagado con estado restaurable | Abrir y editar borrador | Indicador offline claro; edición disponible | Pendiente | Captura | PENDIENTE | Medio |
| C-M02 | C | Recuperación de conexión | MANUAL_REQUIRED | Cambios offline pendientes | Restaurar Wi-Fi y sincronizar | Reconciliación visible sin duplicados | Pendiente | Captura/log | PENDIENTE | Alto |
| D-M01 | D | Reinicio físico | MANUAL_REQUIRED | Borrador guardado | Reiniciar dispositivo y abrir app | Sesión/borrador/paso conservados | Pendiente | Video | PENDIENTE | Alto |
| D-M02 | D | Batería baja | MANUAL_REQUIRED | Emulación/estado seguro | Activar ahorro y usar flujo | No pérdida ni cierre inesperado | Pendiente | Captura/log | PENDIENTE | Medio |
| D-M03 | D | Permisos retirados | MANUAL_REQUIRED | Borrador guardado | Retirar cámara/ubicación y reintentar | Mensaje útil; borrador intacto | Pendiente | Captura | PENDIENTE | Alto |
| D-M04 | D | Bloqueo durante cámara | MANUAL_REQUIRED | Escena segura | Abrir cámara, bloquear/desbloquear | Regreso seguro al mismo paso | Pendiente | Video | PENDIENTE | Alto |
| D-M05 | D | Llamada o notificación | MANUAL_REQUIRED | Interrupción controlada | Interrumpir durante captura/formulario | Estado y paso permanecen | Pendiente | Video | PENDIENTE | Medio |
| E-M01 | E | Revisión funcional del reporte | MANUAL_REQUIRED | Fixture completa | Comparar resumen con captura | Significado técnico íntegro | Pendiente | Lista firmada | PENDIENTE | Alto |
| E-M02 | E | Confirmación del inspector | MANUAL_REQUIRED | Matriz completada | Inspector revisa y acepta | Aceptación explícita documentada | Pendiente | Firma/acta | PENDIENTE | Alto |
