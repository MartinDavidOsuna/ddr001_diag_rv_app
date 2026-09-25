# Documentos históricos recuperados

Estos documentos se conservan íntegros como evidencia histórica; sus versiones,
pendientes y recomendaciones corresponden a sus fechas, no al estado actual de
la app 1.0.18+118 ni a una certificación actual de producción.

- `rv-major-update-analysis-2026-08-01.md`: plan original de `1da8870`,
  recuperado de `plan/rv-major-update-analysis`.
- `motog14_zero_loss_certification_2026-08-28.md`: diagnóstico y resultados de
  la versión 1.0.6+106, recuperados de `6f7b0b9` en
  `fix/motog14-zero-loss-visibility-20260827`.

## Auditoría de integración del 2026-09-25

Se actualizaron las referencias de origin y se revisaron todas las ramas
locales/remotas y los PR abiertos (ninguno). La rama
`feat/rv-inactive-closure-sync`, en `8014e7f`, contenía los dos commits
pendientes sobre `main` (`34c6a9e`): sincronización Ausente y versión 1.0.18+118.

Las ramas históricas no se fusionan indiscriminadamente: el historial fue
reconstruido mediante el snapshot `26f7478` y recuperaciones posteriores.
La comparación de `lib/` entre ese snapshot y `certified/rv-1.0.16-local`
es idéntica. Las ramas anteriores a esa certificación quedan cubiertas por
esa recuperación. Véase también `../RV_CHANGE_HISTORY_RECONSTRUCTION.md`.

- Los cambios de QA `2f40996` y `ca43b34`, de UI `b1caf61` y de identidad
  `1c317c6` tienen equivalentes de parche en la rama actual.
- Los archivos de basemap y de identidad Android de
  `fix/open-source-basemap-openfreemap` coinciden con la rama actual;
  véase `../RV_MAP_BASEMAP_RECOVERY.md`.
- Las ramas de funcionalidades derivadas del plan contienen el documento
  recuperado aquí; sus implementaciones están en la línea certificada.
- Los commits históricos agregados `bc15ee1`/`0652b95` incluyen artefactos APK
  posteriormente retirados. No se reincorporan binarios antiguos.
- Las ramas de release/recovery actuales ya son antecesoras de la rama actual.

Se mantienen todas las referencias históricas. Que Git muestre una rama antigua
como no fusionada por ascendencia no implica que su funcionalidad esté pendiente.
Esta auditoría no acredita despliegue de API ni certificación física nueva.
