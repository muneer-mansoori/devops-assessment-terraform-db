-- 002: booking_events
-- Append-only event log per booking. Added a foreign key (not in the suggested schema) so events can never
-- point at a booking that does not exist; deleting a booking removes its events.

CREATE TABLE booking_events (
    id          BIGSERIAL    PRIMARY KEY,
    booking_id  UUID         NOT NULL REFERENCES hotel_bookings (id) ON DELETE CASCADE,
    event_type  VARCHAR(100) NOT NULL,
    payload     JSONB,
    created_at  TIMESTAMPTZ  NOT NULL DEFAULT now()
);

-- PostgreSQL does not index foreign keys automatically. This index serves both the FK
-- (cascading deletes, joins) and the common "timeline of one booking" lookup, in order.
CREATE INDEX idx_booking_events_booking_id_created_at
    ON booking_events (booking_id, created_at);

COMMENT ON TABLE booking_events IS 'Append-only lifecycle events for hotel_bookings.';
