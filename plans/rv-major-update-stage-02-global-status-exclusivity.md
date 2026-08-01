# Etapa 02: consumo del estado RV global

## Arquitectura implementada

`CachedHydrant` conserva la proyección canónica recibida del servidor; `Hydrant` la expone a lista y mapa. `RvDraft` mantiene el estado local y ahora persiste las referencias de oficial y conflicto. Los JSON legacy usan valores seguros sin migración destructiva de Hive.

```mermaid
flowchart LR
  API[Proyección API] --> C[CachedHydrant / Hive]
  C --> G[Estado global]
  D[RvDraft del usuario] --> L[Estado local]
  G --> U[Lista y mapa]
  L --> U
```

## Submit y conflicto

```mermaid
sequenceDiagram
  participant App
  participant API
  participant Hive
  App->>API: submit completo
  API-->>App: official / already_official
  App->>Hive: submitted + officialInspectionId
  App->>API: refrescar proyección en sincronización posterior
```

```mermaid
sequenceDiagram
  participant A as Técnico A
  participant API
  participant B as Técnico B
  par submits concurrentes
    A->>API: submit A
    B->>API: submit B
  end
  API-->>A: un resultado official
  API-->>B: un resultado conflict
```

```mermaid
sequenceDiagram
  participant App
  participant API
  participant Hive
  App->>API: submit completo offline acumulado
  API-->>App: conflict persistido
  App->>Hive: conflict + IDs, conserva respuestas/fotos
  Note over App,Hive: sale de reintentos normales
```

```mermaid
sequenceDiagram
  participant App
  participant API
  App->>API: repetir submit confirmado
  API-->>App: already_official
  App->>App: éxito idempotente
```

## Estados globales y locales

Globales: `available`, `completed`, `validated`, `returned`, `conflict`, `inactive`. Locales incluyen borrador/en curso/pendiente/sincronizando/error, `submitted` y `conflict`. El local ámbar tiene prioridad visual; después verde para oficial con siete fotos verificadas, rojo para conflicto/devuelto, gris para inactivo/no disponible y azul para disponible.

```mermaid
flowchart TD
  A{¿trabajo local pendiente?} -->|sí| AM[Ámbar]
  A -->|no| B{estado global}
  B -->|completed/validated + fotos| V[Verde]
  B -->|conflict/returned| R[Rojo]
  B -->|inactive/no disponible| G[Gris]
  B -->|available| AZ[Azul]
```

## Caché, lista y búsqueda

Los campos nuevos se serializan en el box existente: oficial, fecha canónica, técnico, brigada, conflictos, disponibilidad, ronda, fotos e inactividad. Campos ausentes significan disponible/ronda 1/sin conflicto. La selección normal de nueva RV oculta revisados y no disponibles; un trabajo local continúa visible, y una coincidencia exacta de cuenta puede encontrar un revisado sin habilitar su edición.

## Rondas y proyección

La app consume `currentRound=1` y `availableForRv`; no abre rondas ni autoriza revisiones. Lista, mapa, snapshot y detalle comparten el contrato servidor de la etapa.

## Backfill y datos legacy

```mermaid
flowchart LR
  O[JSON anterior] --> P[parser tolerante]
  P --> D[defaults seguros]
  N[JSON nuevo] --> P
  P --> H[mismo box Hive]
  H --> UI[UI combinada]
```

No se borran Hive, Secure Storage, SharedPreferences, borradores, colas, respuestas ni fotos. El estado `conflict` es terminal para reintento normal y de solo lectura, pero conserva la evidencia completa para resolución futura.

## Pruebas

Se cubren lectura legacy/nueva, serialización, fecha, disponibilidad, búsqueda exacta, colores, conflicto terminal, preservación de evidencia y parsing de `official`, `already_official` y `conflict`.

## Despliegue pendiente

```mermaid
sequenceDiagram
  participant Ops
  participant API
  participant Mobile
  Ops->>API: migración revisada + API compatible
  Ops->>Mobile: pruebas contra ambiente
  Ops->>Mobile: publicación futura
  Note over API,Mobile: API debe preceder o acompañar a la app
```

## Riesgos y Prompt 3

El refresco global ocurre en la siguiente sincronización/carga ya disponible, no se rediseñó el orquestador completo. La pantalla de reporte, historial inmutable, edición app-plataforma, resolución de conflictos y rondas adicionales dependen de Prompt 3 y etapas posteriores.
