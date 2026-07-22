# Navegación de inspecciones

Los formularios de REPORTE VISUAL y REPORTE FUNCIONAL usan una ruta con estado de paso y un borrador persistente por inspección.

- Atrás vuelve al paso anterior; desde el paso 1 vuelve a la ficha.
- Si el paso tiene cambios sin guardar, `PopScope` solicita confirmación.
- Confirmar salida nunca elimina el borrador local.
- El swipe izquierdo no avanza. El único avance válido es **Guardar y continuar**.
- El swipe derecho equivale a Atrás, excepto en las franjas laterales reservadas por Android.
- Durante una inspección no se permite cerrar silenciosamente la aplicación.
- Una actualización obligatoria permite consultar inspecciones existentes y sincronizar, pero impide iniciar o editar diagnósticos nuevos.

El placeholder de Etapa 1.1 implementa estas reglas para validar el comportamiento antes de incorporar los formularios.
