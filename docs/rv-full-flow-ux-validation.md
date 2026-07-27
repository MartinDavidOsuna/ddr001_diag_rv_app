# Validación UX del flujo RV

El paso activo dejó de ser estado efímero del widget y ahora se persiste como
`activeFormStep` en `RvDraft`. Cámara y galería conservan inspección, paso,
respuestas y fotografías; los logs debug muestran paso anterior/posterior, slot,
ID abreviado y restauración, sin rutas ni contenido de imagen.

La navegación quita foco antes de persistir el nuevo paso y usa callback
post-frame con `Scrollable.ensureVisible` sobre el encabezado. El encabezado se
anuncia semánticamente. Los botones permanecen al final del contenido desplazable.

Cada sección activa es fija. Los pasos 3 al 10 ya no usan `ExpansionTile` ni
renderizan secciones adyacentes. El último paso abre `Resumen de inspección`.

Automatización: `flutter analyze` y 173 pruebas aprobadas. La validación física se
documenta por separado y no autoriza enviar una inspección real.

## Certificación 12.5.2-A

La suite final completa volvió a aprobar con 173 pruebas. El APK versionCode 9 se
instaló conservando datos. La inspección interactiva de pasos, foco, scroll,
cámara y galería quedó pendiente porque el dispositivo estaba bloqueado.
# Actualización 12.5.2-B

El paso 8 dejó de usar respuestas planas y ahora muestra de una a tres
válvulas con datos individuales. La navegación desde pendientes persiste un
destino estable y hace scroll al control exacto después del render. La
certificación automatizada fue aprobada; la repetición física interactiva
quedó pendiente porque el Pixel estaba bloqueado.

## Navegación unificada y cierre

El índice persistente continúa gobernado por `RvInspectionController`. Los
botones, la flecha del encabezado y el gesto horizontal llaman ahora
`goToNextStep`/`goToPreviousStep`; Android y el gesto de regreso comparten la
confirmación de salida del paso 1 mediante `PopScope`.

`RvSwipeNavigationDetector` exige distancia o velocidad horizontal, deja que el
arena de gestos entregue el scroll vertical y los controles horizontales a sus
descendientes, y bloquea una segunda navegación mientras la primera transición
está activa. El resumen no instala este detector.

Después del submit, el éxito se presenta únicamente cuando estado local y
remoto son `submitted`. Una compuerta consumible evita diálogos duplicados. Al
aceptar se limpia el navegador de la rama de hidrantes y se regresa a Inicio.
