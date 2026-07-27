# Resumen y envío RV

El paso funcional final conduce al resumen y nunca envía directamente. El resumen
muestra cuenta/hidrante, inspector, cuadrilla, checklist, inicio, progreso, GPS,
conectividad, fotografías y sincronización.

Los errores obligatorios bloquean el botón. Cada pendiente calcula su sección,
persiste el paso correspondiente y vuelve al formulario sin perder el borrador.

El envío requiere el diálogo explícito `Confirmar envío`. Durante la operación el
botón queda bloqueado; primero sincroniza catálogos y después respuestas,
ubicación, señal, fotografías, reconciliación y submit. El coordinador conserva el
borrador hasta recibir estado remoto `submitted`; un error deja mensaje y permite
reintento. El middleware y `clientInspectionId` evitan duplicación.

Sin conexión no se simula éxito: la inspección permanece local/pending o en error.
No se efectuó ningún envío físico real durante esta etapa.

## Certificación 12.5.2-A

Una inspección exclusivamente sintética completó respuestas, catálogos y siete
slots fotográficos, obtuvo `submitted_at`, conservó una sola fila, rechazó el
segundo envío y quedó bloqueada para edición. La fixture se limpió al finalizar.
No se confirmó el envío desde el dispositivo físico.
# Actualización 12.5.2-B

Los pendientes incluyen destino estable por sección, reactivo, subelemento y
campo. El paso 8 se resume por válvula y existe una acción explícita para
volver al resumen. Los catálogos pendientes de sincronización se conservan
como respuestas válidas localmente, aunque bloquean el envío si todavía no
pueden reconciliarse con IDs remotos.

## Confirmación posterior al envío

El éxito aparece solamente cuando `InspectionSyncCoordinator` devuelve estado
local y remoto `submitted`, después de respuestas, válvulas, ubicación, señal,
fotografías, reconciliación y submit. `RvSubmissionCompletionGate` se consume
una vez por instancia del resumen para impedir diálogos duplicados.

`Aceptar` cierra el diálogo, vacía las rutas de detalle/revisión/resumen de la
rama de hidrantes y navega a `/home`. Una sincronización parcial o fallida
permanece en el resumen y conserva el manejo de error existente.
