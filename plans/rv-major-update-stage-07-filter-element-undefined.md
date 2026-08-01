# Etapa 07 — Captura Indefinido en elemento filtrante

## 1. Objetivo y estado actual

La pregunta RV `filter_element` (“Tiene elemento filtrante.”) usaba el renderer booleano. Ahora usa un control de tres estados y un motivo condicionado. RF permanece intacto.

| Aspecto | Estado anterior | Cambio implementado |
|---|---|---|
| Código | `filter_element` | Sin cambio |
| Etiqueta | Tiene elemento filtrante. | Sin cambio |
| Tipo | Booleano dinámico | Selector especializado Sí/No/Indefinido |
| Persistencia | `bool` en borrador | Objeto `{state, reason}` compatible con bool legacy |
| Dependencias | Comparación directa con `true` | Solo `present` equivale a true |
| Validación | Respuesta requerida | Motivo trim de 10–500 para Indefinido |
| Resumen | Sí/No | Indefinido incluye motivo |
| Visor | Valor genérico | Etiqueta española sin código técnico |

## 2. Estados y dependencias

- `present`: Sí, muestra y exige los campos técnicos actuales.
- `absent`: No, oculta los dependientes y limpia motivo activo.
- `undefined`: Indefinido, muestra motivo y oculta dependientes sin convertirse en No.
- Ausente: No capturado.

```mermaid
flowchart LR
  S[Sí] --> D[Mostrar dependencias]
```

```mermaid
flowchart LR
  N[No] --> H[Ocultar dependencias] --> C[Limpiar motivo]
```

```mermaid
flowchart LR
  U[Indefinido] --> M[Motivo multilínea] --> V[Validar 10–500]
```

```mermaid
flowchart TD
  E{Estado restaurado} -->|present| P[Dependencias activas]
  E -->|absent| A[Dependencias inactivas]
  E -->|undefined| U[Inactivas; identidad conservada]
```

## 3. Modelo Flutter y compatibilidad legacy

`FilterElementSelection` contiene el enum interno `present`, `absent`, `undetermined`; este último serializa `undefined`. `true` y `false` legacy se restauran como present y absent; null sigue sin respuesta. Sí/No siempre serializan motivo nulo.

## 4. Renderer, validación y resumen

El renderer dinámico detecta exclusivamente `filter_element`, usa `SegmentedButton`, muestra un `TextFormField` accesible con contador máximo y autoguarda cada cambio. El validador genera `filter_element_reason_missing` y conserva la sección/ítem para navegación desde pendientes. No existe cámara, evidencia ni slot fotográfico.

```mermaid
flowchart LR
  UI[Selector] --> C[Controlador] --> B[Borrador]
  B --> R[Resumen/pending]
```

```mermaid
flowchart TD
  F[Finalizar] --> Q{Indefinido?}
  Q -->|No| OK[Continúa]
  Q -->|Sí| L{Motivo válido?}
  L -->|No| P[Pendiente navegable]
  L -->|Sí| OK
```

## 5. Offline y sincronización

El objeto vive en la persistencia existente del borrador y no requiere catálogo ni fotografía. Los fallos temporales conservan estado/motivo; el payload builder lo envía con la siguiente sincronización y un conflicto de versión conserva la propuesta.

```mermaid
sequenceDiagram
  participant T as Técnico
  participant A as App
  participant B as Borrador
  T->>A: Elige Indefinido y escribe
  A->>B: Autoguarda offline
```

```mermaid
sequenceDiagram
  participant B as Borrador
  participant S as Sync
  participant API
  B->>S: filterElement
  S->>API: Snapshot/answer
  API-->>S: Confirmación
```

## 6. Versionado, visor y analítica

Una edición sincronizada usa el flujo inmutable existente. Versiones anteriores conservan estado/motivo y una revisión validada permanece bloqueada. El visor recibe `displayValue` y observación legible. El estado estructurado habilita analítica separada Sí/No/Indefinido/No capturado.

```mermaid
flowchart LR
  V1[Snapshot 1] --> E[Editar] --> V2[Snapshot 2]
  V1 -. preservado .-> H[Historial]
```

```mermaid
flowchart LR
  L[Legacy bool] -->|true| P[present]
  L -->|false| A[absent]
  L -->|null| N[No capturado]
```

## 7. Pruebas, riesgos y despliegue

Se prueban estados, legacy, límites, limpieza de motivo, renderer RV, payload y ausencia de integración RF/fotográfica. Riesgos: clientes antiguos no capturan Indefinido y el backend debe desplegarse con su migración antes de depender del nuevo estado.

```mermaid
sequenceDiagram
  participant API
  participant DB
  participant APP
  API->>DB: Aplicar migraciones revisadas
  API->>API: Desplegar compatibilidad
  API->>APP: Distribuir app después
```

Pendiente: ensayo acumulado en SQL Server 2014, smoke test de dependencias y despliegue futuro.

## 8. Dependencias para Prompt 8

La especialización queda limitada a `filter_element`; la pregunta de pilotos conectados puede implementar su propio contrato sin heredar Indefinido ni alterar RF.
