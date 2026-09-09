/*
Q3 (Warm-up): Top 3 products by completed revenue, per category.
Required output: category_name, product_name, total_revenue, revenue_rank

dim_product.category_id points at a product's LEAF category, so only the
15 leaf categories that directly hold products appear in this result --
the 11 parent/rollup categories (e.g. "Electronics", root "All Products")
correctly don't appear here, since rolling revenue UP the tree is a
different, harder problem (see Q6/Q7 for the recursive-tree techniques).

RANK() (not ROW_NUMBER/DENSE_RANK) is used so that a tie in revenue
produces a shared rank rather than an arbitrary tiebreak.
*/

WITH product_revenue AS (
    SELECT
        p.category_id,
        p.product_id,
        p.product_name,
        SUM(oi.line_amount) AS total_revenue
    FROM dbo.fact_order_items oi
    JOIN dbo.fact_orders o ON o.order_id = oi.order_id
    JOIN dbo.dim_product p ON p.product_id = oi.product_id
    WHERE o.order_status = 'Completed'
    GROUP BY p.category_id, p.product_id, p.product_name
),
ranked AS (
    SELECT
        pr.*,
        c.category_name,
        RANK() OVER (PARTITION BY pr.category_id ORDER BY pr.total_revenue DESC) AS revenue_rank
    FROM product_revenue pr
    JOIN dbo.dim_category c ON c.category_id = pr.category_id
)
SELECT
    category_name,
    product_name,
    total_revenue,
    revenue_rank
FROM ranked
WHERE revenue_rank <= 3
ORDER BY category_name, revenue_rank;
