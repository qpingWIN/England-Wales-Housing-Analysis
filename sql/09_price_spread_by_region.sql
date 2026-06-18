-- ============================================================
-- Query 9: Price spread by region (p10/p25/p50/p75/p90)
-- ============================================================
-- Business question: how wide is the price range within each region,
-- not just where the median sits? Two regions can share a median but
-- have very different spreads

-- Notes:
--   - PERCENTILE_CONT(ARRAY[...]) computes all 5 percentiles in a
--     single pass over each region's price data, instead of 5
--     separate PERCENTILE_CONT(x) calls (5x the sort work). Returned
--     as a double precision[] in the same order as the input array,
--     then unpacked into named columns below for readability.
--   - INNER JOIN to dim_geography (via geo_key) drops the 0.05% of
--     rows with no matched postcode, consistent with the README's
--     "Missing postcodes" limitation. This query is geographic by
--     definition so those rows can't be assigned a region anyway.
--   - g.region_name IS NOT NULL is a defensive filter for the case
--     where a matched postcode is missing a region in the source
--     data itself (separate from the missing-postcode case above).

--   - Confirmed: all 10 expected regions appear (9 English regions +
--     Wales)
--     Sales sum to 29,450,470, 14,917 short of query #2's 29,465,387
--     total, matching the documented 0.05% missing-postcode drop

--   - Finding: the ranking (London > South East > East of England >
--     South West > West Midlands > East Midlands > Wales > North West
--     > Yorkshire and The Humber > North East) and London's far wider
--     spread (627,500 vs North East's 209,550) both match official
--     ONS/Land Registry regional breakdowns, which likewise show
--     London as the most expensive region and the North East as the
--     cheapest (ons.gov.uk).
-- ============================================================

WITH spread AS (
    SELECT
        g.region_name,
        COUNT(*) AS sales,
        PERCENTILE_CONT(ARRAY[0.1, 0.25, 0.5, 0.75, 0.9])
            WITHIN GROUP (ORDER BY f.price) AS pctl
    FROM fact_sales f
    JOIN dim_geography g ON g.geo_key = f.geo_key
    WHERE f.ppd_category = 'A'
      AND g.region_name IS NOT NULL
    GROUP BY g.region_name
)
SELECT
    region_name,
    sales,
    ROUND(pctl[1]) AS p10_price,
    ROUND(pctl[2]) AS p25_price,
    ROUND(pctl[3]) AS p50_price,
    ROUND(pctl[4]) AS p75_price,
    ROUND(pctl[5]) AS p90_price,
    ROUND(pctl[5] - pctl[1]) AS p90_minus_p10_spread
FROM spread
ORDER BY p50_price DESC;
