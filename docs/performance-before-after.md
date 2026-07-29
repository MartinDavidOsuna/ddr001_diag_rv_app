# Rendimiento antes y después

| Métrica | Antes confirmado | Después objetivo/medición |
|---|---:|---:|
| Primer frame | después de bootstrap completo | shell en el primer frame |
| I/O antes de `runApp` | más de 30 cajas y recuperación | 0 |
| Login | sesión + health + catálogo + mine + estadísticas + checklist | sesión y almacenamiento seguro |
| Catálogo aproximado | 10 solicitudes para 2,000 filas | 1 snapshot o 304 |
| SQL por catálogo | CTE/ROW_NUMBER/COUNT por página | una consulta mínima |
| Health posterior al login | forzado | reutiliza comprobación reciente |
| Escritura catálogo | lote al terminar todas las páginas | lote tras snapshot válido |

Las mediciones temporales exactas del primer frame se registran mediante
`Stopwatch` en debug. No se incluyen tokens, PII ni direcciones de
infraestructura. La comparación física final debe ejecutarse con un ambiente
de prueba autorizado y datos representativos.

Medición en `RevisionVisualStarter_Test`: snapshot de 1,169 hidrantes en 41 ms
de servidor; la segunda solicitud con el mismo ETag devolvió 304. La prueba
Flutter del contrato procesó snapshot y 304 en una única solicitud por intento.
