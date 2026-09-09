/*
Q10 (Stretch): Optimize the slow customer 2024-orders + lifetime-value
report.

THE REAL PROBLEM: WHERE YEAR(order_date) = 2024 is not SARGable --
wrapping the column in a function forces an Index Scan (read everything,
filter after) instead of an Index Seek, even with an index on order_date
present.

NOTE ON THE SUBQUERY: the correlated scalar subquery for lifetime_value
looked like it should recompute per row instead of once per customer, but
checking the actual execution plan showed SQL Server already flattens it
into a single aggregate + join internally -- confirmed by the ORIGINAL
query and this rewrite producing the exact same plan shape (two
Hash Match aggregate branches joined) and identical IO numbers before any
index existed. The CTE form below is kept for clarity/explicitness, not
because it measurably changed performance on its own.

FIX: rewrite YEAR(order_date)=2024 as a SARGable date range, and add
covering indexes so the date filter can seek and the lifetime-value join
can scan a narrower index instead of the full base tables.

Original (slow) query, for reference:

  SELECT o.customer_id, COUNT(*) AS orders_2024,
         (SELECT SUM(oi.line_amount)
            FROM fact_order_items oi
            JOIN fact_orders o2 ON o2.order_id = oi.order_id
           WHERE o2.customer_id = o.customer_id) AS lifetime_value
  FROM fact_orders o
  WHERE YEAR(o.order_date) = 2024
  GROUP BY o.customer_id;
*/

CREATE INDEX IX_fact_orders_order_date ON dbo.fact_orders (order_date) INCLUDE (customer_id);
CREATE INDEX IX_fact_order_items_order_id ON dbo.fact_order_items (order_id) INCLUDE (line_amount);

WITH orders_2024 AS (
    SELECT
        customer_id,
        COUNT(*) AS orders_2024
    FROM dbo.fact_orders
    WHERE order_date >= '2024-01-01' AND order_date < '2025-01-01'  -- SARGable range, not YEAR()
    GROUP BY customer_id
),
customer_ltv AS (
    SELECT
        o.customer_id,
        SUM(oi.line_amount) AS lifetime_value
    FROM dbo.fact_orders o
    JOIN dbo.fact_order_items oi ON oi.order_id = o.order_id
    GROUP BY o.customer_id  -- lifetime = all history, matching the original's semantics
)
SELECT
    o24.customer_id,
    o24.orders_2024,
    ltv.lifetime_value
FROM orders_2024 o24
LEFT JOIN customer_ltv ltv ON ltv.customer_id = o24.customer_id;

/*
RESULTS (SET STATISTICS IO, before vs after -- see screenshots/ folder for
the execution plans and results-writeup.md for the full narrative):

  Table              Before   After   Change
  fact_orders          506     298    ~41% fewer logical reads
  fact_order_items     415     223    ~46% fewer logical reads

Execution plan confirms two separate, independent wins:
  - The 2024-filter half went from Index Scan (cost 5%) to Index Seek
    (cost 2%) -- the SARGable rewrite in action.
  - The lifetime-value half (unfiltered, needs full history) still scans
    in both versions -- no predicate to seek on -- but scans the new
    narrower covering index instead of the full base tables, which is
    where the rest of the improvement came from.
  - Re-running the ORIGINAL query with the same indexes in place still
    showed 506 / 415 reads, completely unchanged -- direct proof that the
    YEAR() wrapper alone blocks the optimizer from using the new index,
    regardless of whether it exists.
*/
