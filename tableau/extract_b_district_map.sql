-- ============================================================
-- Tableau Extract B: District-level snapshot for the map sheet
-- ============================================================
-- Purpose: feeds the district map sheet. Reuses query 12's exact CAGR
-- logic (same 2015-2025 window, same start_sales/end_sales >= 50
-- threshold, same lad_code filter) and adds the two things the map
-- needs that query 12 doesn't produce: a plottable centroid
-- (latitude/longitude) per district, and an all-time transaction count
-- as a separate market-size signal.

-- Notes:
--   - This puts a circle at each district's centre point instead of
--     drawing its actual outline. Tableau's built-in district shapes
--     don't reliably match our district names without a custom map
--     file so a circle avoids that problem entirely.
--   - centroid_lat/long is the average latitude/longitude of every
--     postcode in the district, not just the postcodes that had a
--     sale. Thus, it's the true middle of the district, not a point
--     pulled toward wherever sales happened to cluster.
--   - transaction_count is every sale ever recorded for the district
--     (minus the current, still-incomplete year, same as queries 10,
--     14 and 16). It measures how big the market is, not how fast
--     it's growing, that's a separate number (cagr_pct).
--   - Uses the same >= 50 sales filter as query 12, so it's the same
--     list of districts, with the same small, unreliable ones left
--     out on purpose.
-- ============================================================

WITH district_year AS (
    SELECT
        g.lad_code,
        g.lad_name,
        g.region_name,
        d.year,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY f.price) AS median_price,
        COUNT(*) AS sales
    FROM fact_sales f
    JOIN dim_geography g ON g.geo_key = f.geo_key
    JOIN dim_date d ON d.date_key = f.date_key
    WHERE f.ppd_category = 'A'
      AND g.lad_code IS NOT NULL
      AND d.year IN (2015, 2025)
    GROUP BY g.lad_code, g.lad_name, g.region_name, d.year
),
start_yr AS (
    SELECT lad_code, lad_name, region_name, median_price AS start_median, sales AS start_sales
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
        s.region_name,
        s.start_median,
        e.end_median,
        s.start_sales,
        e.end_sales,
        (POWER((e.end_median / s.start_median)::numeric, 1.0/10) - 1) AS cagr_ratio
    FROM start_yr s
    JOIN end_yr e ON e.lad_code = s.lad_code
    WHERE s.start_sales >= 50 AND e.end_sales >= 50
),
district_totals AS (
    SELECT g.lad_code, COUNT(*) AS transaction_count
    FROM fact_sales f
    JOIN dim_geography g ON g.geo_key = f.geo_key
    JOIN dim_date d ON d.date_key = f.date_key
    WHERE f.ppd_category = 'A'
      AND g.lad_code IS NOT NULL
      AND d.year < EXTRACT(YEAR FROM CURRENT_DATE)::INT
    GROUP BY g.lad_code
),
district_centroid AS (
    SELECT lad_code, AVG(latitude) AS centroid_lat, AVG(longitude) AS centroid_long
    FROM dim_geography
    WHERE lad_code IS NOT NULL
    GROUP BY lad_code
)
SELECT
    c.lad_code,
    c.lad_name,
    c.region_name,
    dc.centroid_lat,
    dc.centroid_long,
    ROUND(c.start_median) AS median_2015,
    ROUND(c.end_median) AS latest_median_price,
    c.start_sales,
    c.end_sales,
    ROUND(100.0 * c.cagr_ratio, 1) AS cagr_pct,
    RANK() OVER (ORDER BY c.cagr_ratio DESC) AS appreciation_rank,
    t.transaction_count
FROM cagr c
JOIN district_totals t ON t.lad_code = c.lad_code
JOIN district_centroid dc ON dc.lad_code = c.lad_code
ORDER BY appreciation_rank;
