# Etapa 12.5.2-C — Error 422 en sincronización de respuestas

## Diagnóstico inicial

- Borrador local: `d272d28e-066e-47a8-8f40-fee491889dcc`.
- Inspección remota de pruebas:
  `D79DCB89-961C-4725-9441-38AB483B511D`, estado `in_progress`.
- La transacción `/answers` se revirtió: cero respuestas quedaron persistidas.
- Flutter convertía cualquier mapa de catálogo a `displayValue`. Esto era
  correcto para marcas (`text`), pero convertía diámetros `decimal` en una
  cadena como `3"`; `validateAnswer()` exige un número.
- El generador también recorría los reactivos planos heredados del paso 8,
  aunque las válvulas ya tienen el endpoint normalizado `/parcel-valves`.
- Los diámetros derivados del paso 8 usaban IDs locales artificiales
  `seed-3-in`/`seed-4-in`, que no podían reconciliarse con SQL.
- El cliente descartaba `detail`, `errors` y `x-request-id`, mostrando
  solamente “Error de validación”.

## Contrato comparado

| Concepto | Flutter anterior | Zod/servicio | SQL |
|---|---|---|---|
| marca | `displayValue` + `brandId` opcional | `value` texto, UUID opcional | `value_text`, `brand_id` |
| diámetro | `displayValue` texto | `value` numérico, UUID opcional | `value_number`, `diameter_id` |
| ID local | podía quedar sin reconciliar | no admitido | UUID remoto requerido |
| válvulas | reactivos planos y estructura | endpoints separados | respuestas + tablas normalizadas |

## Estrategia

1. Constructor único y probado del payload general.
2. Excluir `valvulas_parcelarias` de `/answers`.
3. Prevalidar tipos e IDs remotos antes de red.
4. Persistir UUID reales para diámetros derivados 3/4.
5. Interpretar y registrar RFC Problem sanitizado.
6. No reintentar un 400/422 sin cambios en el borrador.
7. Validar referencias y tipos de catálogo en API.
8. Reproducir con fixture sintética y certificar suites completas.

## Riesgos

- El borrador físico se conserva y no se enviará.
- Toda prueba de envío usa fixtures en `RevisionVisualStarter_Test`.
- Las marcas históricas textuales siguen siendo compatibles; solo los mapas
  de catálogo nuevos requieren reconciliación.

## Resultado final

Completado en código y fixture sintética el 2026-07-27. La causa exacta fue
`main_manual_valve_diameter`: Flutter enviaba `3"` como `String` para un
reactivo Zod `decimal`.

Flutter quedó con 184 pruebas, analyze y APK `0.2.1+11` verdes. API quedó con
81 unitarias, 10 integraciones, lint, type-check y build verdes en Node
22.17.1. La fixture validó `/answers` 200, `/parcel-valves` 200 y submit
idempotente.

La actualización preservó Hive y siete fotos de `d272d28e`. La prueba UI final
quedó pendiente porque el Pixel estaba bloqueado por credencial; no se envió
ninguna inspección física. Véase `docs/12_5_2_c-error-422-report.md`.
