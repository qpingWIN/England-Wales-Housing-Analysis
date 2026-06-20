-- ============================================================
-- Query 14: Regional divergence from the national median
-- ============================================================
-- Business question: each region's median price as a percentage of
-- the national median, year by year. Is the gap between the most
-- and least expensive regions widening or narrowing over time?

-- Notes:
--   - regional and national are two separate CTEs. National is the median of every
--     transaction pooled together (averaging the regional medians
--     instead would weight a tiny region the same as a huge one).
--   - pct_of_national uses the raw, unrounded medians from the CTEs,
--     not the rounded columns in the final SELECT. Rounding is a
--     display step.    
--   - Excludes the current, still-incomplete year
--     (d.year < EXTRACT(YEAR FROM CURRENT_DATE)::INT), same partial-
--     year convention as query 10.

--   - Finding: London's share of the national median climbs from
--     132.7% (1995) to a clear peak of 203.5% in 2017, then pulls back
--     to 179.0% by 2025. That matches 2026 reporting that the gap
--     between London and regional cities is now at its narrowest since
--     2009. The average London home priced at 2.38x the average
--     Greater Manchester home, down from a much wider multiple at
--     London's 2016/17 peak (Construction Magazine, June 2026). North
--     East and Wales sit at the other end, and both bottom out close to
--     London's peak years: North East's lowest share, 55.9%, occurs in
--     2002 and again in 2022, recovering only to 58.5% by 2025; Wales
--     troughs at 64.5% (2002) and 66.5% (2017) before ending at 72.9%.
--     East of England is the one large region moving the other way,
--     rising from 104.5% to around 120%, consistent with London's
--     commuter belt absorbing some of the capital's spillover demand.
--     The overall pattern, three decades of widening between the
--     richest and poorest region that only narrows in the final few
--     years.
-- ============================================================

WITH regional AS (
    SELECT
        g.region_name,
        d.year,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY f.price) AS regional_median
    FROM fact_sales f
    JOIN dim_geography g ON g.geo_key = f.geo_key
    JOIN dim_date d ON d.date_key = f.date_key
    WHERE f.ppd_category = 'A'
      AND g.region_name IS NOT NULL
      AND d.year < EXTRACT(YEAR FROM CURRENT_DATE)::INT
    GROUP BY g.region_name, d.year
),
national AS (
    SELECT
        d.year,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY f.price) AS national_median
    FROM fact_sales f
    JOIN dim_date d ON d.date_key = f.date_key
    WHERE f.ppd_category = 'A'
      AND d.year < EXTRACT(YEAR FROM CURRENT_DATE)::INT
    GROUP BY d.year
)
SELECT
    r.region_name,
    r.year,
    ROUND(r.regional_median) AS regional_median,
    ROUND(n.national_median) AS national_median,
    ROUND((100.0 * r.regional_median / n.national_median)::numeric, 1) AS pct_of_national
FROM regional r
JOIN national n ON n.year = r.year
ORDER BY r.region_name, r.year;
