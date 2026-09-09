/*
Q7 (Core): For every employee, the total completed order value generated
by their whole team (themselves + everyone reporting under them, at any
depth). A Sales Rep's team is just themselves; a manager's is their
entire subtree.
Required output: employee_id, employee_name, role, team_total_revenue

Step 1 (subtree CTE): recursively builds every (root, member) pair -- i.e.
for every employee, who is in their downline at any depth, including
themselves. This is a different recursion shape than Q6: instead of
walking down from one fixed root, it walks down from every employee
simultaneously.

Step 2 (team_revenue CTE): joins those (root, member) pairs to
fact_orders on member = sales_rep_id, and sums by root -- this is
"attribute rep orders and sum up the tree" from the hint.

LEFT JOIN + COALESCE(..., 0) at the end guards against an employee whose
entire subtree happens to have zero completed orders (didn't occur in
this dataset, but is a real structural possibility).

Verified: CEO's team_total_revenue exactly equals the company-wide total
completed revenue, and each Sales Rep's number exactly matches their own
direct completed-order sum.
*/

WITH subtree AS (
    SELECT employee_id AS root_id, employee_id AS member_id
    FROM dbo.dim_employee

    UNION ALL

    SELECT s.root_id, e.employee_id
    FROM dbo.dim_employee e
    JOIN subtree s ON e.manager_id = s.member_id
),
team_revenue AS (
    SELECT
        s.root_id,
        SUM(o.order_total) AS team_total_revenue
    FROM subtree s
    JOIN dbo.fact_orders o
        ON o.sales_rep_id = s.member_id
        AND o.order_status = 'Completed'
    GROUP BY s.root_id
)
SELECT
    e.employee_id,
    e.employee_name,
    e.role,
    COALESCE(tr.team_total_revenue, 0) AS team_total_revenue
FROM dbo.dim_employee e
LEFT JOIN team_revenue tr ON tr.root_id = e.employee_id
ORDER BY e.employee_id;
