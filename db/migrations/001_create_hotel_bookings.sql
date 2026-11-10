-- 001: hotel_bookings
-- Based on the suggested schema, with deliberate hardening:
--   * created_at is TIMESTAMPTZ (stored as UTC) instead of TIMESTAMP, so "last 30 days" means the same
--     thing regardless of the client's TimeZone setting.
--   * CHECK constraints keep bad data out (unknown statuses, negative amounts, checkout before checkin).
--   * city must be lower-case, so the report query's `city = 'delhi'` can never silently miss 'Delhi'.

CREATE TABLE hotel_bookings (
    id            UUID          PRIMARY KEY DEFAULT gen_random_uuid(),
    org_id        UUID          NOT NULL,
    hotel_id      VARCHAR(100)  NOT NULL,
    city          VARCHAR(100)  NOT NULL,
    checkin_date  DATE          NOT NULL,
    checkout_date DATE          NOT NULL,
    amount        NUMERIC(12,2) NOT NULL,
    status        VARCHAR(50)   NOT NULL,
    created_at    TIMESTAMPTZ   NOT NULL DEFAULT now(),

    CONSTRAINT hotel_bookings_amount_non_negative CHECK (amount >= 0),
    CONSTRAINT hotel_bookings_dates_valid         CHECK (checkout_date > checkin_date),
    CONSTRAINT hotel_bookings_city_lowercase      CHECK (city = lower(city)),
    CONSTRAINT hotel_bookings_status_valid        CHECK (
        status IN ('pending', 'confirmed', 'checked_in', 'completed', 'cancelled', 'refunded')
    )
);

COMMENT ON TABLE  hotel_bookings      IS 'One row per hotel booking.';
COMMENT ON COLUMN hotel_bookings.city IS 'Normalised to lower case (enforced by CHECK).';
