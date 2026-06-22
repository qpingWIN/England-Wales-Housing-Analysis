-- ============================================================
-- Tableau Extract A: Yearly trends by region and property type
-- ============================================================
-- Purpose: feeds three dashboard sheets - the KPI row, the national
-- nominal vs real price trend and price by property type over time.
-- Built as a single GROUPING SETS rollup rather than one flat
-- (year, region, type) table, so every number Tableau displays is
-- already computed at the exact grain it needs. Median and mean price
-- are not additive across rows (median of medians != true median and
-- an unweighted average of per-row means is wrong once group sizes
-- differ), so letting Tableau re-aggregate after dropping a dimension
-- would silently produce the wrong figure. Each grain ships
-- pre-computed instead.

-- Notes:
--   - Four grains, tagged by region_rolled_up/type_rolled_up: (year)
--     for the KPI row and national trend, (year, type) for price by
--     property type, plus (year, region) and (year, region, type) as
--     headroom for later sheets.
--   - LEFT JOIN dim_geography, not INNER JOIN like queries 9/12/13/14:
--     the (year) and (year, type) grains are national rollups and
--     should keep the 0.05% of sales with no matched postcode, same as
--     query 6.
--   - GROUPING() only exists once grouping has happened, so it can't
--     go in a WHERE clause. Missing postcode rows are
--     filtered out of the region-bearing grains in the outer SELECT
--     instead, once GROUPING() is a materialized column.
--   - Excludes the current incomplete year, like queries 10, 14, 16.
--   - real_median reuses query 16's CPIH deflation and base-year
--     logic, applied to every grain since CPIH is one national index
--     regardless of region or type.
-- ============================================================

WITH valid_years AS (
    SELECT DISTINCT d.year
    FROM fact_sales f
    JOIN dim_date d ON d.date_key = f.date_key
    WHERE f.ppd_category = 'A'
      AND d.year < EXTRACT(YEAR FROM CURRENT_DATE)::INT
),
base_year AS (
    SELECT c.cpih_index AS base_cpih
    FROM valid_years v
    JOIN dim_cpih c ON c.year = v.year
    ORDER BY v.year DESC
    LIMIT 1
),
grain_combos AS (
    SELECT
        d.year,
        g.region_name,
        pt.type_name,
        GROUPING(g.region_name) AS region_rolled_up,
        GROUPING(pt.type_name)  AS type_rolled_up,
        COUNT(*) AS transaction_count,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY f.price) AS nominal_median,
        AVG(f.price) AS nominal_mean
    FROM fact_sales f
    JOIN dim_date d ON d.date_key = f.date_key
    LEFT JOIN dim_geography g ON g.geo_key = f.geo_key
    JOIN dim_property_type pt ON pt.type_code = f.type_code
    WHERE f.ppd_category = 'A'
      AND d.year < EXTRACT(YEAR FROM CURRENT_DATE)::INT
    GROUP BY GROUPING SETS (
        (d.year, g.region_name, pt.type_name),
        (d.year, g.region_name),
        (d.year, pt.type_name),
        (d.year)
    )
),
deflated AS (
    SELECT
        gc.*,
        c.cpih_index,
        gc.nominal_median * (b.base_cpih / c.cpih_index) AS real_median
    FROM grain_combos gc
    JOIN dim_cpih c ON c.year = gc.year
    CROSS JOIN base_year b
)
SELECT
    year,
    COALESCE(region_name, 'All regions') AS region_name,
    COALESCE(type_name, 'All types') AS type_name,
    region_rolled_up,
    type_rolled_up,
    transaction_count,
    ROUND(nominal_median) AS nominal_median_price,
    ROUND(nominal_mean) AS nominal_mean_price,
    ROUND(real_median) AS real_median_price,
    cpih_index
FROM deflated
WHERE region_name IS NOT NULL OR region_rolled_up = 1
ORDER BY year, region_rolled_up, type_rolled_up, region_name, type_name;
