/*4. Snowflake the geography. Normalise the airport dimension into three linked
tables: airport, city, and country. Load them, and write one sentence on the trade-off you are
making. Acceptance criteria: three linked tables with foreign keys; a query can resolve an
airport all the way up to its country.*/
-- =====================================================================
-- SNOWFLAKE THE GEOGRAPHY (T-SQL)
-- DimAirport -> DimCity -> DimCountry
-- Run after the DDL and load scripts. DimAirport keeps its airport_key values,
-- so FactTicketSales (origin_airport_key / dest_airport_key) is untouched.
-- Profiling of bronze_airports showed: region depends only on country (13 countries,
-- 0 with >1 region), and each city belongs to exactly one country (24 cities).
-- So region lives on DimCountry.
-- =====================================================================
SET NOCOUNT ON;
GO
 
-- ---------------------------------------------------------------------
-- 1. New tables: DimCountry (top), DimCity (middle, FK to country)
-- ---------------------------------------------------------------------
CREATE TABLE dw.DimCountry (
    country_key   INT IDENTITY(1,1) NOT NULL,           -- surrogate
    country_name  VARCHAR(60) NOT NULL,                 -- business key
    region        VARCHAR(40) NULL,
    CONSTRAINT PK_DimCountry      PRIMARY KEY (country_key),
    CONSTRAINT UQ_DimCountry_name UNIQUE (country_name)
);
 
CREATE TABLE dw.DimCity (
    city_key     INT IDENTITY(1,1) NOT NULL,            -- surrogate
    city_name    VARCHAR(60) NOT NULL,                  -- business key (with country)
    country_key  INT         NOT NULL,
    CONSTRAINT PK_DimCity         PRIMARY KEY (city_key),
    CONSTRAINT UQ_DimCity_name    UNIQUE (city_name, country_key),
    CONSTRAINT FK_DimCity_country FOREIGN KEY (country_key) REFERENCES dw.DimCountry (country_key)
);
GO
 
-- ---------------------------------------------------------------------
-- 2. Load DimCountry, then DimCity (surrogate keys assigned by IDENTITY)
-- ---------------------------------------------------------------------
INSERT INTO dw.DimCountry (country_name, region)
SELECT DISTINCT country, region
FROM   dbo.bronze_airports
ORDER  BY country;
 
INSERT INTO dw.DimCity (city_name, country_key)
SELECT DISTINCT a.city, c.country_key
FROM   dbo.bronze_airports a
JOIN   dw.DimCountry       c ON c.country_name = a.country
ORDER  BY c.country_key, a.city;
GO
 
-- ---------------------------------------------------------------------
-- 3. Reshape DimAirport: add city_key, populate, enforce, drop the flattened columns
-- ---------------------------------------------------------------------
ALTER TABLE dw.DimAirport ADD city_key INT NULL;
GO
 
UPDATE ap
SET    ap.city_key = ct.city_key
FROM   dw.DimAirport       ap
JOIN   dbo.bronze_airports b  ON b.airport_code = ap.airport_code
JOIN   dw.DimCountry       co ON co.country_name = b.country
JOIN   dw.DimCity          ct ON ct.city_name = b.city
                             AND ct.country_key = co.country_key;
GO
 
ALTER TABLE dw.DimAirport ALTER COLUMN city_key INT NOT NULL;
ALTER TABLE dw.DimAirport ADD CONSTRAINT FK_DimAirport_city
      FOREIGN KEY (city_key) REFERENCES dw.DimCity (city_key);
CREATE NONCLUSTERED INDEX ix_dimairport_city ON dw.DimAirport (city_key);
CREATE NONCLUSTERED INDEX ix_dimcity_country ON dw.DimCity (country_key);
 
ALTER TABLE dw.DimAirport DROP COLUMN city, country, region;
GO