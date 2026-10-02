/*5. Rebuild the passenger dimension as Slowly Changing Dimension Type 2 (a new
surrogate key per version, the stable business key, is_current, effective_from,
effective_to). Apply stg_passenger_updates so that a changed tier or home airport
expires the old version and opens a new one, and brand-new passengers are inserted.
Acceptance criteria: the two-step expire-then-insert pattern is used; a passenger who changed
shows two versions with correct is_current and effective dates; new passengers appear as a
single current row.*/
-- =====================================================================
-- SCD Type 2 for dw.DimPassenger (simple version, T-SQL)
-- =====================================================================
 
-- SETUP (run once): use the SCD2 column names, and start every existing
-- passenger's first version at 1900-01-01.
/*EXEC sp_rename 'dw.DimPassenger.effective_date', 'effective_from', 'COLUMN';
EXEC sp_rename 'dw.DimPassenger.expiry_date',    'effective_to',   'COLUMN';
GO
UPDATE dw.DimPassenger SET effective_from = '1900-01-01';
GO*/
 
-- APPLY THE UPDATES
DECLARE @load_date DATE = CAST(GETDATE() AS DATE);   -- the date the change takes effect
 
-- STEP 1: EXPIRE the old version if the tier or home airport changed
UPDATE d
SET    d.is_current   = 0,
       d.effective_to = DATEADD(DAY, -1, @load_date)
FROM   dw.DimPassenger d
JOIN   dbo.stg_passenger_updates s ON s.passenger_id = d.passenger_id
WHERE  d.is_current = 1
  AND (d.frequent_flyer_tier <> s.frequent_flyer_tier
    OR d.home_airport_code   <> s.home_airport_code);
 
-- STEP 2: INSERT a new current row for anyone who has no current row now
--         (= passengers just expired in step 1, plus brand-new passengers)
DECLARE @load_date DATE = CAST(GETDATE() AS DATE);
INSERT INTO dw.DimPassenger
    (passenger_id, passenger_name, home_airport_code, frequent_flyer_tier,
     signup_date, effective_from, effective_to, is_current)
SELECT s.passenger_id, s.passenger_name, s.home_airport_code, s.frequent_flyer_tier,
       (SELECT MAX(d.signup_date) FROM dw.DimPassenger d WHERE d.passenger_id = s.passenger_id),
       @load_date, '9999-12-31', 1
FROM   dbo.stg_passenger_updates s
WHERE  NOT EXISTS (SELECT 1 FROM dw.DimPassenger d
                   WHERE d.passenger_id = s.passenger_id AND d.is_current = 1);
GO
 
-- CHECKS
-- 1) Totals: expect 1750 rows, 1550 current, 200 expired
SELECT COUNT(*) AS total_rows,
       SUM(CASE WHEN is_current = 1 THEN 1 ELSE 0 END) AS current_rows,
       SUM(CASE WHEN is_current = 0 THEN 1 ELSE 0 END) AS expired_rows
FROM dw.DimPassenger;
 
-- 2) A passenger who changed: two versions with correct flags and dates
SELECT TOP (6) passenger_key, passenger_id, frequent_flyer_tier, home_airport_code,
       effective_from, effective_to, is_current
FROM   dw.DimPassenger
WHERE  passenger_id IN (SELECT passenger_id FROM dw.DimPassenger GROUP BY passenger_id HAVING COUNT(*) = 2)
ORDER  BY passenger_id, effective_from;
 
-- 3) New passengers (ID 900000+): one current row each. Expect 50 rows, all with 1 version.
SELECT passenger_id, COUNT(*) AS versions, MAX(CAST(is_current AS INT)) AS is_current
FROM   dw.DimPassenger
WHERE  passenger_id >= 900000
GROUP  BY passenger_id;