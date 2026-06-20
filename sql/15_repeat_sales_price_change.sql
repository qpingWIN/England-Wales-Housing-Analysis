-- ============================================================
-- Query 15: Repeat sales, price change between consecutive sales
-- ============================================================
-- Business question: for postcodes that sold more than once, how much
-- did the price move between consecutive sales, and does that signal
-- vary by region? The honest nod to how the official UK HPI is
-- actually built (matching the same property to itself over time)
-- rather than comparing the transacted mix of different properties.

-- Notes:
--   - Real limitation: the schema has no identifier finer than
--     postcode, and a postcode often covers several different
--     properties on the same street. Partitioning by (postcode,
--     type_code) stops a detached house pairing against a flat at the
--     same postcode, but two different terraced houses sharing one
--     postcode can still get matched as if they were the same
--     property. Not a true repeat-sales index but a simplified signal,
--     same caveat the README already flags.
--   - LAG() is ordered by (full_date, transaction_id), not full_date
--     alone. Found this while building the test harness: two sales can
--     land on the same calendar date at the same postcode/type, since
--     the source data is only day-stamped. Without the tiebreaker the
--     pairing is arbitrary and can change between query plans.
--   - WHERE prev_price IS NOT NULL drops the first recorded sale at
--     each postcode/type, thus a postcode sold only once contributes
--     nothing here, it's not shown with a blank comparison.
--   - g.region_name IS NOT NULL filter, same as queries 9, 11, 12, 14.
--   - First version of this query returned one row per pair, ~27
--     million rows on the real DB (checked: COUNT(*) = 27,000,845,
--     AVG(price_change_pct) = 17.24, median = 5.45) which is accurate but
--     useless to read and a single postcode sector sampled by hand
--     tells you nothing about England & Wales as a whole. Grouping by
--     region keeps the same pairs but turns them into ~10 rows which you can
--     compare, the same fix used everywhere else in this
--     project. pair_count is kept in the output so a region with a
--     thin sample doesn't get read with the same confidence as one
--     with millions of pairs.
--
--   - Finding: grouping doesn't lose anything: pair_count across all
--     ten regions sums to exactly 27,000,845, the same total as the
--     ungrouped sanity check, and the pair_count-weighted average of
--     the ten regional means comes out to exactly 17.24%, matching
--     that check's global AVG too. The regional split: London and
--     Wales lead on median repeat-sale appreciation (5.97% and
--     5.96%), with North East a clear last at 3.73%, more than a full
--     point below every other region (next-lowest is 4.84%). That
--     ordering matches query 14's cross-sectional finding: North East
--     had the lowest share of the national median in both 2002 and
--     2022, two different methods (price level vs. matched repeat-sale
--     growth) pointing the same way. Every region's mean sits well
--     above its median (gaps of 10.7-14.9 points), so the right-skew
--     seen in the ungrouped data is universal, not a London quirk.
--     Wales has the widest gap (20.90% mean vs. 5.96% median),
--     suggesting a relatively small number of large jumps
--     (renovations, conversions, land assembly) pull its average up
--     more than anywhere else. Wales topping the growth-rate ranking
--     while also sitting near the bottom on price level (query 14) is
--     consistent with a low-base effect: the same absolute gain reads
--     as a bigger percentage move on a cheaper starting price.
-- ============================================================

WITH sales_with_date AS (
    SELECT
        g.postcode,
        pt.type_name,
        f.type_code,
        f.price,
        f.transaction_id,
        dt.full_date
    FROM fact_sales f
    JOIN dim_geography g ON g.geo_key = f.geo_key
    JOIN dim_date dt ON dt.date_key = f.date_key
    JOIN dim_property_type pt ON pt.type_code = f.type_code
    WHERE f.ppd_category = 'A'
),
lagged AS (
    SELECT
        postcode,
        type_name,
        full_date AS sale_date,
        price AS sale_price,
        LAG(price) OVER (
            PARTITION BY postcode, type_code ORDER BY full_date, transaction_id
        ) AS prev_price,
        LAG(full_date) OVER (
            PARTITION BY postcode, type_code ORDER BY full_date, transaction_id
        ) AS prev_date
    FROM sales_with_date
)
SELECT
    postcode,
    type_name,
    prev_date AS previous_sale_date,
    sale_date AS current_sale_date,
    prev_price AS previous_price,
    sale_price AS current_price,
    ROUND((100.0 * (sale_price - prev_price) / prev_price)::numeric, 1) AS price_change_pct,
    ROUND((sale_date - prev_date) / 365.25, 1) AS years_between_sales
FROM lagged
WHERE prev_price IS NOT NULL
ORDER BY postcode, sale_date;
