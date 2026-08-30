# Política de cambios de la API compartida

`ddr001_api` es consumida por DDR001 RV, DDR001 Levantamientos, otras
aplicaciones de diagnóstico o consulta y el dashboard/plataforma web.

Antes de modificar contratos, autenticación, sesiones, permisos, tablas
compartidas, endpoints, fotografías, sincronización o comportamiento legacy,
se debe identificar y evaluar el impacto sobre todos esos consumidores. Una
necesidad de la aplicación RV no autoriza por sí sola un cambio incompatible en
la API compartida.

Los cambios deben conservar compatibilidad o incluir una estrategia explícita
de migración y pruebas por consumidor. Las excepciones requieren revisión
técnica antes de modificar la API o SQL productivos.
