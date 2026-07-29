# Etapa 12.5.3 — Certificación integral A–E

## Alcance y seguridad

La certificación cubre sincronización, validación asistida, operación offline,
recuperación, errores controlados y consistencia en servidor. Solo se permiten
`RevisionVisualStarter_Test`, almacenamiento temporal, usuarios e inspecciones
`TEST-12-5-3` y fotografías fixture. Producción, importadores, `--apply` y el
envío de inspecciones físicas quedan fuera de alcance.

## Estrategia

1. Preflight de Git, herramientas, SQL y Pixel 7 Pro.
2. Pruebas Flutter de dominio, persistencia, widgets, errores y recuperación.
3. Pruebas API unitarias e integración SQL con Node 22.
4. Consultas SQL reutilizables de integridad y ausencia de duplicados.
5. Build e instalación incremental solo si el dispositivo sigue autorizado.
6. ADB limitado a instalación, ciclo de vida, red restaurable y evidencia no
   sensible. Cámara, galería y apreciación visual permanecen manuales.

## Mapeo A–E

- A: contratos `/answers`, `/parcel-valves`, catálogos, fotos y submit.
- B: instalación, apertura, background/foreground, rotación y jerarquía ADB.
- C: Hive temporal, cola offline, reapertura, reconciliación y reintento.
- D: RFC Problem, códigos controlados, timeouts, red intermitente, corrupción,
  token expirado y doble solicitud.
- E: inspección, respuestas, válvulas, catálogos, fotos, auditoría,
  idempotencia y solo lectura en SQL de pruebas.

## Criterio de resultado

`AUTOMATED` y `ADB_ASSISTED` requieren evidencia reproducible. Todo aspecto que
dependa de percepción o interacción física se registra como `MANUAL_REQUIRED`.
Un impedimento ambiental se registra `BLOCKED`; no se infiere aprobación.

## Resultado final

La ejecución automatizada concluyó con Flutter, API, integración, build, health
y diagnósticos SQL aprobados. El APK `0.2.1+12` se instaló incrementalmente en
el Pixel 7 Pro; la app abrió sin crash y el ciclo Wi-Fi fue restaurado.

La integración detectó y corrigió dos defectos exclusivos de la infraestructura
de prueba:

- el orden de creación de `normalized_name` en las migraciones 05/06 para SQL
  Server 2014;
- un marcador `TEST-12-5-3` demasiado largo para una columna heredada.

La certificación física completa no se declara. Cámara, galería, percepción
visual, teclado y aprobación del inspector permanecen en la matriz manual.
Los resultados efectivos están en
`docs/12_5_3_automated-certification-report.md`.
