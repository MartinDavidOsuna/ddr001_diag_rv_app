# Checklist de validación Android RV

Versión objetivo: `0.2.1+4`  
Ambiente: desarrollo  
API: valor inyectado mediante `API_BASE_URL`
Fecha: 2026-07-22

Usar datos ficticios y evidencia sin tokens, PII ni fotos sensibles. `PENDIENTE` requiere dispositivo físico y no equivale a aprobado.

| Paso | Resultado esperado | Resultado obtenido | Aprobado | No aprobado | Evidencia | Observaciones | Severidad |
|---|---|---|:---:|:---:|---|---|---|
| Instalación limpia | Instala y abre con identidad correcta | Instalación y proceso activos; UI pendiente | ☑ | ☐ | ADB install/launch | Datos eliminados como exige el escenario | Bloqueante |
| Actualización 0.2.0+3 → 0.2.1+4 | Conserva instalación y datos | APK actualizado y `firstInstallTime` conservado; sesión/Hive pendientes de inspección visual | ☐ | ☐ | dumpsys package | Misma firma debug confirmada por `install -r` | Alta |
| Identidad | Nombre, icono, splash y package correctos | Nombre, package y versión confirmados; icono/splash pendientes | ☐ | ☐ | AAPT + jerarquía UI | Pantalla inicial sin F02-B/RF | Alta |
| Permisos | Cámara y ubicación con mensajes claros | PENDIENTE | ☐ | ☐ |  | Aceptar, negar y negar permanentemente | Alta |
| Sesión | Valida, inicia, restaura, refresca y cierra | PENDIENTE | ☐ | ☐ |  | Inspector ficticio | Bloqueante |
| Hidrantes | Lista, búsqueda, detalle y caché offline | PENDIENTE | ☐ | ☐ |  | Cuenta existente/inexistente/parcial | Bloqueante |
| Checklist | Activo, ETag, orden, reglas y caché | PENDIENTE | ☐ | ☐ |  | Sin fallback hardcodeado silencioso | Bloqueante |
| Respuestas | Persiste progreso y dependencias | PENDIENTE | ☐ | ☐ |  | Cerrar y reabrir parcialmente | Bloqueante |
| GPS concedido | Coordenadas reales, precisión y timestamp | PENDIENTE | ☐ | ☐ |  | No publicar coordenadas | Bloqueante |
| GPS adverso | Explica denegación, apagado y timeout | PENDIENTE | ☐ | ☐ |  | Incluir baja precisión | Alta |
| Señal | Registra solo datos disponibles | PENDIENTE | ☐ | ☐ |  | Wi-Fi, móvil, sin Internet, avión | Alta |
| Cámara | Previsualiza, orienta y comprime | PENDIENTE | ☐ | ☐ |  | Vertical, horizontal, poca luz, EXIF | Bloqueante |
| Siete slots | Asociación, miniatura y estado correctos | PENDIENTE | ☐ | ☐ |  | Ver lista debajo | Bloqueante |
| Reemplazo/eliminación | No duplica antes del submit | PENDIENTE | ☐ | ☐ |  | Reconciliar tras reemplazo | Alta |
| Offline completo | Continúa y conserva todo en modo avión | PENDIENTE | ☐ | ☐ |  | Cerrar desde recientes | Bloqueante |
| Cierre durante respuestas | Reanuda sin pérdida | PENDIENTE | ☐ | ☐ |  |  | Alta |
| Cierre durante upload | Reconcilia sin duplicar fotos | PENDIENTE | ☐ | ☐ |  |  | Bloqueante |
| Interrupción de submit | Consulta remoto y no duplica | PENDIENTE | ☐ | ☐ |  | Solo si es seguro | Bloqueante |
| Sincronización | Etapas claras y siete fotos confirmadas | PENDIENTE | ☐ | ☐ |  | Offline → online | Bloqueante |
| Resumen | Pendientes accionables; submit condicionado | PENDIENTE | ☐ | ☐ |  |  | Alta |
| Submit | Confirma servidor y queda solo lectura | PENDIENTE | ☐ | ☐ |  | Registrar IDs ficticios | Bloqueante |
| API | Inspección y siete fotos visibles | Health PC y TCP/3000 desde Pixel aprobados; flujo pendiente | ☐ | ☐ | health + `nc` | ICMP bloqueado, sin impacto HTTP | Bloqueante |
| SQL Server | Estado y hashes coherentes | PENDIENTE | ☐ | ☐ |  | Solo BD de desarrollo | Bloqueante |
| Dashboard | Inspección enviada visible | PENDIENTE | ☐ | ☐ |  |  | Bloqueante |
| Seguridad | Logcat sin secretos, PII, bytes ni rutas | PENDIENTE | ☐ | ☐ |  |  | Alta |
| UX exterior | Legible al sol y usable con una mano | PENDIENTE | ☐ | ☐ |  | Teclado, scroll, áreas táctiles | Media |
| Rendimiento | Sin cierre o bloqueo en fotos/sync | PENDIENTE | ☐ | ☐ |  | Registrar tiempos y memoria | Alta |

Slots: `front_closed`, `left_side`, `right_side`, `back`, `top`, `front_open`, `serial_plate`.

## Cierre

- Dispositivo: Pixel 7 Pro, Android 17/API 37, arm64, 32 GB libres.
- `clientInspectionId` / `serverInspectionId`: PENDIENTE.
- Resultado: **PENDIENTE DE VALIDACIÓN FÍSICA**.
