/*6. The sales fact is the biggest table in the warehouse. Partition it by date using a partition function 
and a partition scheme. Then run two queries: one that filters on the partition key, and one that filters 
on a non-partition column. Acceptance criteria: a partition function and scheme exist and the fact sits on 
the scheme; you show, using the actual execution plan, that the first query prunes to a small number of 
partitions and the second does not, and you explain why. Give simple step by step answer.*/
-- =====================================================================
-- PARTITION dw.FactTicketSales BY DATE (T-SQL)
-- Partition key: travel_date_key (yyyymmdd integer), one partition per month.
-- Data covers Jan 2025 - Mar 2026; boundaries run to Dec 2026 for headroom.
-- =====================================================================

-- STEP 1: PARTITION FUNCTION - defines the boundaries.
-- RANGE RIGHT: each boundary value is the FIRST day of a month and belongs to the partition
-- on its right. 23 boundaries = 24 partitions:
--   partition 1 = before 2025-02-01 (all of Jan 2025), partition 2 = Feb 2025, ... partition 24 = Dec 2026 onward.
CREATE PARTITION FUNCTION pf_TravelDate (INT)
AS RANGE RIGHT FOR VALUES (
    20250201, 20250301, 20250401, 20250501, 20250601, 20250701,
    20250801, 20250901, 20251001, 20251101, 20251201,
    20260101, 20260201, 20260301, 20260401, 20260501, 20260601,
    20260701, 20260801, 20260901, 20261001, 20261101, 20261201
);
GO

-- STEP 2: PARTITION SCHEME - maps every partition to a filegroup.
-- Everything goes to PRIMARY to keep it simple (in production, spread across filegroups).
CREATE PARTITION SCHEME ps_TravelDate
AS PARTITION pf_TravelDate ALL TO ([PRIMARY]);
GO

-- STEP 3: PUT THE FACT TABLE ON THE SCHEME.
-- A table is partitioned by its clustered index, so we replace the clustered primary key
-- with a clustered index built ON the scheme, then add the primary key back as nonclustered.
-- (The booking_id unique constraint and the FK indexes stay as they are.)
ALTER TABLE dw.FactTicketSales DROP CONSTRAINT PK_FactTicketSales;
GO

CREATE UNIQUE CLUSTERED INDEX CIX_FactTicketSales
    ON dw.FactTicketSales (travel_date_key, ticket_sales_key)
    ON ps_TravelDate (travel_date_key);              -- <-- the table now lives on the scheme
GO

-- ON [PRIMARY] keeps this index OUT of the partition scheme. Without it, SQL Server aligns the
-- index to the scheme by default, and a unique index must then contain travel_date_key (error 1908).
ALTER TABLE dw.FactTicketSales
    ADD CONSTRAINT PK_FactTicketSales PRIMARY KEY NONCLUSTERED (ticket_sales_key) ON [PRIMARY];
GO

-- STEP 4: CONFIRM the table sits on the scheme and see rows per partition.
-- Expected: partitions 1-15 hold the data (Jan 2025 - Mar 2026), partitions 16-24 are empty.
SELECT i.name AS index_name, ds.name AS data_space, ds.type_desc
FROM   sys.indexes i
JOIN   sys.data_spaces ds ON ds.data_space_id = i.data_space_id
WHERE  i.object_id = OBJECT_ID('dw.FactTicketSales') AND i.index_id = 1;   -- expect ps_TravelDate / PARTITION_SCHEME

SELECT $PARTITION.pf_TravelDate(travel_date_key) AS partition_number,
       COUNT(*) AS row_count
FROM   dw.FactTicketSales
GROUP  BY $PARTITION.pf_TravelDate(travel_date_key)
ORDER  BY partition_number;
GO

-- =====================================================================
-- STEP 5: TWO TEST QUERIES
-- In SSMS first turn on  Query > Include Actual Execution Plan  (Ctrl+M), then run each.
-- STATISTICS IO also prints a scan count and logical reads you can compare.
-- =====================================================================
SET STATISTICS IO ON;

-- QUERY 1: filters on the PARTITION KEY (March 2025 only).
-- Expect 2745 rows, fare 40630571.00.
SELECT COUNT(*) AS bookings, SUM(fare_amount) AS fare
FROM   dw.FactTicketSales
WHERE  travel_date_key BETWEEN 20250301 AND 20250331;

-- QUERY 2: filters on a NON-partition column (fare_class has no link to the date).
-- Expect 4779 rows, fare 203820652.00.
SET STATISTICS IO ON;
SELECT COUNT(*) AS bookings, SUM(fare_amount) AS fare
FROM   dw.FactTicketSales
WHERE  fare_class = 'Business';

SET STATISTICS IO OFF;
GO

