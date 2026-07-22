# Guía de estados de reportes

## Tipos de trabajo

- REPORTE VISUAL (RV): inspección de identificación, ubicación, componentes, daños y evidencia visible.
- REPORTE FUNCIONAL (RF): pruebas hidráulicas, mecánicas, eléctricas y de comunicaciones cuando aplican.

## Estados

- Borrador: fue creado y contiene información guardada, pero no está listo ni finalizado.
- Listo: la preparación mínima está completa y puede comenzar la inspección.
- En proceso: la inspección está activa y conserva pasos pendientes.
- Pausado: el trabajo se detuvo temporalmente y puede continuarse.
- Suspendido: se detuvo por una condición técnica, operativa o de seguridad y requiere revisión antes de continuar.
- Finalizado: terminó y quedó cerrado e inmutable; una corrección debe crear una revisión relacionada.
- Cancelado: fue cancelado con motivo y no continuará.
- Requiere repetición: debe ejecutarse una nueva inspección relacionada; el reporte original se conserva.
- Pendiente de revisión: necesita revisión o aprobación de supervisión.
- Sincronizado: todos los datos aplicables fueron confirmados. Mientras no exista backend real, este estado es local o simulado y no equivale a confirmación remota oficial.

## Otros términos

- Sin sincronizar: existe información, evidencia o trazabilidad todavía pendiente.
- Pendiente de validación: un hidrante, autorización o dato local necesita revisión.
- Con observaciones: el trabajo concluyó, pero registra condiciones que deben atenderse.
- No evaluable: no hubo información o condiciones suficientes para emitir resultado.
- Visita sin prueba: se documentó la visita, pero no fue posible ejecutar la prueba.
- No aplica: la prueba o dato no corresponde a la configuración; exige motivo cuando así lo indique el flujo.
- No realizada: correspondía, pero no se ejecutó; no equivale a aprobada.
- No verificado: no se obtuvo confirmación suficiente para responder Sí o No.
