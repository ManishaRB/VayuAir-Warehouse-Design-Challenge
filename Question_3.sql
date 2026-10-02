/*3. Load the dimensions and the fact from the bronze_* tables, assigning the
surrogate keys. Build a DimDate with a yyyymmdd integer DateKey. Populate the fact by joining
bookings to the dimensions on their business keys. Acceptance criteria: dimensions and fact
are populated; the fact row count matches bronze_bookings; every fact row resolves to all of
its dimensions.*/

-- =====================================================================
-- LOAD: bronze_* -> dw dimensions and dw.FactTicketSales (T-SQL)
-- Assumes the bronze tables are loaded as dbo.bronze_bookings, dbo.bronze_flights,
-- dbo.bronze_passengers, dbo.bronze_airports, dbo.bronze_aircraft.
-- Adjust the schema prefix if yours differ. Run the DDL script first.
-- Load order: DimDate, DimAirport, DimAircraft, DimFlight, DimPassenger, then the fact.
-- =====================================================================
SET NOCOUNT ON;
SET LANGUAGE us_english;   -- makes DATENAME() output deterministic
SET DATEFIRST 1;           -- Monday = 1, so Sat/Sun = 6/7
GO
 
-- ---------------------------------------------------------------------
-- 0. Reset (makes the script re-runnable). Children first because of FKs.
-- ---------------------------------------------------------------------
DELETE FROM dw.FactTicketSales;
DELETE FROM dw.DimPassenger;
DELETE FROM dw.DimFlight;
DELETE FROM dw.DimAircraft;
DELETE FROM dw.DimAirport;
DELETE FROM dw.DimDate;
 
DBCC CHECKIDENT ('dw.FactTicketSales', RESEED, 0) WITH NO_INFOMSGS;
DBCC CHECKIDENT ('dw.DimPassenger',    RESEED, 0) WITH NO_INFOMSGS;
DBCC CHECKIDENT ('dw.DimFlight',       RESEED, 0) WITH NO_INFOMSGS;
DBCC CHECKIDENT ('dw.DimAircraft',     RESEED, 0) WITH NO_INFOMSGS;
DBCC CHECKIDENT ('dw.DimAirport',      RESEED, 0) WITH NO_INFOMSGS;
GO
 
-- ---------------------------------------------------------------------
-- 1. DimDate: generated calendar, DateKey = yyyymmdd integer.
--    2021-01-01 .. 2026-12-31 covers signup_date (2021+), booking_date and
--    travel_date/flight_date (to 2026-03-31) with headroom.
-- ---------------------------------------------------------------------
;WITH d AS (
    SELECT CAST('2021-01-01' AS DATE) AS dt
    UNION ALL
    SELECT DATEADD(DAY, 1, dt) FROM d WHERE dt < '2026-12-31'
)
INSERT INTO dw.DimDate
    (date_key, full_date, [year], [quarter], [month], month_name,
     day_of_month, day_of_week, day_name, is_weekend)
SELECT
    CONVERT(INT, CONVERT(CHAR(8), dt, 112)),     -- yyyymmdd
    dt,
    YEAR(dt),
    DATEPART(QUARTER, dt),
    MONTH(dt),
    DATENAME(MONTH, dt),
    DAY(dt),
    DATEPART(WEEKDAY, dt),
    DATENAME(WEEKDAY, dt),
    CASE WHEN DATEPART(WEEKDAY, dt) IN (6, 7) THEN 1 ELSE 0 END
FROM d
OPTION (MAXRECURSION 0);
GO
 
-- ---------------------------------------------------------------------
-- 2. DimAirport (surrogate airport_key assigned by IDENTITY)
-- ---------------------------------------------------------------------
INSERT INTO dw.DimAirport (airport_code, airport_name, city, country, region)
SELECT airport_code, airport_name, city, country, region
FROM   dbo.bronze_airports
ORDER  BY airport_code;
GO
 
-- ---------------------------------------------------------------------
-- 3. DimAircraft
-- ---------------------------------------------------------------------
INSERT INTO dw.DimAircraft (aircraft_code, model, manufacturer, seat_capacity)
SELECT aircraft_code, model, manufacturer, seat_capacity
FROM   dbo.bronze_aircraft
ORDER  BY aircraft_code;
GO
 
-- ---------------------------------------------------------------------
-- 4. DimFlight
-- ---------------------------------------------------------------------
INSERT INTO dw.DimFlight (flight_id, flight_number, flight_date)
SELECT flight_id, flight_number, CAST(flight_date AS DATE)
FROM   dbo.bronze_flights
ORDER  BY flight_id;
GO
 
-- ---------------------------------------------------------------------
-- 5. DimPassenger: initial load = one current version per passenger.
--    effective_date = signup_date. The later SCD2 step (stg_passenger_updates)
--    will expire these rows and add new versions.
-- ---------------------------------------------------------------------
INSERT INTO dw.DimPassenger
    (passenger_id, passenger_name, home_airport_code, frequent_flyer_tier,
     signup_date, effective_date, expiry_date, is_current)
SELECT passenger_id, passenger_name, home_airport_code, frequent_flyer_tier,
       CAST(signup_date AS DATE), CAST(signup_date AS DATE), '9999-12-31', 1
FROM   dbo.bronze_passengers
ORDER  BY passenger_id;
GO
 
-- ---------------------------------------------------------------------
-- 6. FactTicketSales: bookings joined to flights, then to each dimension on its
--    business key. Inner joins are safe here only because the validation in
--    section 7 proves no booking was dropped.
-- ---------------------------------------------------------------------
INSERT INTO dw.FactTicketSales
    (booking_date_key, travel_date_key, passenger_key, flight_key,
     origin_airport_key, dest_airport_key, aircraft_key,
     booking_id, fare_class, booking_status,
     fare_amount, tax_amount, miles_earned, booking_count)
SELECT
    bd.date_key,
    td.date_key,
    p.passenger_key,
    df.flight_key,
    oa.airport_key,
    da.airport_key,
    ac.aircraft_key,
    b.booking_id,
    b.fare_class,
    b.booking_status,
    b.fare_amount,
    b.tax_amount,
    b.miles_earned,
    1
FROM       dbo.bronze_bookings  b
JOIN       dbo.bronze_flights   f  ON f.flight_id           = b.flight_id
JOIN       dw.DimDate           bd ON bd.full_date          = CAST(b.booking_date AS DATE)
JOIN       dw.DimDate           td ON td.full_date          = CAST(b.travel_date  AS DATE)
JOIN       dw.DimPassenger      p  ON p.passenger_id        = b.passenger_id
                                  AND p.is_current          = 1
JOIN       dw.DimFlight         df ON df.flight_id          = b.flight_id
JOIN       dw.DimAirport        oa ON oa.airport_code       = f.origin_airport_code
JOIN       dw.DimAirport        da ON da.airport_code       = f.dest_airport_code
JOIN       dw.DimAircraft       ac ON ac.aircraft_code      = f.aircraft_code;
GO
 
-- ---------------------------------------------------------------------
-- 7. VALIDATION (acceptance criteria)
-- ---------------------------------------------------------------------
 
-- 7a. Row counts per table. Expected for this dataset:
--     fact 40000, flights 2000, passengers 1500, airports 24, aircraft 10, dates 2191.
SELECT 'DimDate'          AS table_name, COUNT(*) AS row_count FROM dw.DimDate          UNION ALL
SELECT 'DimAirport',      COUNT(*) FROM dw.DimAirport      UNION ALL
SELECT 'DimAircraft',     COUNT(*) FROM dw.DimAircraft     UNION ALL
SELECT 'DimFlight',       COUNT(*) FROM dw.DimFlight       UNION ALL
SELECT 'DimPassenger',    COUNT(*) FROM dw.DimPassenger    UNION ALL
SELECT 'FactTicketSales', COUNT(*) FROM dw.FactTicketSales UNION ALL
SELECT 'bronze_bookings', COUNT(*) FROM dbo.bronze_bookings;
 
-- 7b. Fact row count must equal bronze_bookings.
DECLARE @bronze INT = (SELECT COUNT(*) FROM dbo.bronze_bookings);
DECLARE @fact   INT = (SELECT COUNT(*) FROM dw.FactTicketSales);
IF @bronze <> @fact
    THROW 50001, 'Fact row count does not match bronze_bookings.', 1;
 
-- 7c. Every fact row resolves to ALL of its dimensions (inner join back to each one).
DECLARE @resolved INT = (
    SELECT COUNT(*)
    FROM   dw.FactTicketSales f
    JOIN   dw.DimDate      bd ON bd.date_key      = f.booking_date_key
    JOIN   dw.DimDate      td ON td.date_key      = f.travel_date_key
    JOIN   dw.DimPassenger p  ON p.passenger_key  = f.passenger_key
    JOIN   dw.DimFlight    df ON df.flight_key    = f.flight_key
    JOIN   dw.DimAirport   oa ON oa.airport_key   = f.origin_airport_key
    JOIN   dw.DimAirport   da ON da.airport_key   = f.dest_airport_key
    JOIN   dw.DimAircraft  ac ON ac.aircraft_key  = f.aircraft_key
);
IF @resolved <> @fact
    THROW 50002, 'Some fact rows do not resolve to all dimensions.', 1;
 
-- 7d. Any bronze booking that failed to load (should return 0 rows).
SELECT b.booking_id
FROM   dbo.bronze_bookings b
WHERE  NOT EXISTS (SELECT 1 FROM dw.FactTicketSales f WHERE f.booking_id = b.booking_id);
 
-- 7e. Measure reconciliation: bronze vs fact (columns should match pairwise).
--     Expected for this dataset: fare 621279312.00, tax 92553517.44, miles 124239925.
SELECT 'bronze' AS src, SUM(fare_amount) AS fare, SUM(tax_amount) AS tax, SUM(CAST(miles_earned AS BIGINT)) AS miles
FROM dbo.bronze_bookings
UNION ALL
SELECT 'fact',          SUM(fare_amount),         SUM(tax_amount),        SUM(CAST(miles_earned AS BIGINT))
FROM dw.FactTicketSales;
 
PRINT 'Load complete: all validations passed.';
GO