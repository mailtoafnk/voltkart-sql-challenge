/*
Q2 (Warm-up): Customers who have never placed an order (any status -- not
just Completed, since even a Cancelled/Returned order still means they
"placed" one).
Required output: customer_id, customer_name, signup_date

NOT EXISTS is used instead of NOT IN because NOT IN silently returns zero
rows for everyone if the subquery's column ever contains a NULL. NOT EXISTS
just checks row existence, so it isn't vulnerable to that trap.

On this dataset, every one of the 2,000 customers has placed at least one
order, so this query correctly returns 0 rows -- that's the right answer,
not a bug.
*/

SELECT
    dc.customer_id,
    dc.customer_name,
    dc.signup_date
FROM dbo.dim_customer dc
WHERE NOT EXISTS (
    SELECT 1
    FROM dbo.fact_orders fo
    WHERE fo.customer_id = dc.customer_id
);
