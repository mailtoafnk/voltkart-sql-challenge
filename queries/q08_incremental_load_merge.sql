/*
Q8 (Core): Single MERGE for an incremental load from stg_orders_incr into
fact_orders -- update orders that changed, insert orders that are new.
Acceptance criteria: one MERGE statement; matched orders updated
(status + total); new orders inserted; verification query showing row
count before/after and a sample of updated rows.

WARNING: this statement mutates fact_orders. Re-running it a second time
is a no-op (nothing left in stg_orders_incr would be "new" or "changed").
To reset for a clean re-test, drop and re-import fact_orders from the
original CSV.

On this dataset: stg_orders_incr has 800 rows -- 500 genuinely new orders,
300 matching existing orders (all 300 with real status/total differences,
no no-op updates). Expected fact_orders row count: 30,000 -> 30,500.
*/

-- BEFORE: starting row count
SELECT COUNT(*) AS fact_orders_row_count_before FROM dbo.fact_orders;

MERGE dbo.fact_orders AS target
USING dbo.stg_orders_incr AS source
    ON target.order_id = source.order_id
WHEN MATCHED AND (
        target.order_status <> source.order_status
     OR target.order_total  <> source.order_total
    ) THEN
    UPDATE SET
        target.order_status = source.order_status,
        target.order_total  = source.order_total
WHEN NOT MATCHED BY TARGET THEN
    INSERT (order_id, order_date, customer_id, sales_rep_id, order_status, order_total)
    VALUES (source.order_id, source.order_date, source.customer_id, source.sales_rep_id, source.order_status, source.order_total);

-- AFTER: should be 30,000 + 500 new = 30,500
SELECT COUNT(*) AS fact_orders_row_count_after FROM dbo.fact_orders;

-- Sample of updated rows: orders that existed both before and in today's batch
SELECT TOP 10
    fo.order_id, fo.order_date, fo.customer_id, fo.sales_rep_id, fo.order_status, fo.order_total
FROM dbo.fact_orders fo
JOIN dbo.stg_orders_incr s ON s.order_id = fo.order_id
ORDER BY fo.order_id;
