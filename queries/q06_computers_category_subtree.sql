/*
Q6 (Core): Recursive query listing every category in the subtree rooted at
'Computers', at any depth, with depth level and a readable path.
Required output: category_id, category_name, depth_level, category_path

Anchor member: starts at 'Computers' itself (depth 0).
Recursive member: joins dim_category back to the CTE on
parent_category_id = the CTE's category_id, finding one more level of
children each pass. Stops automatically once a pass finds no new children.

CAST(... AS NVARCHAR(MAX)) on category_path is required, not decorative --
SQL Server needs the recursive member's column types to match the anchor
exactly, and without an explicit cast, string concatenation can infer a
shorter type that silently truncates on a deeper tree.
*/

WITH subtree AS (
    SELECT
        category_id,
        category_name,
        parent_category_id,
        0 AS depth_level,
        CAST(category_name AS NVARCHAR(MAX)) AS category_path
    FROM dbo.dim_category
    WHERE category_name = 'Computers'

    UNION ALL

    SELECT
        c.category_id,
        c.category_name,
        c.parent_category_id,
        s.depth_level + 1,
        CAST(s.category_path + ' > ' + c.category_name AS NVARCHAR(MAX))
    FROM dbo.dim_category c
    JOIN subtree s ON c.parent_category_id = s.category_id
)
SELECT category_id, category_name, depth_level, category_path
FROM subtree
ORDER BY depth_level, category_id;
