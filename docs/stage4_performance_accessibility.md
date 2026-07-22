# Rendimiento, recursos y accesibilidad — Etapa 4B

Objetivos no certificados: arranque usable <3 s en gama media, filtros <300 ms, foto <8 s y galería usable con 1000 miniaturas.

La galería aísla JSON corrupto, usa miniaturas, conserva filtros y pagina en lotes de 100. Los formularios liberan TextEditingController; ubicación y GPRS cancelan streams/timers; no deben crearse escaneos de cajas dentro de cada tile.

Etapa 4C conserva un máximo inicial de 100 miniaturas, solicita lotes adicionales de 100, usa `cacheWidth` para evitar decodificar originales en la grilla, restaura filtro/posición y registra tiempo de carga, elementos visibles y errores de imagen. El original solo se construye dentro del visor y se libera al cerrarlo. Estas métricas son diagnósticas y no equivalen a certificación de memoria.

Los editores técnicos se muestran en diálogos desplazables, con Cancelar/Guardar explícitos, tooltips en acciones y estados descritos además de iconos/color. La auditoría usa región semántica para su resumen. Texto 2×, TalkBack, orientación, guantes y pantalla pequeña siguen pendientes de validación física.

Checklist manual: objetivos 48×48, contraste, Semantics/Tooltips, estado además de color, teclado numérico, foco/error legible, texto 1×–2×, pantalla pequeña, rotación y TalkBack. Estas condiciones requieren certificación física; compilar no las acredita.
