# Matriz manual — Etapa 5B RV

| ID | Caso | Precondición | Resultado esperado | Severidad | Estado |
|---|---|---|---|---|---|
| RV5-01 | Abrir A1/A2/A3/A4 | Borrador por tipo | 21/25/29/29 elementos y salidas correctas | P0 | Pendiente |
| RV5-02 | Alternar esquema/lista | Paso 5 abierto | Mismo estado y conteos en ambas vistas | P0 | Pendiente |
| RV5-03 | Editar componente | Componente pendiente | Resumen, pendiente y hallazgo se actualizan | P0 | Pendiente |
| RV5-04 | Medidor desde esquema | Paso 4 incompleto/completo | Abre resumen y acción al paso 4, sin duplicar datos | P0 | Pendiente |
| RV5-05 | Evidencia obligatoria | Hallazgo importante | No avanza sin foto válida del componente | P0 | Pendiente |
| RV5-06 | Revisión rápida | Mezcla de estados | Solo cambia elegibles y muestra alcance | P0 | Pendiente |
| RV5-07 | Borrador heredado | Documento schema 1 | Muestra aviso y exige confirmación individual | P0 | Pendiente |
| RV5-08 | RV finalizado | Reporte completado | Lectura sin escrituras ni edición | P0 | Pendiente |
| RV5-09 | Foto y regreso | Cámara/galería disponible | Conserva paso, vista y componente; contador se actualiza | P1 | Pendiente |
| RV5-10 | Texto 2× y pantalla pequeña | Escala 2.0 | Sin overflow; acciones accesibles | P1 | Pendiente |
| RV5-11 | TalkBack | TalkBack activo | Marcadores anuncian nombre y estado | P1 | Pendiente |
| RV5-12 | Cierre forzado | Cambios guardados | Recupera configuración, componentes y fotos | P0 | Pendiente |
| RV5-13 | A5 Custom | Permiso de edición | Agrega/retiro lógico sin perder historial | P1 | Pendiente |
| RV5-14 | Esquema espacial A1–A5 | Paso 5 abierto | Se reconocen gabinete, dos redes, filtro, tuberías y ramas correctas | P0 | Pendiente |
| RV5-15 | Zoom y desplazamiento | Esquema abierto | Acercar, alejar, pan y restablecer conservan selección y estado | P1 | Pendiente |
| RV5-16 | Fondos raster A1–A5 | Cada tipo activo | Carga solo el WebP correspondiente, sin marcas visibles y con overlays alineados | P0 | Pendiente |
| RV5-17 | Falla de asset | Asset temporalmente ausente | Muestra esquema básico, mensaje controlado y permite usar Lista | P1 | Pendiente |
| RV-L01 | RV | Borrador legacy en paso 6 | Abrir borrador | Abre Energía y comunicaciones como paso 7 una sola vez | S1 | Pendiente |
| RV-L02 | RV | Borrador legacy en pasos 7/8 | Abrir dos veces | Abre pasos 8/9 y no vuelve a desplazar | S1 | Pendiente |
| RV-L03 | RV | Reporte legacy finalizado | Abrir en lectura | No cambia paso, versión, UUID, fechas ni fotos | S1 | Pendiente |
| RV-P05 | RV | A1–A5 configurado | Abrir paso 5 | Lista Red pública en orden técnico; medidor enlaza paso 4 | S1 | Pendiente |
| RV-P06 | RV | A1–A5 configurado | Abrir paso 6 | Red privada y salidas separadas con diámetro correcto | S1 | Pendiente |
| RV-N09 | RV | Pasos anteriores completos | Recorrer 4→5→6→7 y volver | Navegación, guardado y progreso de nueve pasos coherentes | S1 | Pendiente |
| RV-A11 | RV | Texto del sistema a 200 % | Abrir pasos 5 y 6 | Sin desbordes; filas y controles utilizables | S2 | Pendiente |
| RV-W01 | RV | Componente nuevo | Abrir ficha y salir | Defaults favorables visibles; sigue Sin confirmar y sin reviewedAt | S1 | Pendiente |
| RV-W02 | RV | Componente nuevo | Confirmar componente | Guarda actor/fecha/confirmación y avanza | S1 | Pendiente |
| RV-W03 | RV | Default instalado/bueno | Cambiar presencia a No | Limpia Bueno y condiciones incompatibles; exige motivo/foto | S1 | Pendiente |
| RV-W04 | RV | Default sin daño | Seleccionar hallazgo | Retira Sin daño visible y muestra campos condicionales | S1 | Pendiente |
| RV-W05 | RV | Subasistente intermedio | Atrás, índice, cerrar y reabrir | Conserva datos e índice activo sin confirmar implícitamente | S1 | Pendiente |
| RV-W06 | RV | Último componente confirmado | Continuar | Muestra resumen antes de completar la red | S1 | Pendiente |
| RV-W07 | RV | A1/A2/A3/A4/A5 | Recorrer red privada | Totales 11/15/19/19/dinámico y salidas separadas | S1 | Pendiente |
