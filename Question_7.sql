/*Curate
7. Two written deliverables.
(a) Map every table in this pipeline to a medallion layer (bronze, silver, or gold) and say in a
line why each sits where. 
(b) Write a data contract for the bronze_bookings feed. Acceptance
criteria: every table is assigned a layer with a short reason; the contract states the schema and
types, the allowed values for fare_class and booking_status, a freshness or delivery SLA,
the owner, and one example each of a breaking and a non-breaking change.
QUESTION 7: TWO WRITTEN DELIVERABLES

(a) Map every table in the pipeline to a medallion layer (bronze, silver or
    gold) and give a one-line reason for each.
(b) Write a data contract for the bronze_bookings feed.

Acceptance criteria: every table is assigned a layer with a short reason. The
contract states the schema and types, the allowed values for fare_class and
booking_status, a freshness or delivery SLA, the owner, and one example each
of a breaking and a non-breaking change.


==========================================================
PART (a): MEDALLION LAYER FOR EVERY TABLE
==========================================================

STEP 1: DEFINE THE LAYERS

  Bronze  Raw data exactly as received, with no cleaning.
  Silver  Cleaned, conformed and keyed, with history kept, but not yet
          shaped for one business question.
  Gold    Business-ready: modelled for reporting, with measures at a
          declared grain.


STEP 2: ASSIGN EACH TABLE

  bronze_bookings          -> BRONZE
      Raw booking feed, loaded as-is.

  bronze_flights           -> BRONZE
      Raw flight schedule feed, unchanged.

  bronze_passengers        -> BRONZE
      Raw passenger master snapshot, unchanged.

  bronze_airports          -> BRONZE
      Raw airport reference, still flattened (city, country and region in
      one table).

  bronze_aircraft          -> BRONZE
      Raw aircraft reference, unchanged.

  stg_passenger_updates    -> BRONZE
      Raw landing area for the change feed. It carries no keys or dates
      and has not yet been applied to anything.

  DimDate                  -> SILVER
      Generated reference calendar with a yyyymmdd key, shared by every
      fact.

  DimPassenger             -> SILVER
      Cleaned and historized with SCD2 versions and surrogate keys.

  DimAirport, DimCity,
  DimCountry               -> SILVER
      Conformed geography, deduplicated and normalised into a linked
      hierarchy.

  DimAircraft              -> SILVER
      Conformed reference entity with a surrogate key.

  DimFlight                -> SILVER
      Conformed flight entity, deduplicated with a surrogate key.

  FactTicketSales          -> GOLD
      One row per booking, additive measures and surrogate-key foreign
      keys, partitioned by travel date for reporting.

  vDimAirportGeo           -> GOLD
      Flattened airport-to-country view for BI users.

==========================================================
PART (b): DATA CONTRACT FOR bronze_bookings
==========================================================

Everything in the schema and rules sections below was checked against the
40,000 rows you uploaded. The SLA, owner and notice period are proposals,
because I can't know them from the data. The owner and the SLA need
confirming by the real feed owner.


STEP 1: SCHEMA AND TYPES

  booking_id       INT            NOT NULL
      Primary key, unique. Currently 9000000-9039999.

  passenger_id     INT            NOT NULL
      Must exist in bronze_passengers.

  flight_id        INT            NOT NULL
      Must exist in bronze_flights.

  booking_date     DATE           NOT NULL
      Never later than travel_date.

  travel_date      DATE           NOT NULL
      Must equal the flight's flight_date.

  fare_class       VARCHAR(20)    NOT NULL
      One of the allowed values in Step 2.

  fare_amount      DECIMAL(12,2)  NOT NULL
      Greater than 0, at most 2 decimals.

  tax_amount       DECIMAL(12,2)  NOT NULL
      Greater than or equal to 0, at most 2 decimals.

  booking_status   VARCHAR(20)    NOT NULL
      One of the allowed values in Step 2.

  miles_earned     INT            NOT NULL
      Greater than or equal to 0.


STEP 2: ALLOWED VALUES

  fare_class:      Economy, Premium Economy, Business, First
  booking_status:  Confirmed, Cancelled, NoShow

  Values are case-sensitive and have no leading or trailing spaces.


STEP 3: DELIVERY SLA (PROPOSED)

  - Delivered once a day, as a full file with one row per booking, by
    06:00 UTC.
  - A delivery counts as late after 08:00 UTC, and the owner must notify
    consumers.
  - Quality gates on every delivery:
      * no nulls
      * unique booking_id
      * no orphan passenger or flight IDs
      * only the allowed values listed above


STEP 4: OWNER (TO BE CONFIRMED)

  Owner:     The booking platform team that produces the feed, with a named
             contact and email to fill in.
  Consumer:  The data warehouse team that loads FactTicketSales.

  Open item: The feed has no currency column. Confirm with the owner whether
             all amounts are in one currency, and if so, which.


STEP 5: CHANGE RULES

  The owner gives consumers at least 14 days' notice of any breaking change
  (proposed).

  Breaking change example:
      Adding a new fare_class value such as Basic. The warehouse rejects any
      value outside the four listed, so this would fail the load. Renaming
      fare_amount to base_fare would break it too.

  Non-breaking change example:
      Adding a new optional column at the end of the file, such as
      booking_channel. Existing consumers ignore it and keep working.