# Etapa 12.5.2 — Flujo integral, catálogos y envío

## Diagnóstico

- Rama verificada en app y API: `feature/rv-crs-and-catalog-resolution`.
- Ambos repositorios contienen cambios locales previos que se preservan.
- `git diff --check` inicial: sin errores; únicamente avisos LF/CRLF.
- Causa del regreso al paso 1: `DynamicChecklistRenderer` conservaba
  `currentStep = 0` exclusivamente en el `State` del widget. La reconstrucción
  posterior a cámara/galería recreaba ese estado efímero.
- Los pasos 3 en adelante se envolvían en `ExpansionTile`.
- El checklist activo conserva 77 identificadores; la migración incremental v2
  los copia sin renombrarlos.

## Arquitectura

- Flutter: `RvDraft` + `RvDraftRepository` son la fuente persistente; el
  controlador concentra captura y mutaciones; el renderer presenta una sección
  activa; `InspectionSyncCoordinator` ejecuta create/answers/location/signal/
  photos/submit.
- API: Express, Zod, SQL Server 2014, middleware global de autenticación,
  idempotencia y RFC Problem.
- SQL: esquema `rv`, checklist versionado, respuestas tipadas, evidencias,
  auditoría y estados de inspección.

## Inventario de campos afectados (77 reactivos)

Marcas/fabricantes detectados (12):

1. `flow_meter_brand` — medidor/flujómetro.
2. `reg_sust_brand` — válvula reguladora/sostenedora.
3. `reg_sust_solenoid_brand` — solenoide.
4. `air_valve_brand` — válvula de aire.
5. `injector_hydraulic_brand` — válvula hidráulica del inyector.
6. `injector_solenoid_brand` — solenoide del inyector.
7. `filter_brand` — filtro.
8. `filter_drain_brand` — válvula de drenaje.
9. `filter_drain_solenoid_brand` — solenoide de drenaje.
10. `parcel_valve_brand` — válvula parcelaria.
11. `parcel_solenoid_brand` — solenoide parcelario.
12. `parcel_regulating_pilot_brand` — piloto regulador.

Diámetros/medidas nominales detectados (9):

1. `main_manual_valve_diameter`.
2. `flow_meter_diameter`.
3. `reg_sust_diameter`.
4. `air_valve_diameter`.
5. `injector_hydraulic_diameter`.
6. `venturi_diameter`.
7. `user_manual_valve_diameter`.
8. `filter_drain_diameter`.
9. `parcel_valve_diameter`.

## Estrategia

- Persistir `activeFormStep` dentro de `RvDraft`, compatible con borradores
  antiguos mediante valor por defecto cero.
- Al navegar: quitar foco, persistir paso, esperar post-frame, desplazar al
  encabezado y anunciarlo semánticamente.
- Renderizar exclusivamente una sección fija.
- Añadir catálogos locales versionados, selección reutilizable y cola offline.
- Sincronizar catálogos antes de respuestas y reconciliar UUID de cliente.
- Mantener simultáneamente ID de catálogo y valor visible para compatibilidad.
- Conducir el paso 10 al resumen; confirmar explícitamente antes de enviar.

## Migraciones

- Migración incremental, repetible y no destructiva para marcas, diámetros y
  referencias opcionales desde respuestas.
- Unicidad por nombre normalizado/categoría y por valor normalizado/unidad.
- Desactivación lógica; nunca borrado histórico.
- Seed exclusivo de diámetros 3 y 4 pulgadas.
- No se ejecutará ninguna migración ni importación contra producción.

## Riesgos

- Los cambios locales previos se superponen con flujo RV y SQL inicial.
- El checklist de API tiene 9 secciones funcionales aunque la UI denomina el
  recorrido como 10 pasos; pasos 1 y 2 incorporan paneles especializados.
- La validación física depende de dispositivo ADB y de una escena segura.
- Integración SQL depende de la base de pruebas configurada.

## Pruebas

- Dominio/widget: restauración de paso, navegación superior, pasos fijos,
  catálogos, normalización, offline, reconciliación, resumen y envío.
- API: endpoints, filtros, duplicados, idempotencia, desactivación y RFC Problem.
- Comandos obligatorios Flutter y Node 22.
- APK debug e instalación con `adb install -r`; nunca `pm clear`.

## Criterios de aceptación

Se aplican íntegramente los criterios de la instrucción de etapa: persistencia de
paso, scroll superior, ausencia de acordeones, catálogos dinámicos offline,
resumen/confirmación/envío idempotente, suites verdes y cero operaciones
prohibidas.

## Resultado final

- Implementación Flutter/API/SQL y documentación completadas sin aplicar SQL.
- Flutter: format, analyze, 173 pruebas y APK debug aprobados.
- API: lint, type-check, 67 pruebas unitarias y build aprobados.
- Integración SQL: 9 casos omitidos por no estar habilitada la base de pruebas.
- Pixel 7 Pro detectado. `adb install -r` fue rechazado de forma segura porque el
  dispositivo tiene versionCode 8 y el APK generado versionCode 4. No se usó
  `-d`, no se desinstaló y no se borraron datos; validación física pendiente.
- Health no confirmado: API no estaba ejecutándose y el único Node disponible es
  24.17.0. No se dejó un proceso Node 24 activo.
- No hubo importación, `--apply`, envío real, producción, commit, push ni PR.

### Certificación 12.5.2-A

- Versionado corregido a `0.2.1+9`; APK instalado con `adb install -r`.
- Node 22.17.1 y npm 10.9.2 usados en toda la matriz API.
- Migración 04 aplicada dos veces únicamente en `RevisionVisualStarter_Test`.
- 67 unitarias API y 10 integraciones aprobadas sin omisiones.
- Health live/ready: HTTP 200.
- Flutter final: analyze limpio, 173 pruebas y APK aprobados.
- Persistencia de Hive, sesión segura, borradores y fotografías confirmada por
  inventario de datos posterior a actualización.
- Validación manual de UI pendiente: Pixel bloqueado con credencial/biometría y
  sin escena fotográfica segura confirmada.
