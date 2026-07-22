# Incidencias del piloto Android RV

Fecha: 2026-07-22. Versión objetivo: `0.2.1+4`.

## Incidencias reproducidas en preparación

| ID | Fecha | Dispositivo | Android | Versión app | Pantalla | Pasos | Resultado esperado | Resultado real | Severidad | Reproducibilidad | Evidencia | Causa | Corrección | Estado |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| ENV-001 | 2026-07-22 | Pixel 7 Pro | Android 17/API 37 | 0.2.1+4 | Entorno | `adb devices -l` | Equipo autorizado | Inicialmente vacío; después quedó autorizado | Bloqueante física | Transitoria | ADB/Flutter devices | Equipo aún no visible al inicio | Conectar y autorizar equipo | Verificada |
| TOOL-001 | 2026-07-22 | N/A | N/A | 0.2.1+4 | Toolchain | `flutter --version` | Respuesta inmediata | Timeout >120 s dentro del sandbox | Alta | 100% en sandbox | Error de `lockfile` | Sandbox impedía escribir el lock del SDK | Ejecutar Flutter con permiso limitado al SDK | Verificada |

## Plantilla de campo

No adjuntar datos personales, tokens ni fotografías sensibles.

| ID | Fecha | Dispositivo | Android | Versión app | Pantalla | Pasos | Resultado esperado | Resultado real | Severidad | Reproducibilidad | Evidencia | Causa | Corrección | Estado |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| RV-___ | AAAA-MM-DD |  |  |  |  |  |  |  | Baja/Media/Alta/Bloqueante | Siempre/Intermitente/Una vez |  | Pendiente | Pendiente | Abierta |

Estados: Abierta, En análisis, Corregida, Verificada, No reproducible, Diferida.
