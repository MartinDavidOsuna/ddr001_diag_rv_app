/*
  DDR001 - Diagnóstico de coordenadas WGS84 duplicadas
  Base: DDR001_Hidrantes_Prod
  Motor: Microsoft SQL Server

  Este script es estrictamente de solo lectura. No actualiza ni elimina datos.

  Interpretación:
  - duplicate_coordinate_groups = 0: el agrupamiento observado era de la app.
  - duplicate_coordinate_groups > 0: esas filas ocupan exactamente el mismo
    punto y sus marcadores se superpondrán incluso sin clustering.
  - distinct_utm_pairs > 1 para un mismo WGS84: revisar redondeo/conversión.
*/

USE [DDR001_Hidrantes_Prod];
GO

SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

IF OBJECT_ID(N'rv.hydrants', N'U') IS NULL
    THROW 51100, N'No existe la tabla rv.hydrants.', 1;

IF COL_LENGTH(N'rv.hydrants', N'hydrant_id') IS NULL
   OR COL_LENGTH(N'rv.hydrants', N'account_number') IS NULL
   OR COL_LENGTH(N'rv.hydrants', N'latitude') IS NULL
   OR COL_LENGTH(N'rv.hydrants', N'longitude') IS NULL
   OR COL_LENGTH(N'rv.hydrants', N'source_x') IS NULL
   OR COL_LENGTH(N'rv.hydrants', N'source_y') IS NULL
    THROW 51101, N'Faltan columnas requeridas en rv.hydrants.', 1;
GO

/* Resumen general de calidad de coordenadas. */
SELECT
    total_hydrants = COUNT_BIG(*),
    valid_coordinates = SUM(CASE
        WHEN latitude BETWEEN -90.0 AND 90.0
         AND longitude BETWEEN -180.0 AND 180.0
         AND (latitude <> 0.0 OR longitude <> 0.0)
        THEN CONVERT(BIGINT, 1) ELSE CONVERT(BIGINT, 0) END),
    missing_or_invalid_coordinates = SUM(CASE
        WHEN latitude IS NULL
          OR longitude IS NULL
          OR latitude NOT BETWEEN -90.0 AND 90.0
          OR longitude NOT BETWEEN -180.0 AND 180.0
          OR (latitude = 0.0 AND longitude = 0.0)
        THEN CONVERT(BIGINT, 1) ELSE CONVERT(BIGINT, 0) END)
FROM rv.hydrants;
GO

/* Cantidad de grupos y filas adicionales en coordenadas exactamente iguales. */
WITH ValidCoordinates AS
(
    SELECT latitude, longitude
    FROM rv.hydrants
    WHERE latitude BETWEEN -90.0 AND 90.0
      AND longitude BETWEEN -180.0 AND 180.0
      AND (latitude <> 0.0 OR longitude <> 0.0)
),
DuplicateCoordinates AS
(
    SELECT latitude, longitude, hydrant_count = COUNT_BIG(*)
    FROM ValidCoordinates
    GROUP BY latitude, longitude
    HAVING COUNT_BIG(*) > 1
)
SELECT
    duplicate_coordinate_groups = COUNT_BIG(*),
    hydrants_in_duplicate_groups = COALESCE(SUM(hydrant_count), 0),
    overlapping_hydrants_after_first =
        COALESCE(SUM(hydrant_count - CONVERT(BIGINT, 1)), 0)
FROM DuplicateCoordinates;
GO

/* Lista de coordenadas duplicadas, grupos más grandes primero. */
SELECT
    latitude,
    longitude,
    hydrant_count = COUNT_BIG(*),
    first_account_number = MIN(account_number),
    last_account_number = MAX(account_number)
FROM rv.hydrants
WHERE latitude BETWEEN -90.0 AND 90.0
  AND longitude BETWEEN -180.0 AND 180.0
  AND (latitude <> 0.0 OR longitude <> 0.0)
GROUP BY latitude, longitude
HAVING COUNT_BIG(*) > 1
ORDER BY COUNT_BIG(*) DESC, latitude, longitude;
GO

/* Detalle de cada hidrante involucrado para revisar su UTM de origen. */
WITH DuplicateCoordinates AS
(
    SELECT latitude, longitude
    FROM rv.hydrants
    WHERE latitude BETWEEN -90.0 AND 90.0
      AND longitude BETWEEN -180.0 AND 180.0
      AND (latitude <> 0.0 OR longitude <> 0.0)
    GROUP BY latitude, longitude
    HAVING COUNT_BIG(*) > 1
)
SELECT
    hydrant.hydrant_id,
    hydrant.account_number,
    hydrant.latitude,
    hydrant.longitude,
    hydrant.source_x,
    hydrant.source_y
FROM rv.hydrants AS hydrant
INNER JOIN DuplicateCoordinates AS duplicate_coordinate
        ON duplicate_coordinate.latitude = hydrant.latitude
       AND duplicate_coordinate.longitude = hydrant.longitude
ORDER BY
    hydrant.latitude,
    hydrant.longitude,
    hydrant.account_number;
GO

/* Distingue duplicado real de UTM frente a colisión por redondeo WGS84. */
WITH DistinctSourcePairs AS
(
    SELECT DISTINCT
        latitude,
        longitude,
        source_x,
        source_y
    FROM rv.hydrants
    WHERE latitude BETWEEN -90.0 AND 90.0
      AND longitude BETWEEN -180.0 AND 180.0
      AND (latitude <> 0.0 OR longitude <> 0.0)
      AND source_x IS NOT NULL
      AND source_y IS NOT NULL
)
SELECT
    latitude,
    longitude,
    distinct_utm_pairs = COUNT_BIG(*)
FROM DistinctSourcePairs
GROUP BY latitude, longitude
HAVING COUNT_BIG(*) > 1
ORDER BY COUNT_BIG(*) DESC, latitude, longitude;
GO

/* El script no contiene INSERT, UPDATE, DELETE, MERGE, DROP ni TRUNCATE. */
