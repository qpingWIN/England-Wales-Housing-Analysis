-- ============================================================
-- Query 2 (Foundational): Median & mean price by property type
-- ============================================================
-- Business question: what does a typical property of each type cost,
-- and why do the mean and median disagree?

-- Why mean != median: price is right-skewed within every property type. 
-- A small number of very expensive sales pull the mean up,
-- while the median (the 50th percentile) is robust to that. The
-- mean_over_median_pct column quantifies the skew directly: the
-- larger it is, the more that type's mean is being inflated by a thin
-- top tail of expensive sales rather than reflecting "typical".
--
-- Result: Flats/Maisonettes show the widest relative gap (+42.4%), not
-- Detached (+26.1%) as might be assumed. Detached homes have a long
-- expensive tail too (country mansions), but their median is already
-- high, which compresses the *relative* skew. Flats span a much wider
-- relative range, ex-council studios up to prime central London
-- penthouses so a thin top tail moves the mean proportionally
-- further from the median. Terraced is a close second (+38.3%) for
-- the same reason (prime-area townhouses).
-- ============================================================

SELECT
    pt.type_name,
    COUNT(*) AS sales,
    ROUND(AVG(f.price)) AS mean_price,
    PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY f.price) AS median_price,
    ROUND(
        (100.0 * (AVG(f.price) - PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY f.price))
        / PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY f.price))::numeric
    , 1) AS mean_over_median_pct
FROM fact_sales f
JOIN dim_property_type pt ON pt.type_code = f.type_code
WHERE f.ppd_category = 'A'
GROUP BY pt.type_name
ORDER BY median_price DESC;
