-- ============================================================
-- Query 16: Real vs. nominal price growth (CPIH-deflated)
-- ============================================================
-- Business question: how much of query 6's house-price "growth" is
-- just inflation? Deflates the nominal annual median by the ONS CPIH
-- index and shows nominal vs. real year-on-year growth side by side.

-- Notes:
--   - real_median = nominal_median * (base_year_cpih / that_year_cpih).
--     base_year is the latest complete year, so every real figure
--     lands in that year's own pounds. 
--   - base_year is the latest year present in both national_yearly and
--     dim_cpih, not just MAX(year) from the sales data. ONS publishes
--     CPIH with a lag, so if the newest sales year had no CPIH figure
--     yet, anchoring on MAX(year) would join to nothing and quietly
--     empty the whole query.
--   - YoY growth uses LAG() OVER (ORDER BY year), same as query 6. It
--     compares to the previous row in the result, not literally
--     year-1, so a gap year would measure growth against whatever year
--     came before it.
--   - Excludes the current, still-incomplete year, like queries 10
--     and 14.
--
--   - Finding: nominal growth since 1995 looks huge, +436%. Deflating
--     by CPIH cuts that to +159% in 2025, so a big chunk of
--     that headline number is just three decades of inflation, not
--     real gains. 2008 and 2011 hit harder in real terms than nominal
--     (-6.1% and -6.9% vs -2.9% and -3.3%), and 2022-2025 stands out
--     most: real prices fell every single year (-2.7%, -7.4%, -2.1%,
--     -2.0%) while nominal prices stayed flat or rose. An independent
--     Nationwide/RPI series shows the same shape, real prices down
--     roughly 7-8% a year through 2022-2023 before flattening out in
--     2024-2025 (propertyinvestmentproject.co.uk).
-- ============================================================

WITH national_yearly AS (
    SELECT
        d.year,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY f.price) AS nominal_median
    FROM fact_sales f
    JOIN dim_date d ON d.date_key = f.date_key
    WHERE f.ppd_category = 'A'
      AND d.year < EXTRACT(YEAR FROM CURRENT_DATE)::INT
    GROUP BY d.year
),
base_year AS (
    SELECT c.cpih_index AS base_cpih
    FROM national_yearly n
    JOIN dim_cpih c ON c.year = n.year
    ORDER BY n.year DESC
    LIMIT 1
),
deflated AS (
    SELECT
        n.year,
        c.cpih_index,
        n.nominal_median,
        n.nominal_median * (b.base_cpih / c.cpih_index) AS real_median
    FROM national_yearly n
    JOIN dim_cpih c ON c.year = n.year
    CROSS JOIN base_year b
),
with_lag AS (
    SELECT
        year,
        cpih_index,
        nominal_median,
        real_median,
        LAG(nominal_median) OVER (ORDER BY year) AS prev_nominal_median,
        LAG(real_median) OVER (ORDER BY year) AS prev_real_median
    FROM deflated
)
SELECT
    year,
    cpih_index,
    ROUND(nominal_median) AS nominal_median_price,
    ROUND(real_median) AS real_median_price,
    ROUND((100.0 * (nominal_median - prev_nominal_median) / prev_nominal_median)::numeric, 1) AS nominal_yoy_growth_pct,
    ROUND((100.0 * (real_median - prev_real_median) / prev_real_median)::numeric, 1) AS real_yoy_growth_pct
FROM with_lag
ORDER BY year;
