# Auditoría UX — REPORTE VISUAL

Fecha: 2026-07-16

Se revisaron el flujo real de ocho pasos y las referencias de `docs/references/rv_components/`. Las imágenes se usan únicamente como referencia de jerarquía; no son assets productivos ni planos hidráulicos certificados.

## Hallazgos

- El paso 5 anterior reducía componentes internos a un agregado de válvula y solenoide.
- El medidor ya tiene una fuente canónica en el paso 4 y no debe duplicarse.
- La navegación necesitaba separar panorama (esquema/lista) de edición técnica bajo demanda.
- Los estados pendientes y los hallazgos requieren conceptos distintos.
- La revisión rápida solo es segura sobre registros vacíos y elegibles.

## Decisión aplicada

El paso 5 usa configuración tipada A1–A5, marcadores accesibles, lista agrupada, ficha por componente y validación de dominio. Los controles tienen objetivos táctiles de al menos 48 px. El esquema se declara conceptual. Los reportes finalizados se muestran en lectura y toda corrección continúa mediante revisión.

El esquema espacial se implementa como una capa exclusiva de presentación: `CustomPainter` dibuja gabinete y tuberías, mientras overlays semánticos interactivos representan los componentes. Las coordenadas normalizadas no se persisten y las salidas se distribuyen dinámicamente desde la configuración.

La presentación productiva utiliza fondos WebP optimizados por tipo, generados sin logotipos ni textos. `HydrantImageLayoutDefinition` selecciona un único asset y posiciones normalizadas; los marcadores, estados y accesibilidad siguen siendo widgets Flutter. El dibujo con `CustomPainter` permanece únicamente como recuperación si el asset no puede cargarse.

## Brechas de certificación

La ergonomía con guantes, TalkBack, texto 2×, equipos pequeños y rendimiento en dispositivo permanecen sujetos a la matriz manual.
# Decisión UX vigente: listas separadas

La navegación por esquema se retiró del flujo productivo. En campo, la densidad de marcadores y la variación A5 reducían la precisión táctil y añadían zoom/pan sin mejorar la captura técnica. Los pasos 5 y 6 presentan listas verticales en orden hidráulico, tarjetas de progreso y salidas agrupadas, con objetivos táctiles mínimos de 48×48 y la misma ficha especializada bajo demanda.

Las referencias Base44 y el render frontal permanecen únicamente como documentación histórica de jerarquía y agrupación; no son assets de la aplicación.

La lista panorámica fue sustituida como captura principal por una ficha activa a la vez. Esto reduce densidad cognitiva y evita crear controladores para todos los componentes. El índice sigue disponible como navegación secundaria. La ficha usa revelado progresivo: las condiciones y justificaciones adicionales aparecen cuando la respuesta deja de ser favorable.
