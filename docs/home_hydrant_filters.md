# Inicio, alertas y filtros de Hidrantes

## Alerta de Inicio

La alerta completa es una superficie Material con `InkWell`, ripple, semántica de botón y área táctil correspondiente a toda la tarjeta. La implementación anterior solo asignaba callback al `IconButton` del extremo; el cuerpo de `SectionCard` no tenía `onTap`, por eso tocar el texto o el área principal no respondía.

Una alerta con `hydrantId` válido abre `/hydrants/{id}` dentro de la rama Hidrantes de `StatefulShellRoute`. Si el ID no existe localmente se muestra un mensaje controlado. Una alerta sin hidrante abre un bottom sheet con título, descripción, fecha, severidad, origen, acción recomendada y Cerrar. La alerta demo se relaciona con el único hidrante devuelto del conjunto local, `DDR001-HID-0712` (ID `712`), y abre su ficha.

## Resumen de jornada

Inicio muestra exclusivamente cuatro métricas:

- Asignados → Todos.
- Terminados → Finalizado.
- En proceso → En proceso.
- Sin sincronizar → Sin sincronizar.

`AppState.hydrantsForFilter` y `HydrantQueryProjection` producen tanto los totales como la lista. Inicio no contiene predicates propios.

## Reglas centrales

- Todos: todos los hidrantes disponibles en el contexto actual.
- RV: RV disponible, activo, finalizado o con borrador local.
- RF: elegibilidad RF, resumen RF disponible, reporte activo, historial RF o asignación RF heredada.
- En proceso: RV iniciado/borrador o RF activo. RF pausado y suspendido cuentan porque conservan índice activo y son recuperables. RF completado, cancelado o sincronizado no cuenta, salvo que exista otro trabajo activo.
- Sin sincronizar: estado del hidrante no sincronizado, elemento tipado de cola pendiente/error asociado al hidrante, fotografía asociada cuyo estado no sea `verified`, o traza asociada todavía no marcada como sincronizada.
- Finalizado: al menos un REPORTE VISUAL o REPORTE FUNCIONAL completado. Esta es también la definición de Terminados en Inicio.

Los filtros técnicos anteriores permanecen en el enum para compatibilidad interna, pero la barra principal solo proyecta: Todos, RV, RF, En proceso, Sin sincronizar y Finalizado. Los textos visibles no se usan como identificadores.

## Navegación y auto-scroll

Inicio publica un `HydrantFilterRequest` con ID monotónico y navega con `go` a la rama Hidrantes existente. No crea un segundo shell. Hidrantes aplica el filtro y limpia la búsqueda antes de calcular resultados.

El fallo anterior tenía tres causas combinadas: no existía un `ScrollController` horizontal propio, el viewport/posición se resolvía desde el contexto del chip mediante el ancestro `Scrollable`, y el request se consumía incluso si el chip no había quedado visible. Tampoco se distinguía de forma explícita si la rama indexedStack estaba activa.

`AutoVisibleFilterBar` ahora conserva en su `State`:

- un `ScrollController` exclusivamente horizontal;
- un `GlobalKey` del viewport;
- un `GlobalKey` estable por filtro.

Después del frame verifica que la rama esté activa mediante `TickerMode`, que el controlador tenga clientes y que existan ambos `RenderBox`. Compara las coordenadas reales del chip contra el viewport. Si hace falta, calcula el desplazamiento por la diferencia entre centros, limita el destino a los extremos reales y anima solo el controlador horizontal. El `requestId` se consume después de que la comprobación o animación haya podido ejecutarse correctamente.

La selección manual no genera solicitudes de Inicio. Al seleccionar Todos se limpia la solicitud anterior. Un cambio de métricas/rotación vuelve a comprobar visibilidad una vez, sin tocar la lista vertical.

## Validación manual pendiente

Validar en dispositivo los seis chips en ambas orientaciones, todos los accesos desde Inicio, Atrás, búsqueda previa, alerta genérica, alerta asociada y conservación del scroll vertical.
