# Etapa 12.5.2-B — Informe de certificación

Fecha: 2026-07-25. Rama: `feature/rv-crs-and-catalog-resolution`.

## Diagnóstico y correcciones

- El catálogo global se originaba en dos comodines: Flutter incluía marcas
  `generic` en toda consulta y API consultaba `category IN(tipo, generic)`.
  Se eliminó ese comportamiento y se adoptó `elementType` exacto.
- Los 21 pendientes observados eran principalmente selecciones de catálogo
  guardadas como mapas (`catalogId`, `localCatalogId`, `displayValue`) que el
  validador seguía tratando como `String` o `num`. El contrato y el validador
  ahora aceptan ID remoto, ID local pendiente o valor histórico compatible.
  Pendiente de sincronización no equivale a respuesta faltante.
- El paso 8 era un grupo plano para una sola marca/diámetro. Ahora persiste
  `ParcelValveConfiguration` y una lista estable de válvulas indexadas.

## Datos, API y sincronización

- Tipos estables: `VALVE`, `SOLENOID`, `FILTER`, `PILOT`,
  `PRESSURE_GAUGE`, `FLOW_METER`, `REGULATING_VALVE`,
  `COMMUNICATION_DEVICE`, `POWER_DEVICE`, `OTHER`.
- Migración: `database/05_typed_brands_and_parcel_valves.sql`.
  Se ejecutó dos veces únicamente en `RevisionVisualStarter_Test`
  (`WIN-5RQE8N8NQ9V`) con resultado idempotente.
- Tablas nuevas: `rv.brand_element_types`,
  `rv.inspection_parcel_valve_configurations`,
  `rv.inspection_parcel_valves`. La última aplica unicidad por
  `inspection_id + valve_index`.
- Las marcas heredadas solo se clasifican cuando su categoría es inequívoca.
  Las genéricas permanecen sin clasificación y no aparecen en selectores
  tipificados. En el preflight final no quedaron marcas sin clasificar.
- `GET /catalogs/brands` requiere `elementType`; `POST` requiere
  `clientUuid`, nombre y tipo. La normalización es por nombre y tipo.
- `PUT /inspections/:id/parcel-valves` valida configuración, índices, IDs y
  pertenencia exacta de cada marca al tipo del componente.
- Orden aplicado en cliente: catálogos, reconciliación de IDs, respuestas,
  válvulas individuales y después fotografías/envío.

## Paso 8 y resumen

- Botones: `1 de 3"`, `2 de 3"`, `3 de 3"`, `3 de 4"`, `Otro`.
- Las opciones conocidas derivan y persisten el diámetro por válvula.
  `Otro` exige descripción, cantidad entre 1 y 3 y diámetro individual.
- Cada válvula registra marca, diámetro, y existencia/marca de solenoide,
  piloto y manómetro con catálogo tipificado.
- Reducir la cantidad exige confirmación y conserva trazabilidad local de
  válvulas retiradas; aumentar conserva la válvula 1.
- El resumen muestra cada válvula estructurada. Los pendientes contienen
  `sectionId`, `questionId`, `subItemId` y `fieldId`, navegan mediante una
  llave estable al control y habilitan `Volver al resumen`.
- `formatPersonName()` normaliza únicamente la presentación de nombres,
  incluidos espacios, acentos, guiones y apóstrofes.

## Certificación

- Flutter: formato correcto; `flutter analyze` sin hallazgos; 179/179
  pruebas; APK debug generado.
- API con Node `v22.17.1`, npm `10.9.2`: lint, type-check, 80/80 unitarias,
  10/10 integración y build aprobados.
- Health PID 19620, Node 22: `/health/live` 200 y `/health/ready` 200;
  database, storage y configuration `ok`.
- APK `0.2.1+10`: `adb install -r` exitoso en Pixel 7 Pro; package
  `com.aquafim.ddr001diag`; 157 archivos privados permanecen después de la
  actualización, sin `pm clear` ni desinstalación.

## Validación física pendiente

El teléfono estaba bloqueado (`NotificationShade` como ventana enfocada).
Se certificaron instalación, proceso y conservación física de datos, pero no
fue posible operar el flujo visual, cámara, galería, offline ni resumen. No se
tomó fotografía al no poder comprobar una escena segura y no se envió ninguna
inspección física. Este pendiente impide declarar cierre físico total.

No se ejecutaron importadores, `--apply`, producción, commit, push ni PR.
