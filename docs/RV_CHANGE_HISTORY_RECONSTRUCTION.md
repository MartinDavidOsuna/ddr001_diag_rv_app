# Reconstrucción histórica del estado intencional de RV

## Alcance y método

Baseline: `origin/main` en `792070d192318cffaef8f0ddfbd13bb6d914317e`
(`1.0.16+116`). La comparación fue semántica: que un SHA no sea ancestro de
`main` no implica que su comportamiento falte, porque `26f7478` reconstruyó un
snapshot sanitizado sobre `c01961d`.

Se inspeccionaron `git log --all`, todos los reflogs, ramas locales/remotas,
stashes, worktrees, `git fsck --full --no-reflogs --unreachable`, patches,
capturas, UI XML, diagnósticos y APKs en `dist/`. No se ejecutaron `gc`, `prune`,
`clean`, resets ni merges históricos. No había stashes. Los commits unreachable
eran versiones pre-amend de cambios QA, navegación e integridad ya sustituidos;
los blobs unreachable no contenían valores UX buscados.

No se encontró una APK `0.2.39+61`. Sí se encontraron APKs Git históricas
`0.2.25+38` y `0.2.26+39`, diagnósticos v60 y APKs certificadas `1.0.0` a
`1.0.16`; no se usa una APK inexistente como evidencia.

## Matriz semántica

| Cambio/intención | Fuente | Presente en main | Ausente en main | Debe recuperarse | Cubierto por hardening actual |
|---|---|---:|---:|---:|---:|
| Baseline estable previo a la línea RV | `c01961d` | Sí | No | No | Sí |
| Sesión de campo persistente | `1fee9f9` | Sí | No | No | Sí |
| Estado global de inspección | `9df7b5f` | Sí | No | No | Sí |
| Versionado offline inmutable | `eb36072` | Sí | No | No | Sí |
| Visor móvil de reporte | `493d3ab` | Sí | No | No | Sí |
| Catálogo global de presión | `84bd81e` | Sí | No | No | Sí |
| Marca ilegible con evidencia | `7ae1902` | Sí | No | No | Sí |
| Opción indefinida de filtro | `bd05f80` | Sí | No | No | Sí |
| Pregunta de conexión piloto | `87a87b9` | Sí | No | No | Sí |
| Fotos generales y observaciones | `385ed88` | Sí | No | No | Sí |
| Navegación operativa de pendientes | `0cf6c95` | Sí | No | No | Sí |
| Cámara responsiva y toma de sesión | `c202f4a` | Sí | No | No | Sí |
| Firma productiva AQUAFIM | `fef06ef` | Sí | No | Guard público local | Sí |
| Borradores locales y seis grupos | `4cbafc0` | Sí | No | No | Sí |
| Mapa local-first y reconciliación de sesión | `0c896d9` | Sí | No | No | Sí |
| Startup productivo e iconos Android | `22d619a` | Sí | No | No | Sí |
| Convergencia funcional v59/v60 | `0dad2b1` | Sí | No | No | Sí |
| Correcciones de campo v61 | `1fc8ca4` | Sí | No | No | Sí |
| Seis grupos; Home todavía 2×3 | `392d1ca` | Sí, semántica | Presentación final | No directamente | Sí |
| Evidencia/backup de pruebas en dispositivo | `7d37b16` | Sí, semántica | No | No | Sí |
| Aislamiento de colisiones de upload | `1cf7298` | Sí | No | No | Sí |
| Integridad fotográfica confirmada | `e6b7438` | Sí | No | No | Sí |
| Snapshot sanitizado zero-loss | `26f7478` | Sí | UX local posterior | Base obligatoria | Sí |
| Merge publicado `1.0.16+116` | `792070d` | Sí | UX local posterior | Base obligatoria | Sí |
| Dashboard 3×2 determinista | `b1caf61` | No | Sí | Sí | No aplica |
| Label corto `Pendientes` | `b1caf61` | No | Sí | Sí | No aplica |
| Colores por grupo centralizados | `b1caf61` | Parcial | Extensión única | Sí | No aplica |
| Retirar Home `Mis hidrantes` y `Mapa general` | `b1caf61` | No | Sí | Sí | No aplica |
| Conservar `Todas mis revisiones` y `Sincronización` | `b1caf61` | Sí | No | Bloquear con tests | No aplica |
| Controles compactos de mapa | `b1caf61` | No | Sí | Sí | No aplica |
| Filtros Home/lista semánticamente alineados | `b1caf61` | No | Sí | Sí | Complementa hardening |
| OpenFreeMap | `719cefa` | No | Sí | No: cambio de proveedor, fuera de restauración UX | Mapa actual manda |
| Símbolo de marca en AppBars | `1c317c6` | Parcial | Generalización reusable | Sí | No aplica |
| QA aislada del package productivo | `49c3fee`, `2f40996` | Parcial | Guard local posterior | Sí | Sí |
| Inset launcher aprobado del 18% | `bc15ee1` + worktree local | No | Sí | Sí | No aplica |
| Nombre Android `AQ DV DDR001` | worktree local, 2026-08-29 21:02 -0600 | No | Sí | Sí | No aplica |

## Evidencia exacta de presentación

`b1caf61` es un commit local creado directamente desde `792070d`. Define seis
tarjetas mediante `SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3,
mainAxisExtent: 82)`, por lo que portrait usa exactamente tres columnas y dos
filas sin calcular anchos mágicos. Conserva el orden del enum:

1. En proceso — `AppColors.blue` (`#2848B8`)
2. Pendientes — `AppColors.orange` (`#E8780B`)
3. Enviados — `AppColors.teal` (`#14849A`)
4. Validados — `AppColors.green` (`#0BA674`)
5. Devueltos — `AppColors.red` (`#EF4444`)
6. Con conflictos — `AppColors.red` (`#EF4444`)

No se inventaron colores. Los valores son idénticos en `392d1ca`, `e6b7438`,
`792070d` y `b1caf61`; el delta demostrable es su asociación centralizada.

La limpieza final demostrable de Home elimina únicamente `Mis hidrantes` y
`Mapa general`. Conserva `Nueva revisión visual`, `Todas mis revisiones` y
`Sincronización`. Las rutas retiradas de Home permanecen accesibles desde la
navegación inferior y no se eliminan.

## Evidencia exacta Android

Los raster `ic_launcher`/`ic_launcher_round`, adaptive icons y monochrome de
`main` coinciden por blob con la línea aprobada desde `22d619a`. El worktree
`fix/open-source-basemap-openfreemap`, creado desde `main`, conserva sin commit:

- `launcher_icon_foreground.xml`: inset `18%`, idéntico a `bc15ee1`, modificado
  localmente el 2026-08-29 20:47 -0600;
- `strings.xml`: `AQ DV DDR001`, modificado localmente el 2026-08-29 21:02
  -0600.

Éstos son los últimos valores locales demostrables. El manifest debe seguir
referenciando `@string/app_name` y `@mipmap/ic_launcher`; se añadirá
`android:roundIcon="@mipmap/ic_launcher_round"` para declarar explícitamente el
recurso redondo ya existente.

## Límites de recuperación

No se recuperan archivos históricos completos. Persistencia, modelos, cámara,
colas, sync, reconciliación, contratos y seguridad permanecen en `main`. El
proveedor OpenFreeMap de `719cefa` no se incorpora porque cambiaría la capa
funcional del mapa y la regla de reconstrucción asigna esa autoridad al
hardening actual.
