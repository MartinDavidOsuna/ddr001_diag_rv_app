# RV Sync Recovery v58 — validación

Fecha: 2026-08-13

## Identidad de build

- Package: `com.aquafim.ddr001diag`
- versionName: `0.2.36`
- versionCode: `58`
- APP base SHA: `1fc8ca477b7cf9793a0480169300750caf878f0f`
- Identidad interna: `1fc8ca477b7cf9793a0480169300750caf878f0f-dirty-v58`
- API SHA: `3986d4b43b0b22fcd8889ac670516171c369ba8c`
- APK SHA-256: `DE539A2ED4B2EADFE82897FA06D37E573EB504F7F086B27F98061FD5020F1FF6`
- Artefacto: `dist/rv-diagnostics/ddr001-rv-sync-recovery-v58.apk`

No existe un commit v58 porque se prohibió push/merge y los cambios permanecen
en el working tree. El diagnóstico persistente registra esa identidad explícita.

## Calidad automática

- `flutter analyze`: sin hallazgos.
- `flutter test`: 350 aprobadas.
- `npm test`: 27 archivos, 211 pruebas aprobadas.
- `npm run build`: aprobado.

Pruebas nuevas cubren:

- 343 trabajos legacy con 226 verificaciones: converge a 226 verified y 117
  pendientes reales, también tras una segunda ejecución/restart simulado.
- verified en `media_sync_queue` repara documento y cola legacy sin upload.
- una foto realmente pendiente permanece pendiente.
- identidad remota por server ID/client hash y rechazo de hash ambiguo.
- HTTP 429 conserva Retry-After, requestId, método y endpoint.
- prioridad ausente de toda la experiencia bajo `lib/features`.

Los contratos API existentes y las pruebas previas cubren create/upload/submit
idempotentes y repeated submit.

## Pixel 7 Pro

- Serial: `27301FDH3004R7`, estado `device`.
- Instalación: `adb install -r` — `Success`.
- `firstInstallTime` antes y después: `2026-08-08 00:17:40`.
- Versión instalada: `0.2.36+58`.
- No se usó uninstall, `pm clear`, reset Hive ni borrado de archivos.

### Conteos observables

| Estado | Antes (v57) | Después v58 | Tras force-stop/restart |
|---|---:|---:|---:|
| En proceso | 0 | 0 | 0 |
| Pendientes de sincronizar | 0 | 0 | 0 |
| Enviados | 2 | 2 | 2 |
| Cuenta 1497 | Terminada | Terminada | Terminada |

- Segundo arranque: escrituras HTTP observadas `POST/PUT/PATCH/DELETE = 0`.
- HTTP 429 observado: 0.
- Excepciones fatales: 0.
- Duplicados creados durante esa corrida: 0 (no hubo escrituras).
- La palabra/indicador Prioridad no aparece en la jerarquía UI.

## Límites de esta validación

El Pixel no contiene las 34 revisiones/343 fotos del teléfono productivo de José;
por tanto esta validación demuestra migración por fixture realista, preservación
en instalación y convergencia del caso control, pero **no prueba todavía la
convergencia física del teléfono afectado**. Tampoco se provocaron pérdidas de
respuesta contra producción porque hacerlo crearía/modificaría evidencia real.
Esos escenarios se validaron de forma controlada por contratos/tests.

Antes de declarar cerrado el incidente productivo debe instalarse esta APK con
`install -r` en uno de los teléfonos afectados, exportar el diagnóstico normal
posterior y verificar allí: conteos antes/después, cero archivos perdidos, segunda
sincronización sin escrituras y cero duplicados en SQL read-only.

