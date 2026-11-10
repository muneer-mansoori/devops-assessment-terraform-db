-- 003: index for the city revenue report
--
--   SELECT org_id, status, COUNT(*), SUM(amount)
--   FROM hotel_bookings
--   WHERE city = 'delhi'
--     AND created_at >= NOW() - INTERVAL '30 days'
--   GROUP BY org_id, status;
--
-- * city first (equality), created_at second (range): the B-tree seeks straight to ('delhi', now-30d)
--   and reads one contiguous slice. Reversing the order would scan every city's last 30 days.
-- * INCLUDE (org_id, status, amount): every column the query touches is in the index, so PostgreSQL
--   answers it with an Index Only Scan and never visits the table heap.
--   INCLUDE columns sit only in the leaf pages, so they do not widen the search key.
-- * A partial index (WHERE created_at >= now() - '30 days') is not possible: index predicates must be
--   immutable and now() is not.
--
-- On a live production table, create it with CREATE INDEX CONCURRENTLY outside a transaction to avoid
-- blocking writes. Here the table is empty when the migration runs, so a plain CREATE INDEX is fine.

CREATE INDEX idx_hotel_bookings_city_created_at
    ON hotel_bookings (city, created_at)
    INCLUDE (org_id, status, amount);
