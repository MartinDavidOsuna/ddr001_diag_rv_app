# Plan de pruebas — Etapa 5B RV

## Automatización

1. Configuración: totales A1–A4, diámetro A4 y total dinámico A5.
2. Modelo: round-trip, UUID, campos desconocidos y defaults antiguos.
3. Dominio: conflictos de condiciones, evidencia, comentarios, manómetros y revisión rápida.
4. Regresión: ejecutar toda la suite previa, análisis y cobertura.
5. Empaquetado: generar APK debug sin cambiar versión.

## Certificación manual pendiente

Ejecutar `docs/stage5_manual_test_matrix.md` en Android 10 y en el dispositivo principal. Cámara, GPS, GPRS, recuperación por cierre forzado, TalkBack y rendimiento no quedan certificados por pruebas de host.
# Cobertura adicional — flujo RV de nueve pasos

- Verificar títulos, progreso y navegación 4→5→6→7 y regreso 7→6→5.
- Verificar el remapeo idempotente de borradores legacy 6→7, 7→8 y 8→9.
- Confirmar que abrir un reporte finalizado legacy no cambia paso, versión, UUID ni timestamps.
- Confirmar que el paso 5 muestra red pública y referencia el medidor canónico del paso 4.
- Confirmar que el paso 6 agrupa componentes generales y salidas A1–A5.
- Confirmar ausencia de selector Esquema/Lista e `InteractiveViewer` en ambos pasos.
- Ejecutar validación bloqueante por compartimiento sin confundir hallazgo revisado con pendiente.

### Asistente por componente

- Defaults visibles no deben escribir reviewedAt ni marcar revisado.
- Abrir/cerrar y recuperación conservan explicitlyConfirmed=false.
- Confirmar registra actor, fecha y avanza una posición.
- Presencia No limpia condición y observaciones incompatibles.
- Hallazgo elimina Sin daño visible y activa comentario/evidencia condicional.
- Secuencias: pública 10; privada A1=11, A2=15, A3=19, A4=19; A5 dinámica.
- Índice, Anterior, resumen, read-only, texto 200 % y targets 48×48.
