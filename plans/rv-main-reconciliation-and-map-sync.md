# Reconciliación RV de `main` y mapa local-first

Fecha de auditoría: 2026-08-07.

## Estado Git y diagnóstico

`origin/main` está en `c01961d` y contiene mejoras recientes de arranque, sincronización de catálogo y mapa que no están completas en la rama RV acumulativa. La rama de trabajo actual `fix/rv-field-anr-local-first-and-session-takeover` contiene 21 commits no presentes en `origin/main` (aproximadamente 8,048 inserciones), incluyendo la cadena RV, procesamiento local-first, takeover, borrado de borradores, preguntas nuevas, firma/icono y compatibilidad. Hay cambios preexistentes no confirmados (`pubspec.lock`, `dist/`, `node_modules/`, `package*.json`); se preservarán y no se incorporarán accidentalmente.

No se hará merge ciego de la rama acumulativa. La reconciliación partirá de `origin/main` y trasladará la implementación final por capacidad, conservando el arranque/mapa nuevo y el takeover acumulativo.

## Matriz de funcionalidades

| Feature | API main | API rama fuente | APP main | APP rama/commit fuente | Acción |
|---|---|---|---|---|---|
| Sesiones permanentes + takeover | Takeover sí | API `main` | No | acumulativa, especialmente `0ff2479` | Portar UI/repositorio y alinear contrato con API autoritativa |
| Exclusividad RV global | No actualmente | API deploy | No | `48c6817` | Portar modelos/CTA/proyección global |
| Versionado inmutable | No | API deploy | No | `f16c4dd` | Portar navegación/modelos sin permitir edición accidental |
| Visor móvil | No | API deploy | No | `c30b026` y correcciones acumulativas | Portar viewer y CTA “Ver reporte” |
| Rangos de presión | No | API deploy | No | `fcc529e` | Reconciliar con formulario actual |
| Marca ilegible | No | API deploy | No | `7c6be55` | Portar sin perder respuestas legacy |
| Filtro indefinido | No | API deploy | No | `8d347ff` | Portar sin perder respuestas legacy |
| Conexión piloto | No | API deploy | No | `4646add` | Portar modelo/UI/tests |
| Fotos generales/observaciones | No | API deploy | No | `2255104` y acumulativa | Portar flujo verificado/local-first |
| Hardening/ANR local-first | Parcial | API main + deploy | No | `aa292e9`, `0ff2479` | Portar implementación final y preservar responsividad |
| Borrado de borrador/dashboard | API no debe borrar reporte | API reconciliada | No | `6a44d53` | Corregir eliminación transaccional de todas las proyecciones y startup reconciliation |
| Arranque/snapshot mapa | API por integrar | API deploy | Sí, versión más reciente | `origin/main` (`e63d181`..`c01961d`) | Conservar como base y extender a catálogo completo/incremental |
| Icono/preguntas recientes | API main contiene contrato reciente | API main | No | `2985455`, `158ffb2` | Portar versión final compatible |

## Arquitectura local-first del mapa

- Persistencia local versionada del catálogo mínimo completo: ID, cuenta, coordenadas, estado RV global, reporte actual, validación, cambio de estado y versión/cursor.
- Render inmediato desde Hive/cache al abrir o reiniciar offline; la red nunca bloquea el primer render si hay snapshot.
- Snapshot completo solo con caché inexistente/incompatible o cursor inválido.
- Cambios incrementales en background al iniciar sesión, recuperar conexión estable, abrir mapa con TTL vencido, sincronizar una revisión o refrescar manualmente.
- Upsert por páginas y una sola notificación por lote; sin HTTP por marcador, fotos o checklist.
- TTL configurable y exclusión mutua para impedir descargas duplicadas por rebuild.
- Para 1,400–2,500 puntos: índices/mapas O(N), construcción por lotes y evaluación de clustering solo si las mediciones lo justifican.

## Proyección única de estado

Se implementará una función pura compartida:

`remoteGlobalState + localDraftState + syncQueue = HydrantDisplayState`

Prioridad inicial: conflicto/validado/reporte oficial remoto prevalece sobre borradores locales obsoletos; un borrador propio vigente permite continuar; operaciones locales válidas pendientes muestran “Sin sincronizar”. Home, listas, mapa, recientes y CTA consumirán la misma proyección.

## Eliminación segura de borradores

La operación coordinará draft, journal/cola de sync, cola multimedia solo local, índices, cachés y contadores. No borrará fotos/reportes remotos confirmados. Al arrancar se reconciliarán referencias huérfanas conservadoramente: una operación sin draft ni entidad válida se cancela/retira de vistas; evidencia con referencia remota se conserva. Tras borrar un draft con reporte remoto, reaparece la proyección remota.

“Revisiones recientes” contendrá entidades vigentes, no historial de objetos eliminados. “Sin sincronizar” requerirá una operación vigente y su entidad local válida.

## Secuencia de implementación y validación

1. Crear rama `fix/rv-main-reconciliation-and-map-sync` desde `origin/main`, preservando cambios locales preexistentes fuera del commit.
2. Portar modelos/contratos RV y takeover por feature, no por merge masivo.
3. Integrar proyección global y viewer; cambiar CTA según estado.
4. Corregir borrado/reconciliación de colas, recientes y contadores.
5. Completar cache snapshot/incremental y actualización de mapa en background.
6. Agregar pruebas A-G solicitadas, compatibilidad offline, 2,500 puntos y no regresión de takeover.
7. Ejecutar formato, análisis y suite completa.

## Riesgos conocidos antes de implementar

- La rama acumulativa y `origin/main` modifican simultáneamente bootstrap, repositorio de hidrantes, mapa y estado global; requieren resolución semántica.
- Los cambios locales preexistentes no pertenecen automáticamente a esta tarea y deben mantenerse fuera de commits.
- Borrar referencias multimedia exige distinguir evidencia exclusivamente local de contenido remoto confirmado.
- Un draft local antiguo no puede ocultar un reporte oficial remoto más reciente.
- El endpoint incremental debe representar inactivaciones/eliminaciones para evitar marcadores fantasma.

## Informe final

### Resultado

- Se partió de `origin/main`, preservando su bootstrap y sincronización reciente, y se recuperaron individualmente status global, versionado, viewer, catálogos/campos RV, fotos generales, hardening, takeover, evidencia del medidor y administración de borradores.
- Un hidrante oficial deriva CTA de consulta y abre el reader; no se ofrece revisión normal nueva. El dashboard agrupa por hidrante y evita duplicar conteos.
- El borrado verifica creador y ausencia de `serverInspectionId` antes de tocar evidencia; limpia documento, índices, sync queue, media queue y journal. Nunca borra reporte/foto remota confirmada.
- Se corrigió la ruta de cierre normal/pending logout: ahora usa `/field-sessions/{id}/end` con el access token de esa sesión. Takeover continúa usando exclusivamente `/field-sessions/revoke-existing` y no borra almacenamiento local.
- El mapa renderiza inmediatamente la caché completa. El snapshot inicial persiste cursor; después usa feed incremental `scope=all`, páginas de 500, upsert por lote, retiro de inactivos, una invalidación de caché y TTL de 15 minutos.
- Reiniciar offline conserva todos los puntos. No hay HTTP por marcador ni descarga de checklist/fotos en el mapa.
- `CachedHydrant` conserva ahora el timestamp canónico del servidor, necesario para cursor y precedencia global.

### Proyección y prioridad

La proyección global recuperada se consume en modelo de hidrante, navegación, mapa y dashboard. Reporte remoto validado/completado/conflicto prevalece en la disponibilidad; un borrador propio activo permite continuar; una operación vigente pendiente produce “Sin sincronizar”. Los conteos usan sets por `hydrantId` para impedir duplicados.

### Pruebas

- Hidrante revisado por otro: proyección global + viewer y CTA cubiertos.
- Borrado/contadores/CTA: `rv_operational_hardening_test` y `rv_work_dashboard_projection_test`.
- Snapshot, reinicio offline y cambio incremental de available a validated: `cache_repositories_test`.
- Session takeover estructurado y conservación local: `session_takeover_contract_test`.
- Suite completa: 308 pruebas correctas.
- `flutter analyze`: sin hallazgos.
- `dart format --set-exit-if-changed .`: correcto.

### Riesgos residuales

- Falta smoke/integration test en dispositivo con 2,500 marcadores y API/SQL de staging reales.
- El cursor depende de timestamps monotónicos del servidor; si una importación modifica filas sin actualizar timestamp canónico, requerirá refresh completo explícito.
- Los artefactos locales preexistentes (`dist`, APK, `node_modules`, `package*.json`) quedaron fuera de commits.
- El `pubspec.lock` preexistente está preservado en `stash@{0}` con mensaje `preserve-preexisting-pubspec-lock-before-rv-reconciliation`; no pertenece a esta reconciliación.

### Archivos y commits

La rama es `fix/rv-main-reconciliation-and-map-sync`. Los commits recuperados quedaron aplicados individualmente (`1fee9f9` a `4cbafc0`) y el cierre incremental se confirma junto con este plan. El inventario exacto se obtiene con `git diff --name-only origin/main...fix/rv-main-reconciliation-and-map-sync`. No se hizo push ni merge.
