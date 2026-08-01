# Etapa 01 — sesión permanente de campo (Flutter)

Fecha: 2026-08-01. Rama: `feature/permanent-field-session`.

## Arquitectura implementada

La identidad se restaura desde Secure Storage durante bootstrap y aplica inmediatamente `LocalDataScope`; mapa, hidrantes, formularios, fotos, historial y colas pueden abrir su caché sin esperar a la API. La verificación remota queda en segundo plano. `FieldSession` acepta `persistentSessionId` y `bindingId` manteniendo lectura legacy cuando no existan.

`ApiClient` conserva un único refresh concurrente, reintenta una vez la solicitud original y solo elimina credenciales si el cuerpo incluye un código definitivo reconocido. Timeout, conexión, 5xx, respuesta inválida y `401/403` genéricos dejan la sesión y el refresh anterior intactos. La cola pasa a error reintentable/offline en fallas temporales, sin `requiresAuthentication` ni mensajes de login.

Logout guarda primero una credencial de revocación pendiente dentro de Secure Storage, cierra la identidad y el scope local inmediatamente y preserva todas las cajas/archivos. Al recuperar red o antes de otro login llama al logout idempotente y elimina la credencial pendiente solo tras confirmación. El cambio A→B aplica un scope distinto; los repositorios ya filtran por propietario/ambiente/cuenta.

## Persistencia y migración

No se borran ni recrean boxes. El modelo nuevo usa campos opcionales y por ello lee sesiones legacy sin migración destructiva. Secure Storage agrega claves de binding/sesión persistente y un sobre separado para logout pendiente. `installation_id` se conserva. SharedPreferences mantiene el indicador visual legacy, pero el secreto pendiente nunca se guarda allí.

Se preservan Hive, Secure Storage no relacionado, SharedPreferences, borradores, fotografías, colas, catálogos, checklist, hidrantes y datos de otros propietarios. No se usa `Hive.deleteBoxFromDisk`, clear global ni borrado de fotos.

## Códigos y mensajes

- `SESSION_REVOKED`: Tu sesión fue revocada por un administrador.
- `USER_INACTIVE`: Tu usuario fue desactivado.
- `DEVICE_BLOCKED`: Este dispositivo fue bloqueado.
- `DEVICE_BINDING_REVOKED`: El acceso de este dispositivo fue revocado.
- `REFRESH_TOKEN_REUSE`: La seguridad de la sesión requiere iniciar nuevamente.
- Cualquier falla temporal: Sin conexión. Puedes continuar trabajando; los cambios se sincronizarán después.

## Flujos

### Login correcto

```mermaid
sequenceDiagram
  App->>API: start identidad+device
  API-->>App: session/binding/tokens
  App->>Secure: escritura atómica de scope y tokens
  App-->>App: mostrar datos del propietario
```

### Restauración offline

```mermaid
sequenceDiagram
  Bootstrap->>Secure: read
  Secure-->>Bootstrap: sesión local
  Bootstrap->>Scope: aplicar usuario
  Bootstrap-->>UI: contenido cacheado
  Bootstrap--xAPI: current timeout
  UI-->>UI: banner offline, sin login
```

### Refresh

```mermaid
sequenceDiagram
  Request->>ApiClient: access vencido
  ApiClient->>API: un refresh compartido
  API-->>ApiClient: tokens rotados
  ApiClient->>Secure: confirmar par nuevo
  ApiClient->>API: reintentar original una vez
```

### Revocación

```mermaid
sequenceDiagram
  API-->>ApiClient: 401/403 + código definitivo
  ApiClient->>Secure: retirar credenciales
  AppState->>Scope: cerrar acceso en memoria
  AppState-->>UI: mensaje diferenciado + login
```

### Logout online

```mermaid
sequenceDiagram
  App->>Secure: staged pending logout
  App->>API: logout idempotente
  API-->>App: 204
  App->>Secure: clear active + pending
  App->>Scope: close
```

### Logout offline

```mermaid
sequenceDiagram
  App->>Secure: pending refresh cifrado
  App--xAPI: sin conexión
  App->>Secure: clear active
  App->>Scope: close
  Note over App: drafts/photos/queues permanecen
  App->>API: retry al volver
```

### Cambio de usuario

```mermaid
flowchart LR
  LA[logout A] --> RA[revocación A completada]
  RA --> LB[login B]
  LB --> SB[scope B]
  SB -. aislado .-> CA[caché A]
```

### Usuario activo en otro dispositivo

```mermaid
sequenceDiagram
  App2->>API: login A
  API-->>App2: 409 USER_ACTIVE_ON_ANOTHER_DEVICE
  App2-->>App2: explicar conflicto
  Note over App2: no sobrescribe Secure Storage ni scope existente
```

## Pruebas, despliegue y rollback

Unitarias cubren refresh único, red/500, `401` genérico, cinco revocaciones, sesión legacy/nueva, aislamiento y logout offline; widgets existentes cubren bootstrap visible y acceso a caché. Despliegue pendiente: API/migración primero, configurar `FIELD_REFRESH_TOKEN_HOURS=87600`, compilar app y probar modo avión/reinicio/dos usuarios/dos dispositivos en ambiente. Rollback de app conserva todos los documentos; si el contrato API se revierte, deshabilitar distribución nueva y coordinar API/SQL. Riesgos: credencial pendiente puede expirar técnicamente tras diez años; desinstalación/clear-data elimina almacenamiento local; historial remoto completo depende de endpoints de etapas posteriores.
