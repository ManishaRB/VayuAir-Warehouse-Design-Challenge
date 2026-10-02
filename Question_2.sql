/*Create a dw schema and write the star schema DDL: a central FactTicketSales at 
your declared grain plus the dimensions it needs (date, passenger, flight, airport, aircraft). 
Use surrogate keys on the dimensions and foreign keys on the fact, and keep only additive measures on the fact.
Acceptance criteria: fact at the declared grain with surrogate-key foreign keys; each dimension has 
a surrogate primary key and keeps its business key.*/
 
-- =====================================================================
-- Star schema DDL (T-SQL / SQL Server)
-- GRAIN of FactTicketSales: one row = one booking (one booking_id):
--   a single passenger's booking on a single flight, in one fare class,
--   with its status (Confirmed / Cancelled / NoShow).
-- =====================================================================

CREATE SCHEMA dw;

-- ---------------------------------------------------------------------
-- DIMENSIONS (surrogate PK + business key retained)
-- ---------------------------------------------------------------------

-- Date: role-played twice by the fact (booking date, travel date).
-- Surrogate key is a smart integer yyyymmdd.
CREATE TABLE dw.DimDate (
    date_key        INT          NOT NULL,              -- surrogate, e.g. 20260110
    full_date       DATE         NOT NULL,              -- business key
    [year]          SMALLINT     NOT NULL,
    [quarter]       TINYINT      NOT NULL,
    [month]         TINYINT      NOT NULL,
    month_name      VARCHAR(12)  NOT NULL,
    day_of_month    TINYINT      NOT NULL,
    day_of_week     TINYINT      NOT NULL,
    day_name        VARCHAR(12)  NOT NULL,
    is_weekend      BIT          NOT NULL,
    CONSTRAINT PK_DimDate      PRIMARY KEY (date_key),
    CONSTRAINT UQ_DimDate_date UNIQUE (full_date)
);
GO

-- Passenger: SCD Type 2 (tier / home airport change over time, see stg_passenger_updates).
-- passenger_id is NOT unique here; a passenger has one row per version.
CREATE TABLE dw.DimPassenger (
    passenger_key        INT IDENTITY(1,1) NOT NULL,    -- surrogate
    passenger_id         INT          NOT NULL,         -- business key
    passenger_name       VARCHAR(100) NOT NULL,
    home_airport_code    CHAR(3)      NULL,
    frequent_flyer_tier  VARCHAR(20)  NULL,
    signup_date          DATE         NULL,
    effective_date       DATE         NOT NULL,
    expiry_date          DATE         NOT NULL CONSTRAINT DF_DimPassenger_expiry  DEFAULT ('9999-12-31'),
    is_current           BIT          NOT NULL CONSTRAINT DF_DimPassenger_current DEFAULT (1),
    CONSTRAINT PK_DimPassenger     PRIMARY KEY (passenger_key),
    CONSTRAINT UQ_DimPassenger_ver UNIQUE (passenger_id, effective_date)
);
GO

-- Airport: role-played twice by the fact (origin, destination).
CREATE TABLE dw.DimAirport (
    airport_key   INT IDENTITY(1,1) NOT NULL,           -- surrogate
    airport_code  CHAR(3)      NOT NULL,                -- business key
    airport_name  VARCHAR(100) NOT NULL,
    city          VARCHAR(60)  NULL,
    country       VARCHAR(60)  NULL,
    region        VARCHAR(40)  NULL,
    CONSTRAINT PK_DimAirport      PRIMARY KEY (airport_key),
    CONSTRAINT UQ_DimAirport_code UNIQUE (airport_code)
);
GO

-- Aircraft
CREATE TABLE dw.DimAircraft (
    aircraft_key   INT IDENTITY(1,1) NOT NULL,          -- surrogate
    aircraft_code  VARCHAR(10) NOT NULL,                -- business key
    model          VARCHAR(50) NOT NULL,
    manufacturer   VARCHAR(50) NULL,
    seat_capacity  INT         NULL,
    CONSTRAINT PK_DimAircraft      PRIMARY KEY (aircraft_key),
    CONSTRAINT UQ_DimAircraft_code UNIQUE (aircraft_code)
);
GO

-- Flight: descriptive flight attributes. Route and aircraft are carried
-- on the fact as their own keys (star, not snowflake).
CREATE TABLE dw.DimFlight (
    flight_key     INT IDENTITY(1,1) NOT NULL,          -- surrogate
    flight_id      INT         NOT NULL,                -- business key
    flight_number  VARCHAR(10) NOT NULL,
    flight_date    DATE        NOT NULL,
    CONSTRAINT PK_DimFlight    PRIMARY KEY (flight_key),
    CONSTRAINT UQ_DimFlight_id UNIQUE (flight_id)
);
GO

-- ---------------------------------------------------------------------
-- FACT: one row per booking
-- ---------------------------------------------------------------------
CREATE TABLE dw.FactTicketSales (
    ticket_sales_key     BIGINT IDENTITY(1,1) NOT NULL,

    -- Foreign keys (surrogate keys of the dimensions)
    booking_date_key     INT NOT NULL,
    travel_date_key      INT NOT NULL,
    passenger_key        INT NOT NULL,
    flight_key           INT NOT NULL,
    origin_airport_key   INT NOT NULL,
    dest_airport_key     INT NOT NULL,
    aircraft_key         INT NOT NULL,

    -- Degenerate dimensions (no dimension table needed)
    booking_id           INT         NOT NULL,          -- enforces the grain (UNIQUE below)
    fare_class           VARCHAR(20) NOT NULL,
    booking_status       VARCHAR(20) NOT NULL,

    -- Additive measures only
    fare_amount          DECIMAL(12,2) NOT NULL,
    tax_amount           DECIMAL(12,2) NOT NULL,
    miles_earned         INT           NOT NULL,
    booking_count        SMALLINT      NOT NULL CONSTRAINT DF_FTS_booking_count DEFAULT (1),

    CONSTRAINT PK_FactTicketSales        PRIMARY KEY (ticket_sales_key),
    CONSTRAINT UQ_FTS_booking_id         UNIQUE (booking_id),
    CONSTRAINT CK_FTS_fare_class         CHECK (fare_class IN ('Economy','Premium Economy','Business','First')),
    CONSTRAINT CK_FTS_booking_status     CHECK (booking_status IN ('Confirmed','Cancelled','NoShow')),
    CONSTRAINT CK_FTS_booking_count      CHECK (booking_count = 1),

    CONSTRAINT FK_FTS_booking_date  FOREIGN KEY (booking_date_key)   REFERENCES dw.DimDate (date_key),
    CONSTRAINT FK_FTS_travel_date   FOREIGN KEY (travel_date_key)    REFERENCES dw.DimDate (date_key),
    CONSTRAINT FK_FTS_passenger     FOREIGN KEY (passenger_key)      REFERENCES dw.DimPassenger (passenger_key),
    CONSTRAINT FK_FTS_flight        FOREIGN KEY (flight_key)         REFERENCES dw.DimFlight (flight_key),
    CONSTRAINT FK_FTS_origin        FOREIGN KEY (origin_airport_key) REFERENCES dw.DimAirport (airport_key),
    CONSTRAINT FK_FTS_dest          FOREIGN KEY (dest_airport_key)   REFERENCES dw.DimAirport (airport_key),
    CONSTRAINT FK_FTS_aircraft      FOREIGN KEY (aircraft_key)       REFERENCES dw.DimAircraft (aircraft_key)
);
GO

/*-- Nonclustered indexes on foreign keys for join / filter performance
CREATE NONCLUSTERED INDEX ix_fts_booking_date ON dw.FactTicketSales (booking_date_key);
CREATE NONCLUSTERED INDEX ix_fts_travel_date  ON dw.FactTicketSales (travel_date_key);
CREATE NONCLUSTERED INDEX ix_fts_passenger    ON dw.FactTicketSales (passenger_key);
CREATE NONCLUSTERED INDEX ix_fts_flight       ON dw.FactTicketSales (flight_key);
CREATE NONCLUSTERED INDEX ix_fts_origin       ON dw.FactTicketSales (origin_airport_key);
CREATE NONCLUSTERED INDEX ix_fts_dest         ON dw.FactTicketSales (dest_airport_key);
CREATE NONCLUSTERED INDEX ix_fts_aircraft     ON dw.FactTicketSales (aircraft_key);
GO */