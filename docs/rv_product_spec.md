# Especificación de producto — Componentes internos de RV

## Navegación vigente por compartimiento

REPORTE VISUAL usa nueve pasos. El paso 5 contiene exclusivamente los componentes de red pública y el paso 6 los componentes generales de red privada y las salidas agrupadas. La navegación productiva es mediante listas; el esquema espacial, zoom, pan, fondos raster y selector Esquema/Lista fueron descartados.

El medidor visible en red pública es una referencia al dato canónico del paso 4. No se crea una segunda inspección de medidor. La red privada conserva sus siete componentes generales y agrupa cada salida con válvula de seccionamiento, piloto, manómetro y toma, sin mezclar registros entre salidas.

Los filtros de ambos pasos son Todos, Pendientes, Hallazgos, Con fotografías y No verificables. Un hallazgo revisado no se considera pendiente. La revisión rápida se limita al compartimiento o salida confirmados y conserva hallazgos, evidencia y discrepancias.

## Asistente secuencial por componente

Cada compartimiento se captura como subasistente dentro de su paso global. La red pública recorre diez elementos, incluido el resumen canónico del medidor del paso 4. La red privada recorre siete elementos generales y cuatro elementos por salida. El encabezado indica componente actual, total, salida, diámetro, progreso y estado de guardado.

Los valores favorables se muestran como propuesta de captura, pero permanecen `Sin confirmar`. Abrir, retroceder o guardar el borrador no crea una revisión favorable. Solo “Confirmar componente y continuar” registra confirmación explícita, inspector y fecha. Los documentos legacy leen esta confirmación como falsa.

El índice permite saltar a un componente conservando el borrador activo. Al terminar se presenta un resumen de revisados, pendientes, hallazgos y fotografías antes de completar el paso global.

RV conserva ocho pasos; este cambio redefine exclusivamente el paso 5. La captura canónica del medidor sigue en el paso 4.

## Configuraciones

- A1: 10 componentes públicos + 7 privados + 4 de una salida = 21.
- A2: 10 + 7 + 8 = 25.
- A3: 10 + 7 + 12 = 29, salidas de 3 pulgadas.
- A4: 10 + 7 + 12 = 29, salidas de 4 pulgadas.
- A5 Custom: composición derivada de su definición editable.

Cada componente posee UUID estable independiente de su etiqueta visual. Las salidas agrupan válvula de seccionamiento, piloto, manómetro y toma.

## Compatibilidad

La lectura anterior proyecta `FlowMeterAssessment` y `PressureValveAssessment` sin declararlos confirmados. Un borrador se escribe con esquema nuevo conservando campos heredados y desconocidos. Un RV finalizado no se migra ni reescribe al abrirse.

## Reglas

Presencia, condición y observaciones usan enums estables. “Sin daño visible” excluye daños. Hallazgos importantes/críticos, ausencia esperada, diferencias y elementos no catalogados exigen evidencia. La ficha del manómetro advierte que la lectura visual no certifica medición ni calibración.

La revisión rápida excluye componentes críticos, especializados, con evidencia requerida, diferencias, datos previos o definición custom. Nunca sobrescribe información.
