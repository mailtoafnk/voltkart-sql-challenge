/*
Q5 (Core): Customers split into 4 equal-sized quartiles by lifetime
completed spend, with count and average spend per quartile.
Required output: spend_quartile, customer_count, avg_lifetime_spend

NTILE(4) sorts customers by spend and slices them into 4 equal-SIZED
groups (not equal spend RANGES) -- lowest-spending 25% = quartile 1,
highest-spending 25% = quartile 4.

Scoped to fact_orders only (matching the hint), not joined to
dim_customer -- a customer with zero completed orders simply wouldn't
appear here at all, rather than showing up with $0 in quartile 1. On
this dataset it's moot: all 2,000 registered customers have at least one
completed order, so the populations are identical either way.
*/

WITH customer_spend AS (
    SELECT
        customer_id,
        SUM(order_total) AS lifetime_spend
    FROM dbo.fact_orders
    WHERE order_status = 'Completed'
    GROUP BY customer_id
),
quartiled AS (
    SELECT
        customer_id,
        lifetime_spend,
        NTILE(4) OVER (ORDER BY lifetime_spend) AS spend_quartile
    FROM customer_spend
)
SELECT
    spend_quartile,
    COUNT(*) AS customer_count,
    AVG(lifetime_spend) AS avg_lifetime_spend
FROM quartiled
GROUP BY spend_quartile
ORDER BY spend_quartile;
