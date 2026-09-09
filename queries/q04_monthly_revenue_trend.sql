/*
Q4 (Core): Monthly completed revenue, with a cumulative running total and
month-over-month % change.
Required output: order_month (YYYY-MM), monthly_revenue, running_total, mom_pct_change

SUM(...) OVER (ORDER BY order_month ROWS UNBOUNDED PRECEDING) gives the
running total. LAG() pulls the previous row's value into the current row
so MoM % change can be computed without a self-join.

The first month (2023-01) has mom_pct_change = NULL, since there's no
prior month to compare against -- expected, not a bug.

Note: the data only runs through 2025-03-15, so the last month (2025-03)
is a partial month and shows an artificially large revenue drop. This is a
data-coverage artifact, not a real business downturn -- call it out
explicitly when presenting this trend to a stakeholder.
*/

WITH monthly AS (
    SELECT
        CONVERT(char(7), order_date, 126) AS order_month,
        SUM(order_total) AS monthly_revenue
    FROM dbo.fact_orders
    WHERE order_status = 'Completed'
    GROUP BY CONVERT(char(7), order_date, 126)
)
SELECT
    order_month,
    monthly_revenue,
    SUM(monthly_revenue) OVER (ORDER BY order_month ROWS UNBOUNDED PRECEDING) AS running_total,
    ROUND(
        (monthly_revenue - LAG(monthly_revenue) OVER (ORDER BY order_month))
        / LAG(monthly_revenue) OVER (ORDER BY order_month) * 100
    , 2) AS mom_pct_change
FROM monthly
ORDER BY order_month;
