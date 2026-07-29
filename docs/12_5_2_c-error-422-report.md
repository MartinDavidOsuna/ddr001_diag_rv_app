# Etapa 12.5.2-C — Certificación del error 422

Fecha: 2026-07-27  
Rama: `feature/rv-crs-and-catalog-resolution`

## Causa y RFC Problem

El request original no conservó `x-request-id` ni el cuerpo porque el cliente
anterior solo registraba `ERROR 422`. La reproducción equivalente quedó como:

```text
requestId=stage-12-5-2-c-ab2223e0-a5a2-4a1c-8190-14e03e8e70ff
inspection=D049EE75-02CA-4553-8E89-AA8352B4E2EF
```

```json
{
  "type": "https://rvs.example/problems/invalid-answer",
  "title": "Invalid answer",
  "status": 422,
  "detail": "main_manual_valve_diameter: type",
  "instance": "/api/v1/inspections/D049EE75-02CA-4553-8E89-AA8352B4E2EF/answers",
  "requestId": "stage-12-5-2-c-ab2223e0-a5a2-4a1c-8190-14e03e8e70ff",
  "errors": [{
    "path": ["answers", 0, "value"],
    "code": "invalid_answer_type",
    "expected": "decimal",
    "received": "string",
    "message": "type"
  }]
}
```

Payload anterior sanitizado:

```text
questionId=main_manual_valve_diameter
answerType=decimal
serializedValueType=String
valueShape=displayValue (3")
diameterIdPresent=true
```

La causa fue convertir todo mapa de catálogo a `displayValue`. Checklist y Zod
requieren número para `decimal`. El lote genérico incluía además reactivos
planos heredados del paso 8 y los diámetros derivados usaban IDs ficticios.

## Contrato corregido

| Capa | Marca | Diámetro |
|---|---|---|
| Flutter | texto + `brandId` remoto | número + `diameterId` remoto |
| Zod | objeto estricto, sin campos locales | objeto estricto, sin campos locales |
| SQL | `value_text`, `brand_id` | `value_number`, `diameter_id` |

El coordinador sincroniza catálogos, reconcilia IDs en respuestas y válvulas y
bloquea la llamada si queda una referencia local. `valvulas_parcelarias` se
excluye de `/answers` y va por `/parcel-valves`. Los diámetros derivados 3 y 4
pulgadas conservan los UUID seed y el número normalizado.

El cliente interpreta RFC Problem y registra únicamente status, método, path,
request ID, type, title, detail y errores sanitizados. La API registra path,
code, expected, received y message, sin cuerpo, token, fotos ni datos personales.

- 400/422: sin reintento automático.
- 401/403: autenticación/autorización.
- 408/429/5xx/red: reintento controlado.
- 409: conflicto/idempotencia.

## Certificación

- Flutter: format/analyze aprobados; 184 pruebas aprobadas. La corrida final
  completa se ejecutó con `--concurrency=1` tras aislar un timeout de cierre Hive
  que no se reprodujo focalmente.
- APK: `0.2.1+11`, build debug aprobado.
- API: Node `v22.17.1`, npm `10.9.2`; lint, type-check, 81 unitarias,
  10 integraciones y build aprobados.
- Fixture: 422 reproducido; `/answers` 200 corregido; `/parcel-valves` 200;
  siete fotos; submit 200; segundo submit 409; sin duplicado; fixture limpiada.
- Se corrigieron también parámetros SQL display no enlazados en
  `/parcel-valves` y una PK mal nombrada durante submit.
- API: PID 15192, puerto 3000, Node 22.17.1.
- `health/live`: HTTP 200 `{"status":"ok"}`.
- `health/ready`: HTTP 200; database, storage y configuration `ok`.

## Android

`adb install -r` actualizó Pixel 7 Pro de versionCode 10 a 11 sin desinstalar ni
limpiar. `firstInstallTime` se conservó. Hive, colas, catálogos y fotos siguen
presentes; `d272d28e` conserva siete originales y miniaturas.

El Pixel estaba bloqueado por credencial. No fue posible abrir la UI ni pulsar
sincronización, no se intentó sortear el bloqueo y no se confirmó envío físico.
Queda repetir, con el equipo desbloqueado, la sincronización sin submit.

No se usaron importadores, producción, commit, push ni PR.
