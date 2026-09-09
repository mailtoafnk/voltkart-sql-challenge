/*
Q1 (Warm-up): Top 20 completed orders by value, with customer and sales rep.
Required output: order_id, order_date, customer_name, sales_rep_name, order_total

Note: sales_rep_id in fact_orders is a foreign key into dim_employee (the
self-referencing org-chart table) -- there is no separate "sales rep" table.
A Sales Rep is just a dim_employee row where role = 'Sales Rep'.

Approach: filter + sort + cut down to the top 20 rows FIRST (inside the CTE),
then join to dim_customer/dim_employee only for those 20 rows -- instead of
joining every completed order to both dimension tables and only then sorting
and discarding all but 20. On this table size (30K orders) the optimizer
likely reaches an equivalent plan either way, but narrowing before fanning
out into joins is a good habit that matters more as fact_orders grows.

Note: lower(order_status) = 'completed' works correctly (SQL Server's default
collation is case-insensitive), though it is functionally equivalent here to
a plain order_status = 'Completed' comparison.
*/

WITH top_orders AS (
    SELECT TOP 20
        order_id, order_date, customer_id, sales_rep_id, order_total
    FROM dbo.fact_orders
    WHERE lower(order_status) = 'completed'
    ORDER BY order_total DESC
)
SELECT
    t.order_id,
    t.order_date,
    dc.customer_name,
    de.employee_name AS sales_rep_name,
    t.order_total
FROM top_orders t
JOIN dbo.dim_customer dc ON dc.customer_id = t.customer_id
JOIN dbo.dim_employee de ON de.employee_id = t.sales_rep_id
ORDER BY t.order_total DESC;
