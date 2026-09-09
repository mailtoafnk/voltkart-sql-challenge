/*
Q9 (Stretch): Single MERGE applying the cdc_product_changes feed to
dim_product, honoring the I/U/D operation codes.
Acceptance criteria: one MERGE handling all three operations;
verification query showing inserted/updated/deleted products.

WHEN NOT MATCHED BY TARGET AND source.operation = 'I' (not just a bare
WHEN NOT MATCHED BY TARGET) is deliberate: it guards against a malformed
feed row -- e.g. a 'U' or 'D' row referencing a product_id that doesn't
exist in dim_product -- being silently turned into an unintended INSERT.

WARNING: this statement mutates dim_product (including real deletes).
Re-running it a second time is a no-op / would need a fresh import to
retest cleanly.

On this dataset: 35 change rows -- 10 I (all genuinely new product_ids),
20 U (all matching existing products), 5 D (all matching existing
products). Expected dim_product row count: 400 -> 405.
*/

-- BEFORE: starting row count
SELECT COUNT(*) AS dim_product_row_count_before FROM dbo.dim_product;

MERGE dbo.dim_product AS target
USING dbo.cdc_product_changes AS source
    ON target.product_id = source.product_id
WHEN MATCHED AND source.operation = 'U' THEN
    UPDATE SET
        target.product_name  = source.product_name,
        target.category_id   = source.category_id,
        target.unit_price    = source.unit_price,
        target.unit_cost     = source.unit_cost,
        target.launch_date   = source.launch_date
WHEN MATCHED AND source.operation = 'D' THEN
    DELETE
WHEN NOT MATCHED BY TARGET AND source.operation = 'I' THEN
    INSERT (product_id, product_name, category_id, unit_price, unit_cost, launch_date)
    VALUES (source.product_id, source.product_name, source.category_id, source.unit_price, source.unit_cost, source.launch_date);

-- AFTER: should be 400 + 10 - 5 = 405
SELECT COUNT(*) AS dim_product_row_count_after FROM dbo.dim_product;

-- Verification: change counts by operation
SELECT source.operation, COUNT(*) AS change_count
FROM dbo.cdc_product_changes source
GROUP BY source.operation
ORDER BY source.operation;

-- Confirm deleted products are actually gone
SELECT c.product_id, c.product_name
FROM dbo.cdc_product_changes c
WHERE c.operation = 'D'
  AND NOT EXISTS (SELECT 1 FROM dbo.dim_product p WHERE p.product_id = c.product_id);

-- Confirm inserted products now exist with the feed's values
SELECT p.*
FROM dbo.dim_product p
JOIN dbo.cdc_product_changes c ON c.product_id = p.product_id AND c.operation = 'I';
