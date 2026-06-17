-- ============================================================
-- Query 1 (Foundational): Transaction volume & total market value per year
-- ============================================================
-- Business question: how big is the market each year, and how have
-- both VOLUME (transactions) and VALUE (£ turnover) moved through the
-- cycle -- the 2007/08 crash, the recovery, the COVID dip and rebound?

-- Notes:
--   - is_partial_year flags the current calendar year as TRUE so a
--     reader doesn't mistake a low, still-accumulating final bar for a
--     market crash. See the "Partial-2026" note in 03_load_ppd.py's
--     module docstring, 2026 sales are in fact_sales but the year
--     isn't over yet.
--   - ppd_category = 'A' is always true today (fact_sales only holds
--     Category A rows, see 00_schema_ddl.sql) but is kept explicit
--     here so the query stays correct if Category B rows are ever
--     added for an A-vs-B comparison.
-- ============================================================

SELECT
    d.year,
    COUNT(*) AS transactions,
    SUM(f.price) AS total_value_gbp,
    ROUND(AVG(f.price)) AS avg_price_gbp,
    (d.year = EXTRACT(YEAR FROM CURRENT_DATE)::INT) AS is_partial_year
FROM fact_sales f
JOIN dim_date d ON d.date_key = f.date_key
WHERE f.ppd_category = 'A'
GROUP BY d.year
ORDER BY d.year;
