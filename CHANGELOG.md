# Changelog

Todos los cambios notables de **DIAGNOSTICO HIDRANTES** se documentan aquí.

## Unreleased — Etapa 3

- Etapa 5B divide Componentes internos de REPORTE VISUAL en listas independientes de red pública y red privada, elimina el esquema productivo y amplía el flujo de ocho a nueve pasos con adaptación legacy idempotente.
- Los pasos 5 y 6 funcionan como subasistentes secuenciales por componente, con defaults favorables no confirmatorios, índice, recuperación de posición, resumen previo y confirmación explícita trazable.
- El esquema de RV ahora representa espacialmente gabinete, redes pública/privada, tuberías, filtro y salidas dinámicas mediante un lienzo interactivo accesible.
- Los fondos del esquema RV usan assets WebP optimizados A1–A5 sin marcas; los estados y la interacción permanecen como overlays Flutter y el esquema dibujado se conserva solo como fallback.
- RV conserva el medidor como fuente canónica del paso 4, añade compatibilidad read-old/write-new y protege reportes finalizados.
- Se incorporan validación por componente, evidencia condicional y revisión rápida sin sobrescritura.
- Etapa 4D incorpora infraestructura de pruebas unitarias, dominio, serialización, Hive, recuperación, medios, widgets, MethodChannel e integración offline previa a DDR001 API.
- Se agregan fixtures, fakes, entorno Hive temporal, matriz P0/P1/P2 y guía reproducible de ejecución; las suites quedan pendientes de ejecución manual por restricción de esta intervención.
- El adaptador celular admite inyección controlada del canal y plataforma para probar el contrato sin alterar la implementación Android ni realizar conexiones reales.
- Etapa 4C completa editores UUID para válvulas/pruebas, corridas, alarmas e instrumentos con historial, invalidación y evidencia.
- Se agrega resolución verificable de revisiones RV/RF, recuperación por fases, regeneración de miniaturas y detección segura de huérfanos.
- Perfil incorpora auditoría técnica restringida con reparaciones conservadoras y exportación; galería añade métricas y posición persistida.
- Etapa 4C liga una prueba HTTPS mínima a un `Network` celular Android y separa capacidades INTERNET/VALIDATED del resultado HTTP.
- La evaluación Wi-Fi permanece manual y ahora aplica ramas condicionales con normalización persistida y validación central.
- Etapa 4B agrega máquina de estados común, inmutabilidad y revisiones para RV/RF.
- Se incorporan journal recuperable, auditor de integridad, cuarentena y recuperación conservadora al arranque.
- RF incorpora colecciones UUID de válvulas, corridas de reductora y alarmas, snapshots de instrumentos y resultado agregado.
- Medios incorporan reconciliación; galería aísla corrupción, conserva filtros y carga miniaturas incrementalmente.
- Nuevo levantamiento RV + RF queda coordinado mediante journal; sincronización local prepara idempotencia y dependencias para una API futura.
- Diagnóstico automático limitado a GPRS/red celular, con contador máximo de 60 segundos y resultados diferenciados.
- Evaluación Wi-Fi manual mediante respuestas explícitas, sin escaneo de redes ni permisos adicionales.
- Etapa 4 inicia estabilización local: respuestas trivalentes RV persistentes, ubicación automática, diagnóstico de red parcial honesto, resolución central de RV finalizado, navegación RF y traducciones visibles.
- Evidencia por sección incorpora contador reutilizable y daños visibles incorpora evaluación individual por componente.
- Inicio recupera el Resumen de jornada compacto de cuatro métricas con reglas compartidas con Hidrantes.
- La alerta de Inicio ahora responde en toda su superficie y abre detalle o ficha según su relación.
- La barra principal se simplifica a Todos, RV, RF, En proceso, Sin sincronizar y Finalizado.
- El chip activo se centra mediante un controlador horizontal y medición real del viewport antes de consumir la solicitud.
- REPORTE FUNCIONAL offline en diez pasos con borrador, suspensión y visita sin prueba.
- Habilitación funcional explícita y Nuevo levantamiento con RV, RF o RV + RF.
- Instrumentos, series versionadas, unidades normalizadas y tolerancias DEMO no oficiales.
- Pruebas hidráulicas, mecánicas, eléctricas, comunicaciones, alarmas y fugas.
- Evidencia funcional sobre el pipeline fotográfico existente.
- Filtros RV/RF y visibilidad automática del chip solicitado desde Inicio.
- Cajas Hive no destructivas, cola tipada y trazabilidad funcional ampliada.

## Unreleased — Etapa 1.1

- Navegación horizontal entre secciones y control jerárquico de Atrás con `PopScope`.
- Sincronización incremental simulada de asignaciones, con upsert y retiros protegidos.
- Etiquetas cortas permanentes en los marcadores del mapa demo.
- Estado global corregido para diagnósticos, fotografías, trazabilidad y errores.
- Simulación controlada de actualización disponible, opcional, obligatoria y error.
- Base para consultar un manifiesto remoto con fallback local.

## [0.2.0+3] - 2026-07-13

- Base arquitectónica móvil y tema centralizado.
- Acceso demo, navegación principal y pantallas generales de Etapa 1.
- Datos simulados para hidrantes RV y RF.
- Trazabilidad y cola de sincronización local mediante Hive CE.
- Mapa visual simulado sin SDK cartográfico.
- Base segura para actualización y evidencias fotográficas.

## [0.1.1+2]

- Proyecto Flutter inicial.
## Unreleased — Etapa 2

- Navegación anidada por ramas y protección del botón Atrás.
- Sincronización compacta y cíclica de asignaciones.
- Borradores versionados de REPORTE VISUAL en ocho pasos.
- Captura GPS contextual y conversión local WGS84 a UTM.
- Flujo local para hidrantes no asignados y encontrados en campo.
- Pipeline fotográfico normalizado, almacenamiento privado, SHA-256 y cola pendiente.
- Galería local por hidrante y trazabilidad ampliada.
