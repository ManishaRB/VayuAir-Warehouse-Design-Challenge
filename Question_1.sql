/*1. State the grain of the sales fact you will build, written as a comment, and
classify every candidate column from bronze_bookings (joined to its flight) as a dimension
key or a measure. Add one sentence naming which measures are additive and giving one
example of a value that would not be additive. Acceptance criteria: a clear one-row grain
statement; a correct split of columns into dimension keys versus measures; one additiveversus-non-additive note.
----------------------------------
           GRAIN
----------------------------------
 GRAIN: one row in fact_sales = one booking (one booking_id): a single passenger's booking
 on a single flight, in one fare class, with its status (Confirmed / Cancelled / NoShow).

 Source: bronze_bookings joined to bronze_flights on flight_id (1:1 per booking, no fan-out). */

SELECT *
FROM dbo.bronze_bookings AS booking
LEFT JOIN dbo.bronze_flights AS flight
ON booking.flight_id = flight.flight_id

/*Column classification (bronze_bookings joined to its flight)

Column				Source				Role			Notes
booking_id			bookings	Degenerate dimension	Identifies the grain and has no dimension table of its own.
passenger_id		bookings	Dimension key			Links to dim_passenger. Use the surrogate key if the passenger dimension is SCD-tracked (see stg_passenger_updates).
flight_id			bookings	Dimension key			Links to dim_flight (flight_number, aircraft, route).
booking_date		bookings	Dimension key			Role-playing date, links to dim_date.
travel_date			bookings	Dimension key			Role-playing date, links to dim_date. It always equals flight_date, so flight_date is redundant.
fare_class			bookings	Dimension key			A low-cardinality attribute with 4 values. Make it a small dim_fare_class, or a junk dimension together with booking_status.
booking_status		bookings	Dimension key			3 values. Treat it as a status dimension or flag, not a measure.
origin_airport_code	flights		Dimension key			Role-playing airport (origin), links to dim_airport.
dest_airport_code	flights		Dimension key			Role-playing airport (destination), links to dim_airport.
aircraft_code		flights		Dimension key			Links to dim_aircraft. It could instead live inside dim_flight.
flight_number		flights		Dimension attribute		Belongs in dim_flight, not on the fact.
fare_amount			bookings	Measure					Currency amount.
tax_amount			bookings	Measure					Currency amount.
miles_earned		bookings	Measure					Integer count of miles.

------------------
	Additive 
------------------
fare_amount, 
tax_amount, 
miles_earned,
booking_count
These are fully additive across every dimension (passenger, flight, date, fare class, status).

------------------
A non-additive
------------------
Average fare per booking.
Those must be recomputed as SUM(tax_amount) / SUM(fare_amount) and never summed or averaged across rows. */




