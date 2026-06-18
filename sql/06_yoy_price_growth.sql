-- ============================================================
-- Query 6: Year-on-year national median price growth
-- ============================================================
-- Business question: by how much did the typical (median) national price move
-- year over year? LAG() turns the yearly median series
-- into a growth rate.

-- Notes:
--   - National median mixes all property types together so this
--     inherits the mix/composition caveat from the README: a shift
--     in WHAT sold (more flats, fewer detached houses, say) moves
--     this number even if no individual home's value changed. 
--   - 1995's yoy_growth_pct is NULL: there's no 1994 in this dataset
--     to compare against. Expected, not a bug.
--   - is_partial_year flags the current year as before. Comparing a
--     partial year's median to a prior full year's median is still
--     meaningful (median doesn't depend on completeness the
--     way a transaction COUNT does).


--   - Finding: this query's 2007-2009 decline (-2.9%, -0.6%, ~-3.5%
--     cumulative) looks far milder than the headline UK crash figure
--     quoted, Halifax's mix-adjusted average fell ~18.7%
--     peak (Sep 2007, GBP 190,032) to trough (Mar 2009, GBP 154,452)
--     (halifax.co.uk). Three things explain most of the gap:
--          (1) this query averages by CALENDAR YEAR, smoothing out a decline whose
--     peak and trough were specific months, not full years
--          (2) Halifax/Nationwide use a mix-adjusted methodology
--     built specifically to strip out compositional shifts. 
--     This query's median is raw "what actually transacted", and during
--     the credit crunch the mix of what could still transact likely
--     skewed toward smaller/cheaper, easier-to-mortgage sales (the
--     README's mix-effect caveat, observed directly here)
--          (3) MEDIAN is inherently more resistant than a mean/average to a crash
--     concentrated at the expensive end (prime London, new-build/
--     off-plan) which is exactly where 2008 hit hardest.

--     DATA SOURCE: https://www.halifax.co.uk/media-centre/house-price-index.html
-- ============================================================

WITH yearly_median AS (
    SELECT
        d.year,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY f.price) AS median_price
    FROM fact_sales f
    JOIN dim_date d ON d.date_key = f.date_key
    WHERE f.ppd_category = 'A'
    GROUP BY d.year
),
with_lag AS (
    SELECT
        year,
        median_price,
        LAG(median_price) OVER (ORDER BY year) AS prev_median_price
    FROM yearly_median
)
SELECT
    year,
    ROUND(median_price) AS median_price,
    ROUND(
        (100.0 * (median_price - prev_median_price) / prev_median_price)::numeric
    , 1) AS yoy_growth_pct,
    (year = EXTRACT(YEAR FROM CURRENT_DATE)::INT) AS is_partial_year
FROM with_lag
ORDER BY year;
