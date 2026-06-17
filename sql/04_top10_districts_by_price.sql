-- ============================================================
-- Query 4 (Foundational): Top 10 districts by median price, latest full year
-- ============================================================
-- Business question: which local authority districts are most
-- expensive right now, using the most recently *complete* year so a
-- partial current year can't distort the ranking?
--
-- Notes:
--   - latest_full_year is computed dynamically (MAX year strictly
--     before the current calendar year) rather than hardcoded, so
--     this query stays correct every time it's re-run in a later year.
--   - HAVING COUNT(*) >= 30 drops tiny-sample districts. Without a
--     floor, a district with 2-3 sales of unusually expensive homes
--     could fake its way into the "top 10" on noise, not a genuine
--     market price level.
--   - lad_name comes from a separate ONS lookup (LAD25CD/LAD25NM),
--     backfilled onto dim_geography by scripts/04_backfill_lad_names.py
--     -- the ONSPD postcode extract only carries the LAD *code*, not a
--     name. lad_code is kept alongside lad_name for traceability.
-- ============================================================

WITH latest_full_year AS (
    SELECT MAX(year) AS yr
    FROM dim_date
    WHERE year < EXTRACT(YEAR FROM CURRENT_DATE)::INT
)
SELECT
    g.lad_name,
    g.lad_code,
    g.region_name,
    COUNT(*) AS sales,
    PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY f.price) AS median_price
FROM fact_sales f
JOIN dim_date d       ON d.date_key = f.date_key
JOIN dim_geography g  ON g.geo_key  = f.geo_key
CROSS JOIN latest_full_year lfy
WHERE f.ppd_category = 'A'
  AND d.year = lfy.yr
  AND g.lad_code IS NOT NULL
GROUP BY g.lad_name, g.lad_code, g.region_name
HAVING COUNT(*) >= 30
ORDER BY median_price DESC
LIMIT 10;
