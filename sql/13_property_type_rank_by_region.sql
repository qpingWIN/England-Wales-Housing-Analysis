-- ============================================================
-- Query 13: Property type price rank within each region
-- ============================================================
-- Business question: within each region, which property type commands
-- the highest price, and how does the full ranking of detached / semi
-- / terraced / flat / other compare from region to region?

-- Notes:
--   - Pools all years together. This is a cross-sectional snapshot of
--     price ordering by type within each region, not a trend over
--     time 
--   - DENSE_RANK(), not RANK(): with only 5 property types per region,
--     two landing on the same rounded median is plausible, and a
--     "missing" rank number there would look like a bug rather than a
--     real tie. 
--   - Same region_name IS NOT NULL filter as queries 9, 11, 12.
--   - type_name comes from dim_property_type rather than the raw
--     D/S/T/F/O code, just for readability.
--
--   - Finding: Detached ranks #1 in every single region, no
--     exceptions, the one ordering invariant.
--     "Other" never shows up in any region's
--     results, but that traces back to Phase 0 profiling
--     (notebooks/profiling_notes.md), where the Category-A
--     property-type split already summed to 100.0% across just D/S/T/F
--     (T 29.9% / S 28.1% / D 24.0% / F 18.0%), leaving nothing for
--     "Other". So this isn't a query bug, "Other"-type Category-A
--     sales are effectively absent from the source data, consistent
--     with HM Land Registry guidance that non-standard sales are
--     typically captured under Category B, which this project
--     excludes by design (see README). 
--     At rank 3/4 it's always Terraced vs Flat/Maisonette,
--     but which one comes out cheaper flips by region. Terraced is
--     the cheaper type in East Midlands, North East, North West,
--     Wales and Yorkshire and The Humber, whereas Flat/Maisonette is the
--     cheaper type in East of England, London, South East, South
--     West and West Midlands. 

-- ============================================================

WITH region_type AS (
    SELECT
        g.region_name,
        pt.type_name,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY f.price) AS median_price,
        COUNT(*) AS sales
    FROM fact_sales f
    JOIN dim_geography g ON g.geo_key = f.geo_key
    JOIN dim_property_type pt ON pt.type_code = f.type_code
    WHERE f.ppd_category = 'A'
      AND g.region_name IS NOT NULL
    GROUP BY g.region_name, pt.type_name
)
SELECT
    region_name,
    type_name,
    sales,
    ROUND(median_price) AS median_price,
    DENSE_RANK() OVER (PARTITION BY region_name ORDER BY median_price DESC) AS price_rank_within_region
FROM region_type
ORDER BY region_name, price_rank_within_region;
