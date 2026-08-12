/*
  Auditoría RV de producción - Pixel 7 Pro
  Fecha: 2026-08-08

  No se generaron registros remotos durante la auditoría:
    - inspecciones: 0
    - reportes visuales: 0
    - fotografías: 0
    - hidrantes manuales: 0
    - sesiones creadas o revocadas: 0

  Por seguridad este script no referencia tablas ni elimina datos. Se conserva
  como manifiesto de rollback: el conjunto exacto a revertir está vacío.
*/

SET NOCOUNT ON;
SET XACT_ABORT ON;

BEGIN TRANSACTION;

PRINT N'Auditoría RV 2026-08-08: no existen registros de prueba que revertir.';
PRINT N'No se ejecutó ninguna instrucción DELETE, UPDATE ni INSERT.';

ROLLBACK TRANSACTION;
