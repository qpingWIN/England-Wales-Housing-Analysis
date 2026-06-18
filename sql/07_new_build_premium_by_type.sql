-- ============================================================
-- Query 7: New-build premium over established homes by property type
-- ============================================================
-- Business question: do new-build homes sell for more than
-- established (resale) homes of the same type and by how much?

-- Notes:
--   - Two CTEs (one per is_new_build value), joined on property type,
--     rather than one pass with a CASE inside the aggregate -- makes
--     the "two populations, one ratio" structure explicit.
--   - INNER JOIN between the two CTEs: a property type with zero
--     sales in either bucket would not appear in the result.
--   - Pools all years 1995-2026 (no year filter), so the registration
--     lag caveat from query #3/README applies here too: new-build
--     sales from ~2024 onward are still arriving, but they're a small
--     fraction of a 31-year pool so they shouldn't meaningfully move
--     this result
--   - Confirmed: only 4 of 5 dim_property_type rows appear above.
--     "Other" (O) has zero sales in at least one of the two buckets,
--     exactly the case already called out in the INNER JOIN note.

--   - Finding: detached is the one type where new-build undercuts
--     established (-9.1%). Terraced/flat/semi all show a clear
--     premium instead (+35.0%/+24.3%/+18.2%). This direction is
--     corroborated by general UK market commentary rather than one
--     definitive benchmark: new-build detached homes are increasingly
--     built on smaller plots than the older detached stock they're
--     priced against (new-builds.co.uk), while a 15-25% premium on a
--     per-sq-ft basis is described as "normal" and >30% as warranting
--     scrutiny, with flats carrying the smallest premium of any type,
--     particularly, as low as 3.5% in London (hunterfinance.co.uk). There's no
--     single authoritative by-type figure to check this against
--     directly but it's consistent with the known market dynamics.
-- ============================================================

WITH new_build AS (
    SELECT
        pt.type_name,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY f.price) AS new_build_median
    FROM fact_sales f
    JOIN dim_property_type pt ON pt.type_code = f.type_code
    WHERE f.ppd_category = 'A'
      AND f.is_new_build
    GROUP BY pt.type_name
),
established AS (
    SELECT
        pt.type_name,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY f.price) AS established_median
    FROM fact_sales f
    JOIN dim_property_type pt ON pt.type_code = f.type_code
    WHERE f.ppd_category = 'A'
      AND NOT f.is_new_build
    GROUP BY pt.type_name
)
SELECT
    n.type_name,
    ROUND(n.new_build_median) AS new_build_median,
    ROUND(e.established_median) AS established_median,
    ROUND(
        (100.0 * (n.new_build_median - e.established_median) / e.established_median)::numeric
    , 1) AS new_build_premium_pct
FROM new_build n
JOIN established e ON e.type_name = n.type_name
ORDER BY new_build_premium_pct DESC;
