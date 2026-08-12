/*
  DDR001 - Backfill y persistencia de coordenadas de hidrantes
  Base: DDR001_Hidrantes_Prod
  Motor: Microsoft SQL Server

  Usa la función validada:
      rv.fn_UtmZone13NToWgs84(source_x, source_y)

  La causa probable de la pérdida es una importación/MERGE que vuelve a
  escribir latitude y longitude con NULL. El UPDATE aislado las calcula, pero
  no evita que una carga posterior las vuelva a nulificar. Este script:

    1. completa inmediatamente todas las coordenadas faltantes;
    2. instala un trigger que las recalcula después de INSERT/UPDATE;
    3. conserva coordenadas válidas ya capturadas;
    4. actualiza updated_at para invalidar ETag/cursor del mapa;
    5. no elimina hidrantes ni modifica source_x/source_y.

  Ejecutar primero en staging. No ejecutar si rv.hydrants no es la tabla
  canónica que consume la API.
*/

USE [DDR001_Hidrantes_Prod];
GO

SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

IF SCHEMA_ID(N'rv') IS NULL
    THROW 51000, N'No existe el esquema rv.', 1;

IF OBJECT_ID(N'rv.hydrants', N'U') IS NULL
    THROW 51001, N'No existe la tabla rv.hydrants.', 1;

IF OBJECT_ID(N'rv.fn_UtmZone13NToWgs84', N'IF') IS NULL
   AND OBJECT_ID(N'rv.fn_UtmZone13NToWgs84', N'TF') IS NULL
    THROW 51002, N'No existe rv.fn_UtmZone13NToWgs84.', 1;

IF COL_LENGTH(N'rv.hydrants', N'hydrant_id') IS NULL
   OR COL_LENGTH(N'rv.hydrants', N'source_x') IS NULL
   OR COL_LENGTH(N'rv.hydrants', N'source_y') IS NULL
   OR COL_LENGTH(N'rv.hydrants', N'latitude') IS NULL
   OR COL_LENGTH(N'rv.hydrants', N'longitude') IS NULL
   OR COL_LENGTH(N'rv.hydrants', N'updated_at') IS NULL
    THROW 51003, N'Faltan columnas requeridas en rv.hydrants.', 1;
GO

/* Diagnóstico previo, sin datos sensibles. */
SELECT
    COUNT_BIG(*) AS total_hydrants,
    SUM(CASE
            WHEN source_x IS NOT NULL AND source_y IS NOT NULL THEN 1
            ELSE 0
        END) AS with_utm_source,
    SUM(CASE
            WHEN source_x IS NOT NULL
             AND source_y IS NOT NULL
             AND
             (
                 latitude IS NULL
                 OR longitude IS NULL
                 OR latitude NOT BETWEEN -90.0 AND 90.0
                 OR longitude NOT BETWEEN -180.0 AND 180.0
                 OR (latitude = 0.0 AND longitude = 0.0)
             )
            THEN 1 ELSE 0
        END) AS requiring_backfill
FROM rv.hydrants;
GO

/*
  Backfill inicial. Solo reemplaza coordenadas ausentes o inválidas; una
  coordenada WGS84 válida existente no se sobrescribe.
*/
BEGIN TRY
    BEGIN TRANSACTION;

    UPDATE hydrant
       SET hydrant.latitude = converted.Latitude,
           hydrant.longitude = converted.Longitude,
           hydrant.updated_at = SYSUTCDATETIME()
      FROM rv.hydrants AS hydrant
      CROSS APPLY rv.fn_UtmZone13NToWgs84(
          CONVERT(FLOAT, hydrant.source_x),
          CONVERT(FLOAT, hydrant.source_y)
      ) AS converted
     WHERE hydrant.source_x IS NOT NULL
       AND hydrant.source_y IS NOT NULL
       AND
       (
           hydrant.latitude IS NULL
           OR hydrant.longitude IS NULL
           OR hydrant.latitude NOT BETWEEN -90.0 AND 90.0
           OR hydrant.longitude NOT BETWEEN -180.0 AND 180.0
           OR (hydrant.latitude = 0.0 AND hydrant.longitude = 0.0)
       );

    DECLARE @BackfilledRows INT = @@ROWCOUNT;

    COMMIT TRANSACTION;

    PRINT CONCAT(N'Coordenadas completadas: ', @BackfilledRows);
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
    THROW;
END CATCH;
GO

/*
  Reemplaza exclusivamente el trigger administrado por esta migración.
  No borra tablas ni datos.
*/
IF OBJECT_ID(N'rv.trg_hydrants_keep_wgs84', N'TR') IS NOT NULL
    DROP TRIGGER rv.trg_hydrants_keep_wgs84;
GO

CREATE TRIGGER rv.trg_hydrants_keep_wgs84
ON rv.hydrants
AFTER INSERT, UPDATE
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    /* Evita una segunda ejecución causada por el UPDATE correctivo del trigger. */
    IF TRIGGER_NESTLEVEL() > 1 RETURN;

    /*
      Si una importación vuelve a guardar NULL, 0,0 o valores fuera de rango,
      recalcula desde el UTM de esa misma fila. No modifica WGS84 válido.
    */
    UPDATE hydrant
       SET hydrant.latitude = converted.Latitude,
           hydrant.longitude = converted.Longitude,
           hydrant.updated_at = SYSUTCDATETIME()
      FROM rv.hydrants AS hydrant
      INNER JOIN inserted AS changed
              ON changed.hydrant_id = hydrant.hydrant_id
      CROSS APPLY rv.fn_UtmZone13NToWgs84(
          CONVERT(FLOAT, changed.source_x),
          CONVERT(FLOAT, changed.source_y)
      ) AS converted
     WHERE changed.source_x IS NOT NULL
       AND changed.source_y IS NOT NULL
       AND
       (
           changed.latitude IS NULL
           OR changed.longitude IS NULL
           OR changed.latitude NOT BETWEEN -90.0 AND 90.0
           OR changed.longitude NOT BETWEEN -180.0 AND 180.0
           OR (changed.latitude = 0.0 AND changed.longitude = 0.0)
       );
END;
GO

/* Verifica que el trigger exista y esté habilitado. */
SELECT
    trigger_name = trigger_object.name,
    trigger_object.is_disabled,
    parent_table = QUOTENAME(OBJECT_SCHEMA_NAME(trigger_object.parent_id))
                   + N'.'
                   + QUOTENAME(OBJECT_NAME(trigger_object.parent_id))
FROM sys.triggers AS trigger_object
WHERE trigger_object.object_id = OBJECT_ID(N'rv.trg_hydrants_keep_wgs84');
GO

/* Resultado final. pending_conversion debe quedar en cero salvo UTM inválido. */
SELECT
    COUNT_BIG(*) AS total_hydrants,
    SUM(CASE
            WHEN latitude BETWEEN -90.0 AND 90.0
             AND longitude BETWEEN -180.0 AND 180.0
             AND (latitude <> 0.0 OR longitude <> 0.0)
            THEN 1 ELSE 0
        END) AS with_valid_wgs84,
    SUM(CASE
            WHEN source_x IS NOT NULL
             AND source_y IS NOT NULL
             AND
             (
                 latitude IS NULL
                 OR longitude IS NULL
                 OR latitude NOT BETWEEN -90.0 AND 90.0
                 OR longitude NOT BETWEEN -180.0 AND 180.0
                 OR (latitude = 0.0 AND longitude = 0.0)
             )
            THEN 1 ELSE 0
        END) AS pending_conversion
FROM rv.hydrants;
GO

/*
  Prueba recomendada en staging:

  BEGIN TRANSACTION;

  DECLARE @TestHydrantId UNIQUEIDENTIFIER =
  (
      SELECT TOP (1) hydrant_id
      FROM rv.hydrants
      WHERE source_x IS NOT NULL
        AND source_y IS NOT NULL
        AND latitude IS NOT NULL
        AND longitude IS NOT NULL
      ORDER BY hydrant_id
  );

  UPDATE rv.hydrants
     SET latitude = NULL,
         longitude = NULL
   WHERE hydrant_id = @TestHydrantId;

  SELECT hydrant_id, source_x, source_y, latitude, longitude
  FROM rv.hydrants
  WHERE hydrant_id = @TestHydrantId;

  ROLLBACK TRANSACTION;

  El SELECT debe mostrar latitude/longitude restauradas aun antes del ROLLBACK.
*/
