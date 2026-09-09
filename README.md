# Voltkart SQL Challenge — Advanced SQL for Modern Data Engineering

Codebasics Data Engineering Bootcamp. Engine: SQL Server (T-SQL), run in SSMS on the `Voltkart` database.

Browse all 11 solutions in an interactive query bench: [live here](https://mailtoafnk.github.io/voltkart-sql-challenge/)

## Repo structure

```
queries/
  q01_top_20_orders.sql
  q02_customers_never_ordered.sql
  q03_top3_products_per_category.sql
  q04_monthly_revenue_trend.sql
  q05_customer_spend_quartiles.sql
  q06_computers_category_subtree.sql
  q07_employee_team_revenue_rollup.sql
  q08_incremental_load_merge.sql
  q09_cdc_product_changes_merge.sql
  q10_optimize_customer_report.sql
  q11_bonus_loyalty_streaks.sql
screenshots/
  q10_execution_plan_before_indexscan.png
  q10_execution_plan_after_indexseek.png
docs/
  index.html   <- interactive query bench (see "Publishing the query bench")
README.md   <- this file (results write-up)
```

Each `.sql` file is self-contained and can be run directly against the `Voltkart` database. Comments at the top of each file explain the approach and any non-obvious design decisions.

**Note on Q8/Q9**: these two files run `MERGE` statements that mutate `fact_orders` and `dim_product`. To re-test them from a clean slate, drop and re-import those tables from the original CSVs first.

## Results write-up

### Warm-up

**Q1 — Top 20 completed orders.** Filters, sorts, and narrows `fact_orders` down to the top 20 rows inside a CTE *first*, then joins those 20 rows to `dim_customer` and `dim_employee` (the latter for the sales rep's name, since Sales Reps live in `dim_employee` alongside every other role) — rather than joining every completed order to both dimension tables and only discarding down to 20 afterward.

**Q2 — Customers who never ordered.** Anti-join with `NOT EXISTS` against `fact_orders`, with no status filter (a Cancelled order still counts as "having placed an order"). Result: **0 rows** — every one of the 2,000 customers in this dataset has placed at least one order, which is the correct answer for this data, not a bug.

**Q3 — Top 3 products by revenue per category.** Two-step CTE: aggregate `line_amount` per product first, then `RANK() OVER (PARTITION BY category_id ORDER BY total_revenue DESC)` and filter to rank ≤ 3. Only the 15 leaf categories that directly hold products appear (45 rows total, exactly 3 per category) — parent/rollup categories correctly have no rows here, since revenue only lives at the product/leaf level in `dim_product`.

### Core

**Q4 — Monthly revenue trend.** `SUM() OVER (... ROWS UNBOUNDED PRECEDING)` for the running total, `LAG()` for month-over-month % change. 27 months, Jan 2023 – Mar 2025, running total reaches ~₹1.78B. The final month (2025-03) is a partial month (data cuts off mid-March), which shows as an artificial revenue dip — flagged here so it isn't misread as a real trend.

**Q5 — Customer spend quartiles.** Per-customer `SUM()` of completed spend, then `NTILE(4)` to split into 4 equal-sized groups by rank (not by spend range). Result: exactly 500 customers per quartile, with average spend climbing sharply from ~₹227K (quartile 1) to ~₹2.27M (quartile 4) — a small group of high-value customers pulling the top bucket's average well above the rest.

**Q6 — Computers category subtree.** Recursive CTE anchored at `'Computers'`, recursing on `parent_category_id`, tracking depth and building a `>`-delimited path via string concatenation. Result: 8 categories total across 3 depth levels (Computers itself, then Laptops/Desktops/Components, then their children).

**Q7 — Employee team revenue rollup.** A different recursive shape than Q6: instead of walking down from one fixed root, the CTE builds every `(root_employee, descendant_employee)` pair simultaneously for all 58 employees, then joins that to `fact_orders` and sums by root. Verified two ways: the CEO's `team_total_revenue` exactly equals company-wide completed revenue, and every individual Sales Rep's number exactly matches their own direct order sum.

**Q8 — Incremental load MERGE.** Single `MERGE` on `order_id`, updating matched rows only when status/total actually differ, inserting unmatched source rows. On this batch: 800 staged rows = 500 new + 300 changed (all 300 genuine changes, no no-op updates). `fact_orders` row count: 30,000 → 30,500.

### Stretch

**Q9 — CDC MERGE on dim_product.** Single `MERGE` honoring the `I`/`U`/`D` operation codes explicitly (`WHEN NOT MATCHED ... AND operation = 'I'`, not a bare `WHEN NOT MATCHED`, to avoid a malformed `U`/`D` row silently creating a bad insert). On this feed: 10 inserts, 20 updates, 5 deletes, all clean matches. `dim_product` row count: 400 → 405.

**Q10 — Query optimization.** Full before/after numbers and execution-plan analysis below.

### Bonus

**Q11 — Loyalty streaks.** Classic gaps-and-islands: convert each active month to a sequential integer (`YEAR*12 + MONTH`), subtract `ROW_NUMBER()` per customer to label consecutive runs, then take the longest run per customer. All 2,000 customers get a streak value from 1 to 27 months. Spot-checked the top result: that customer has a completed order in literally every month of the dataset's 27-month span — the theoretical maximum, confirming the logic.

## Q10 — Optimization deep dive

**The slow query:**
```sql
SELECT o.customer_id, COUNT(*) AS orders_2024,
       (SELECT SUM(oi.line_amount)
          FROM fact_order_items oi
          JOIN fact_orders o2 ON o2.order_id = oi.order_id
         WHERE o2.customer_id = o.customer_id) AS lifetime_value
FROM fact_orders o
WHERE YEAR(o.order_date) = 2024
GROUP BY o.customer_id;
```

**Diagnosis.** `WHERE YEAR(o.order_date) = 2024` is not SARGable — wrapping the column in a function forces SQL Server to compute `YEAR()` for every row before it can check the filter, so no index on `order_date` can be seeked, only scanned. Separately, the correlated subquery *looked* like it should recompute each customer's full lifetime value once per matching row instead of once per customer — but checking the actual execution plan showed this wasn't true: SQL Server had already flattened it internally into the same two-branch aggregate-and-join shape as an explicit rewrite would produce, confirmed by the original query and a manually rewritten CTE version producing byte-for-byte identical `SET STATISTICS IO` numbers before any index existed.

**The fix** — SARGable date range + two covering indexes (full query in `queries/q10_optimize_customer_report.sql`):
```sql
CREATE INDEX IX_fact_orders_order_date ON dbo.fact_orders (order_date) INCLUDE (customer_id);
CREATE INDEX IX_fact_order_items_order_id ON dbo.fact_order_items (order_id) INCLUDE (line_amount);
```
```sql
WHERE order_date >= '2024-01-01' AND order_date < '2025-01-01'  -- instead of YEAR(order_date) = 2024
```

**Logical reads, before vs after** (`SET STATISTICS IO`):

| Table | Before | After | Change |
|---|---|---|---|
| `fact_orders` | 506 | 298 | ~41% fewer |
| `fact_order_items` | 415 | 223 | ~46% fewer |

**Why the plan changed** (see `screenshots/`): the query has two independent halves. The **2024-count half** went from `Index Scan` (cost 5%) to `Index Seek` (cost 2%) — direct result of the SARGable rewrite letting SQL Server jump straight to the 2024 rows instead of scanning the whole index and filtering afterward. The **lifetime-value half** is inherently unfiltered (it needs a customer's *entire* order history), so it still scans in both versions — there's nothing to seek toward — but scans the new narrower covering index instead of the full base tables, which is where the rest of the read reduction came from.

The most direct proof that the rewrite (not just the index) mattered for the filtered half: re-running the **original** query after the same two indexes were already in place still produced identical reads (506 / 415, unchanged). The `YEAR()` wrapper alone was enough to stop the optimizer from using the new index at all — the index existing wasn't sufficient on its own; the query had to be rewritten to actually take advantage of it.

## Publishing the query bench

`docs/index.html` is a self-contained, single-file page (no build step, no external assets besides Google Fonts) that presents all 11 questions with plain-language explanations, the final SQL with syntax highlighting, and verified results — including the Q10 execution-plan screenshots embedded directly in the page.

To make it public on GitHub:
1. Push this repo to GitHub (create a new repo, then `git init`, `git add .`, `git commit`, `git remote add origin <your-repo-url>`, `git push -u origin main`).
2. In the repo on GitHub: **Settings → Pages → Build and deployment → Source: Deploy from a branch → Branch: `main`, folder: `/docs` → Save**.
3. GitHub publishes it at `https://<your-username>.github.io/<repo-name>/` within a minute or two — that link is safe to share with anyone, since GitHub Pages serves it as a normal public webpage.

## Grading self-check

- **Correctness**: every query verified against the actual loaded data before being finalized here.
- **Logic & approach**: window functions used where the pattern calls for them (RANK, NTILE, LAG, running SUM), recursive CTEs for both tree shapes (top-down subtree in Q6, all-pairs subtree in Q7), single-statement MERGE for both change-driven loads, SARGable rewrite + covering indexes for Q10 — each measured, not assumed.
- **Readability**: CTEs over nested subqueries throughout; every file commented with the reasoning behind non-obvious choices.
- **Communication**: this write-up, plus inline comments in each `.sql` file.
