-- Deterministic seed data.
--   * :booking_count bookings (default 50,000 via SEED_BOOKINGS; the brief asks for at least 100).
--     The larger default makes the effect of the index measurable instead of theoretical.
--   * 10 cities, 8 organisations, 6 statuses, created_at spread over the last 365 days.
--   * Booking events for ~70% of bookings, consistent with each booking's status.
-- setseed() + md5-derived UUIDs make every run produce the same data, which keeps the backup/restore
-- checksums and EXPLAIN output reproducible. Re-running is safe (ON CONFLICT DO NOTHING).

SELECT setseed(0.42) \g /dev/null

WITH base AS (
    SELECT
        g,
        1 + floor(random() * 8)::int                 AS org_n,
        1 + floor(random() * 10)::int                AS city_n,
        1 + floor(random() * 25)::int                AS hotel_n,
        random()                                     AS status_r,
        now() - random() * interval '365 days'       AS created_at,
        1 + floor(random() * 60)::int                AS lead_days,
        1 + floor(random() * 7)::int                 AS nights,
        round((1500 + random() * 18500)::numeric, 2) AS amount
    FROM generate_series(1, :booking_count) AS g
),
named AS (
    SELECT
        b.*,
        (ARRAY['delhi', 'mumbai', 'bengaluru', 'hyderabad', 'chennai',
               'kolkata', 'pune', 'jaipur', 'goa', 'ahmedabad'])[b.city_n] AS city
    FROM base b
)
INSERT INTO hotel_bookings (id, org_id, hotel_id, city, checkin_date, checkout_date, amount, status, created_at)
SELECT
    md5('booking-' || n.g)::uuid,
    md5('org-' || n.org_n)::uuid,
    n.city || '-hotel-' || lpad(n.hotel_n::text, 3, '0'),
    n.city,
    (n.created_at + n.lead_days * interval '1 day')::date,
    (n.created_at + (n.lead_days + n.nights) * interval '1 day')::date,
    n.amount,
    CASE
        WHEN n.status_r < 0.35 THEN 'confirmed'
        WHEN n.status_r < 0.65 THEN 'completed'
        WHEN n.status_r < 0.75 THEN 'pending'
        WHEN n.status_r < 0.90 THEN 'cancelled'
        WHEN n.status_r < 0.95 THEN 'checked_in'
        ELSE 'refunded'
    END,
    n.created_at
FROM named n
ON CONFLICT (id) DO NOTHING;

-- Events for ~70% of bookings (selection is a stable hash of the id, not random()).
WITH selected AS (
    SELECT *
    FROM hotel_bookings
    WHERE abs(hashtext(id::text)) % 10 < 7
      AND NOT EXISTS (SELECT 1 FROM booking_events e WHERE e.booking_id = hotel_bookings.id)
),
events AS (
    SELECT id AS booking_id, 'booking_created' AS event_type,
           jsonb_build_object('amount', amount, 'city', city, 'hotel_id', hotel_id,
                              'channel', (ARRAY['web', 'mobile', 'partner_api'])[1 + abs(hashtext(id::text)) % 3]) AS payload,
           created_at
    FROM selected
    UNION ALL
    SELECT id, 'payment_captured',
           jsonb_build_object('amount', amount, 'currency', 'INR'),
           created_at + interval '5 minutes'
    FROM selected WHERE status IN ('confirmed', 'checked_in', 'completed', 'refunded')
    UNION ALL
    SELECT id, 'checked_in', jsonb_build_object('hotel_id', hotel_id),
           checkin_date + interval '14 hours'
    FROM selected WHERE status IN ('checked_in', 'completed')
    UNION ALL
    SELECT id, 'checked_out', jsonb_build_object('hotel_id', hotel_id),
           checkout_date + interval '11 hours'
    FROM selected WHERE status = 'completed'
    UNION ALL
    SELECT id, 'booking_cancelled', jsonb_build_object('reason', 'customer_request'),
           created_at + interval '1 day'
    FROM selected WHERE status IN ('cancelled', 'refunded')
    UNION ALL
    SELECT id, 'refund_issued', jsonb_build_object('amount', amount, 'currency', 'INR'),
           created_at + interval '2 days'
    FROM selected WHERE status = 'refunded'
)
INSERT INTO booking_events (booking_id, event_type, payload, created_at)
SELECT booking_id, event_type, payload, created_at
FROM events
ORDER BY booking_id, created_at;
