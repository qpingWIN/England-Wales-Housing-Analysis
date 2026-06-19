-- ============================================================
-- Query 12: Fastest and slowest appreciating districts, 10-year CAGR
-- ============================================================
-- Business question: over the last 10 years, which districts have
-- appreciated the fastest, and which have lagged behind? (ranked)
-- Notes:
--   - CAGR, not total % change: (median_2025 / median_2015)^(1/10) - 1.
--     Annualizing puts every district on the same footing over a fixed
--     10-year horizon instead of comparing raw magnitude.
--   - 2015-2025, not the full ~30-year history. A clean 10-year window
--     keeps things consistent and avoids mixing eras with very
--     different market conditions.
--   - start_sales >= 50 AND end_sales >= 50 is a judgment call, not
--     derived from the data. Small districts can have single-digit
--     annual sale counts, where one unusual sale swings the median and
--     produces a CAGR that looks dramatic but is really just noise.
--   - RANK(), not DENSE_RANK(): CAGR is continuous so an exact tie is
--     unlikely, but RANK() is the more conventional choice for a
--     leaderboard, where ties should leave a gap in the numbering.
--   - Returns every qualifying district, not a fixed top/bottom N. Its possible to
--     filter on appreciation_rank downstream (e.g. <= 10 for a top-10
--     view).
--   - Same lad_code IS NOT NULL filter as queries 9, 11, 13.

--   - Finding: matches reported decade trends at both ends of the
--     table. Salford (#1, 6.3% CAGR), Oldham (#4, 6.0%) and
--     Manchester (#6, 5.7%) anchoring the top lines up with multiple
--     2026 reports naming this exact trio as England's
--     fastest-appreciating local authorities over the same decade (BuyAssociation,
-- Mortgage Solutions).
--     At the other end, City of London, Kensington and Chelsea,
--     Westminster and Hammersmith and Fulham are the only four
--     districts with a negative cagr_pct: an actual nominal price
--     fall over ten years. 
-- ============================================================

WITH district_year AS (
    SELECT
        g.lad_code,
        g.lad_name,
        d.year,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY f.price) AS median_price,
        COUNT(*) AS sales
    FROM fact_sales f
    JOIN dim_geography g ON g.geo_key = f.geo_key
    JOIN dim_date d ON d.date_key = f.date_key
    WHERE f.ppd_category = 'A'
      AND g.lad_code IS NOT NULL
      AND d.year IN (2015, 2025)
    GROUP BY g.lad_code, g.lad_name, d.year
),
start_yr AS (
    SELECT lad_code, lad_name, median_price AS start_median, sales AS start_sales
    FROM district_year WHERE year = 2015
),
end_yr AS (
    SELECT lad_code, median_price AS end_median, sales AS end_sales
    FROM district_year WHERE year = 2025
),
cagr AS (
    SELECT
        s.lad_code,
        s.lad_name,
        s.start_median,
        e.end_median,
        s.start_sales,
        e.end_sales,
        (POWER((e.end_median / s.start_median)::numeric, 1.0/10) - 1) AS cagr_ratio
    FROM start_yr s
    JOIN end_yr e ON e.lad_code = s.lad_code
    WHERE s.start_sales >= 50 AND e.end_sales >= 50
)
SELECT
    lad_code,
    lad_name,
    ROUND(start_median) AS median_2015,
    ROUND(end_median) AS median_2025,
    start_sales,
    end_sales,
    ROUND(100.0 * cagr_ratio, 1) AS cagr_pct,
    RANK() OVER (ORDER BY cagr_ratio DESC) AS appreciation_rank
FROM cagr
ORDER BY appreciation_rank;
