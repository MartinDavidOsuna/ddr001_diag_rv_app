/*
  Rollback de la auditoría RV con escritura - Pixel 7 Pro
  Fecha local: 2026-08-08 (America/Hermosillo, UTC-07:00)

  Alcance remoto conocido:
    - cuenta existente 1130;
    - creador martinosuna@agrienlace.com;
    - borrador/inspección parcial creado aproximadamente 20:00-21:00 UTC;
    - una fotografía subida y verificada;
    - NO hubo submit ni reporte oficial intencional.

  SEGURIDAD:
    1. El script inicia en modo diagnóstico (@Apply = 0).
    2. No elimina el hidrante 1130.
    3. No elimina reportes oficiales ni datos fuera de la ventana.
    4. Si el esquema desplegado no coincide, aborta sin cambios.
    5. Revise primero el result set y escriba los IDs exactos en
       @AuditInspectionIds. Solo entonces cambie @Apply a 1.

  Los IDs del hidrante manual AUDIT-RV-20260808-124300-P7P y de sus tres
  fotografías son locales; no llegaron al servidor y no pertenecen a este SQL.
*/

USE [DDR001_Hidrantes_Prod];
GO

SET NOCOUNT ON;
SET XACT_ABORT ON;

DECLARE @Apply BIT = 0;
DECLARE @AccountNumber NVARCHAR(100) = N'1130';
DECLARE @CreatorEmail NVARCHAR(320) = N'martinosuna@agrienlace.com';
DECLARE @CreatedFromUtc DATETIME2(0) = '2026-08-08T20:00:00';
DECLARE @CreatedToUtc DATETIME2(0) = '2026-08-08T21:00:00';

IF OBJECT_ID(N'rv.inspections', N'U') IS NULL
    THROW 51000, N'No existe rv.inspections. Verifique el esquema desplegado; no se hizo ningún cambio.', 1;

/*
  Descubrimiento deliberadamente dinámico: las revisiones desplegadas de la
  API no siempre usan el mismo nombre para fecha/usuario. Esta consulta lista
  las columnas reales antes de preparar el borrado.
*/
SELECT
    c.column_id,
    c.name AS column_name,
    TYPE_NAME(c.user_type_id) AS data_type
FROM sys.columns AS c
WHERE c.object_id = OBJECT_ID(N'rv.inspections')
ORDER BY c.column_id;

SELECT
    fk.name AS foreign_key_name,
    OBJECT_SCHEMA_NAME(fkc.parent_object_id) AS child_schema,
    OBJECT_NAME(fkc.parent_object_id) AS child_table,
    pc.name AS child_column,
    rc.name AS inspection_column
FROM sys.foreign_key_columns AS fkc
INNER JOIN sys.foreign_keys AS fk
    ON fk.object_id = fkc.constraint_object_id
INNER JOIN sys.columns AS pc
    ON pc.object_id = fkc.parent_object_id
   AND pc.column_id = fkc.parent_column_id
INNER JOIN sys.columns AS rc
    ON rc.object_id = fkc.referenced_object_id
   AND rc.column_id = fkc.referenced_column_id
WHERE fkc.referenced_object_id = OBJECT_ID(N'rv.inspections')
ORDER BY child_schema, child_table, child_column;

DECLARE @AuditInspectionIds TABLE
(
    inspection_id UNIQUEIDENTIFIER NOT NULL PRIMARY KEY
);

/*
  DESPUÉS de revisar con el equipo de API/DB los candidatos de cuenta, creador
  y ventana UTC, agregue solamente el/los UUID exactos producidos por esta
  auditoría. Ejemplo, mantener comentado hasta confirmar:

  INSERT INTO @AuditInspectionIds (inspection_id)
  VALUES ('00000000-0000-0000-0000-000000000000');
*/

IF NOT EXISTS (SELECT 1 FROM @AuditInspectionIds)
BEGIN
    PRINT N'Modo seguro: no se proporcionaron IDs remotos confirmados.';
    PRINT N'Cuenta objetivo: ' + @AccountNumber;
    PRINT N'Creador objetivo: ' + @CreatorEmail;
    PRINT N'Ventana UTC: 2026-08-08 20:00:00 a 21:00:00.';
    PRINT N'Revise las columnas y dependencias listadas; no se eliminó nada.';
    RETURN;
END;

IF @Apply = 0
BEGIN
    SELECT inspection_id AS confirmed_audit_inspection_id
    FROM @AuditInspectionIds;
    PRINT N'DRY RUN: cambie @Apply a 1 solamente después de validar propietario, cuenta, fecha y ausencia de submit.';
    RETURN;
END;

/*
  No se automatiza un DELETE genérico de dependencias: hacerlo por metadatos
  podría borrar evidencia ajena. Ejecute el servicio/rollback oficial de la API
  para los IDs confirmados, o complete aquí el orden de tablas usando el listado
  de foreign keys anterior y la migración exacta instalada.
*/
THROW 51001, N'Rollback destructivo bloqueado: complete el orden de borrado conforme al esquema de API desplegado y mantenga el filtro por IDs confirmados.', 1;
GO
