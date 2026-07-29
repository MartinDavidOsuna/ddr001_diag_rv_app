# Arquitectura de inicio y sincronización

```text
App launch
  -> Flutter shell visible
  -> local bootstrap medido
  -> session resolution
       -> no session: login
       -> session + cache: home immediately
  -> background connectivity check
  -> background session validation
  -> background resource sync
       -> personal hydrants
       -> catalog snapshot
       -> checklist
       -> statistics
       -> catalogs
```

`runApp` ocurre antes de cualquier I/O. El shell muestra progreso y permite
reintentar. La sesión local aplica inmediatamente su namespace; red, refresh y
recursos remotos nunca forman parte del camino crítico del primer frame o del
login.

El catálogo usa un snapshot móvil mínimo con ETag. La caja vigente solo se
reconcilia después de recibir y decodificar una respuesta completa; una
interrupción conserva el snapshot anterior y las altas manuales.

Catálogo, asignaciones, estadísticas y checklist tienen fallos independientes.
La UI conserva el último dato válido y presenta una sincronización parcial sin
regresar al login.
