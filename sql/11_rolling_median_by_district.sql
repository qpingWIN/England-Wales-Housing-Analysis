-- ============================================================
-- Query 11: Rolling 12-month median price per district
-- ============================================================
-- Business question: smoothing past month-to-month noise (and the
-- seasonality already surfaced in query 8), what's the underlying
-- price trend in each district, and where does that trend have gaps
-- because a district went quiet for some time?

-- Notes:
--   - Postgres won't allow PERCENTILE_CONT inside an OVER() window, and
--     array_agg() can't pool arrays of different lengths across rows.
--     So months_in_window/rolling_sales use real window functions,
--     while the median comes from a self-join (each month joins its
--     own trailing 11 months by lad_code, unnests, then percentiles).
--     A correlated subquery here is fine on small data but doesn't
--     scale: it re-scans the table per output row instead of hashing
--     on lad_code once.
--   - RANGE BETWEEN 11 PRECEDING AND CURRENT ROW, not ROWS, so a month
--     with zero sales correctly breaks the run instead of being
--     skipped over. months_in_window = 12 then enforces a true
--     gap-free run, thus a district that goes quiet drops out until it
--     rebuilds 12 straight months.
--   - Same lad_code IS NOT NULL filter as queries 9, 12, 13.
-- ============================================================

WITH district_month AS (
    SELECT
        g.lad_code,
        g.lad_name,
        d.year,
        d.month,
        (d.year * 12 + d.month) AS month_index,
        array_agg(f.price) AS prices,
        COUNT(*) AS sales
    FROM fact_sales f
    JOIN dim_geography g ON g.geo_key = f.geo_key
    JOIN dim_date d ON d.date_key = f.date_key
    WHERE f.ppd_category = 'A'
      AND g.lad_code IS NOT NULL
    GROUP BY g.lad_code, g.lad_name, d.year, d.month
),
windowed AS (
    SELECT
        lad_code, lad_name, year, month, month_index, sales,
        COUNT(*) OVER w AS months_in_window,
        SUM(sales) OVER w AS rolling_sales
    FROM district_month
    WINDOW w AS (
        PARTITION BY lad_code ORDER BY month_index
        RANGE BETWEEN 11 PRECEDING AND CURRENT ROW
    )
),
medians AS (
    SELECT
        cur.lad_code,
        cur.month_index,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY p.price) AS rolling_12mo_median
    FROM district_month cur
    JOIN district_month hist
        ON hist.lad_code = cur.lad_code
       AND hist.month_index BETWEEN cur.month_index - 11 AND cur.month_index
    CROSS JOIN LATERAL unnest(hist.prices) AS p(price)
    GROUP BY cur.lad_code, cur.month_index
)
SELECT
    w.lad_code,
    w.lad_name,
    w.year,
    w.month,
    w.rolling_sales,
    ROUND(m.rolling_12mo_median) AS rolling_12mo_median
FROM windowed w
JOIN medians m ON m.lad_code = w.lad_code AND m.month_index = w.month_index
WHERE w.months_in_window = 12
ORDER BY w.lad_code, w.year, w.month;
