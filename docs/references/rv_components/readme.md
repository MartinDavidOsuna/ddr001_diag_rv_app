# Referencias visuales — REPORTE VISUAL / Componentes internos

## Propósito

Esta carpeta contiene referencias visuales para el rediseño del paso **Componentes internos** dentro de **REPORTE VISUAL (RV)** de la aplicación **DIAGNOSTICO HIDRANTES — Distrito de Riego 001**.

Las imágenes sirven para orientar:

- jerarquía visual;
- navegación entre esquema y lista;
- agrupación por compartimiento;
- inspección por componente;
- revisión por salida;
- estados de avance;
- pendientes;
- hallazgos;
- revisión rápida;
- resumen de inspección;
- configuración de hidrantes A1, A2, A3, A4 y A5 Custom.

Estas imágenes son **referencias de producto y UX**. No deben tratarse como recursos productivos de la aplicación ni como especificaciones hidráulicas certificadas.

## Ubicación esperada

```text
docs/references/rv_components/
```

No mover estas imágenes a `assets/` ni empaquetarlas dentro de la aplicación salvo aprobación explícita.

## Archivos de referencia

### `hydrant_reference_render.png`

Render frontal de un hidrante dentro de gabinete, dividido conceptualmente en:

- compartimiento izquierdo — red pública;
- compartimiento derecho — red privada.

Se utiliza para comprender la disposición física aproximada de tuberías, válvulas, medidor, válvula sostenedora-reguladora, pilotos, solenoides, manómetros, filtro, conjunto filtrante, válvulas de seccionamiento, tomas de salida, juntas y conexiones.

**Importante:** no es un plano hidráulico certificado ni representa necesariamente todas las configuraciones reales. No debe utilizarse para inferir funcionamiento, presión, calibración o desempeño.

### `base44_rv_overview.png`

Vista general del paso **Componentes internos** con encabezado, tipo de hidrante, avance, red pública, red privada, pendientes, hallazgos, fotografías y selector Esquema/Lista.

### `base44_rv_component_detail.png`

Ficha individual básica de un componente. Sirve como referencia visual, pero su formulario es insuficiente para la implementación final porque cada tipo de componente requiere variables técnicas específicas.

### `base44_rv_component_detail_2.png`

Versión ampliada de la ficha individual con estado visual, condiciones observadas, revisión específica, fotografías y marcado como revisado. Debe usarse solo como referencia de jerarquía y controles.

### `base44_rv_findings.png`

Vista de hallazgos o elementos que requieren atención. Debe diferenciar claramente pendiente, hallazgo menor, hallazgo importante, crítico, no verificable y diferencia de configuración.

### `base44_rv_list.png`

Vista alternativa en lista, agrupada por red pública, red privada y salidas. Cada fila debe mostrar estado, resumen técnico y acceso al detalle.

### `base44_rv_pending.png`

Lista de pendientes con acceso directo al componente correspondiente. Los pendientes deben clasificarse por causa: dato obligatorio faltante, evidencia faltante, discrepancia, componente no verificado, componente crítico o validación específica.

### `base44_rv_summary.png`

Resumen final tipo orden de servicio con hidrante, tipo esperado, tipo observado, componentes revisados, pendientes, hallazgos, no instalados, no verificables, fotografías y diferencias.

### `base44_rv_quick_review.png`

Confirmación de revisión rápida sin hallazgos. La implementación final no debe ofrecer una acción indiscriminada de “marcar todo como bueno”.

### `base44_rv_quick_review_result.png`

Resultado visual después de aplicar revisión rápida. La revisión rápida deberá aplicarse solo a componentes elegibles, no sobrescribir hallazgos ni datos existentes, registrar usuario y fecha, y permitir corrección posterior.

### `base44_rv_outlet.png`

Vista de una salida física agrupando válvula de seccionamiento, válvula piloto, manómetro de salida y toma de salida. La salida física debe conservarse como unidad de navegación.

### `base44_rv_type_a1.png`

Referencia de interfaz para hidrante A1: una válvula de seccionamiento de 3 pulgadas.

### `base44_rv_type_a2.png`

Referencia de interfaz para hidrante A2: dos válvulas de seccionamiento de 3 pulgadas.

### `base44_rv_type_a3.png`

Referencia de interfaz para hidrante A3: tres válvulas de seccionamiento de 3 pulgadas.

### `base44_rv_type_a4.png`

Referencia de interfaz para hidrante A4: tres válvulas de seccionamiento de 4 pulgadas.

### `base44_rv_type_a5.png`

Referencia de interfaz para A5 Custom. A5 puede variar en cualquier componente, cantidad, diámetro, compartimiento o salida.

## Configuraciones de referencia

- **A1:** una válvula de seccionamiento de 3 pulgadas.
- **A2:** dos válvulas de seccionamiento de 3 pulgadas.
- **A3:** tres válvulas de seccionamiento de 3 pulgadas.
- **A4:** tres válvulas de seccionamiento de 4 pulgadas.
- **A5 Custom:** configuración abierta que puede variar en componentes, cantidades, diámetros, red pública, red privada, salidas, accesorios y componentes no catalogados.

## Interpretación correcta de las imágenes

Las referencias deben utilizarse para comprender navegación, jerarquía, agrupación, estados, acceso a pendientes, acceso a hallazgos, revisión por componente, revisión por salida, resumen de inspección, uso con una mano y diseño para campo.

No deben utilizarse para:

- copiar código generado por Base44;
- reproducir literalmente la interfaz;
- definir el modelo de persistencia;
- asumir que un componente funciona por verse en buen estado;
- inferir presión o caudal;
- certificar calibración;
- duplicar datos que ya pertenecen a otro paso;
- sustituir una prueba funcional.

## Principio hidráulico

REPORTE VISUAL registra únicamente condiciones razonablemente observables, por ejemplo:

- presencia;
- condición exterior;
- corrosión;
- fuga visible;
- deformación;
- fijación;
- conexiones;
- legibilidad;
- identificación;
- daños;
- evidencia fotográfica.

REPORTE VISUAL no debe concluir por sí solo:

- funcionamiento hidráulico;
- calibración;
- presión correcta;
- caudal correcto;
- actuación automática;
- estanqueidad interna;
- desempeño del filtro;
- operación correcta del solenoide;
- comunicación efectiva del equipo.

Estas comprobaciones corresponden a **REPORTE FUNCIONAL** cuando aplique.

## Reglas para Codex

Antes de modificar la interfaz de RV, Codex debe:

1. Inspeccionar todas las imágenes de esta carpeta.
2. Revisar el código real de REPORTE VISUAL.
3. Verificar modelos, validadores, fotografías, persistencia, rutas y pruebas.
4. Usar las imágenes como referencia UX, no como fuente de datos.
5. Conservar compatibilidad read-old/write-new.
6. No borrar Hive.
7. No cambiar UUID.
8. No perder fotografías ni borradores.
9. No modificar reportes finalizados.
10. No iniciar cambios en REPORTE FUNCIONAL.
11. No mover estas imágenes a `assets/` sin aprobación explícita.

## Convención de nombres recomendada

```text
docs/references/rv_components/
  README.md
  hydrant_reference_render.png
  base44_rv_overview.png
  base44_rv_component_detail.png
  base44_rv_component_detail_2.png
  base44_rv_findings.png
  base44_rv_list.png
  base44_rv_pending.png
  base44_rv_summary.png
  base44_rv_quick_review.png
  base44_rv_quick_review_result.png
  base44_rv_outlet.png
  base44_rv_type_a1.png
  base44_rv_type_a2.png
  base44_rv_type_a3.png
  base44_rv_type_a4.png
  base44_rv_type_a5.png
```

Los nombres pueden ajustarse, pero deben ser descriptivos, estables y coincidir con las referencias mencionadas en documentación y planes.

## Estado

**Referencia de diseño para Etapa 5B — REPORTE VISUAL / Componentes internos.**

Estas imágenes no constituyen aprobación final de UI, arquitectura, persistencia ni reglas hidráulicas.