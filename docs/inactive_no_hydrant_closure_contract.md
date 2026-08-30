# Cierre inactivo porque no hay hidrante en la ubicación

## Decisión de dominio

`inactive` es un estado local terminal y de solo lectura de una revisión RV. No
es el estado global del hidrante maestro. El resultado asociado se persiste como
`RvInactiveClosure` con el motivo canónico
`NO_HYDRANT_AT_CAPTURED_LOCATION`.

El cierre conserva una copia inmutable de:

- coordenada y precisión capturadas;
- fecha de captura y fecha de cierre;
- comentario de 10 a 500 caracteres;
- uno o más `photoId` del slot exclusivo `no_hydrant_at_location`;
- usuario, cuadrilla y dispositivo;
- clave de idempotencia derivada de la identidad completa del cierre;
- versión de contrato y estado de sincronización.

El estado inicial de sincronización es `pendingApiContract`. Mientras el
servidor no implemente el contrato, la revisión permanece visible como
“Inactivo · pendiente de sincronización”, no se envía por el flujo normal y no
se marca como confirmada remotamente.

Los documentos legacy no contienen `inactiveClosure`; el campo es opcional y su
ausencia conserva exactamente la semántica anterior. No hay reescritura ni
migración masiva de cajas Hive.

## Persistencia local

Antes del cierre existe un estado opcional y aditivo
`RvInactiveClosureDraft`. Conserva el identificador único del borrador, una
copia exacta de la coordenada persistida en el paso 1, comentario parcial,
`photoId`, usuario, cuadrilla, dispositivo y estado de recuperación. No cambia
el estado local a `inactive`, no completa el contenedor y no retira el índice
activo.

Al salir con contenido guardado, la interfaz obliga a elegir entre:

- **Guardar para continuar después**: conserva el borrador activo y excluye su
  slot fotográfico del pipeline normal.
- **Descartar este reporte**: valida que cada foto sea local, exclusiva de la
  revisión, usuario, dispositivo y slot dedicado, sin estado remoto ni cierre
  confirmado. Una operación journaled retira sólo esas referencias, marca los
  documentos de foto con `deletedAt` y resuelve sus dos colas como
  `discardedLocalInactiveDraft`. Los archivos físicos se conservan para
  recuperación y auditoría; no se produce un huérfano accionable.

Un descarte interrumpido converge durante recovery utilizando la identidad
exacta registrada en el journal. Si no puede demostrarse exclusividad, no
modifica la evidencia y exige revisión manual.

Justo antes de abrir la cámara se persiste un borrador vacío de recuperación.
Así, Android puede restaurar la intención y `retrieveLostData` tras process
death. Si la cámara vuelve cancelada y el reporte no tenía contenido previo,
ese placeholder se descarta de forma journaled y no queda evidencia ni bloqueo.

El cierre local es una operación journaled e idempotente:

1. valida propiedad, dispositivo, edición y coordenada persistida;
2. valida comentario y al menos una referencia del slot exclusivo;
3. comprueba documento, archivo, tamaño y SHA-256 físico de cada foto;
4. persiste el sobre `inactiveClosure` dentro del documento RV existente;
5. marca el documento contenedor como terminado sólo para volverlo inmutable;
6. retira y confirma la ausencia de la revisión en el índice activo;
7. conserva documento, fotografías, colas y journal para auditoría.

Las capturas nuevas guardan de forma aditiva `receivedSha256`, calculado en
streaming sobre los bytes entregados por la cámara antes de normalizar, además
del `sha256` ya existente del JPEG normalizado. Las fotografías legacy siguen
siendo legibles cuando el campo no existe. El cierre inactivo exige ambos
hashes porque sólo puede usar evidencia creada por esta versión o una posterior.

Cancelar antes de tomar una fotografía y sin comentario no produce cambios. Si
la cámara ya entregó evidencia o existe comentario útil, no se permite salir
sin guardar o descartar explícitamente. La revisión permanece editable y el
cierre no ocurre hasta confirmar todos los requisitos.

La repetición del cierre compara `clientInspectionId`, motivo, comentario,
coordenada y timestamp, usuario, dispositivo, IDs y ambos hashes de cada foto,
versión de contrato y clave de idempotencia. Una identidad distinta se rechaza
sin sobrescribir el cierre confirmado.

La UI y las proyecciones usan `RvDraft.localStatus == inactive`, por lo que el
documento no se presenta como una revisión enviada/finalizada normal. El estado
del contenedor no autoriza cambiar `rv.hydrants.is_active` ni
`rv.hydrant_rv_status`.

## Contrato API encontrado

La API actual permite crear inspecciones, guardar respuestas, coordenadas,
señal, válvulas, contenido general, fotografías de slots conocidos y someter la
inspección normal. También contiene un `inactive` global derivado del hidrante
maestro. No existe un DTO, endpoint, slot ni estado de inspección para “no se
encontró hidrante en la coordenada capturada”. La ruta administrativa de
cancelación tampoco representa este resultado.

Por ello esta rama no cambia API, SQL ni contratos compartidos.

## Contrato remoto pendiente

No se propone ni implementa una ruta, DTO, código de dominio o cambio SQL en
esta rama. El contrato canónico debe acordarse y verificarse en una fase de API
separada, con pruebas de compatibilidad para Levantamientos y staging. Hasta
entonces, la app conserva el cierre sólo offline, bloquea todo su pipeline de
sincronización normal y nunca lo marca como confirmado remotamente.
