-- ============================================================
-- Query 10: Volume shock recovery, indexed to 2007
-- ============================================================
-- Business question: how did transaction volume move through the two
-- big shocks in this dataset, particularly, the 2008 financial crisis and the
-- 2020 COVID-19 pandemic, relative to the market's pre-crisis size?

-- Notes:
--   - Base year = 2007, the last full year before the 2008 crash - a
--     natural pre-shock reference point, rather than 1995 (the start
--     of the dataset, but not a meaningful market peak/trough) or an
--     arbitrary recent year.
--   - volume_index_2007_base = 100 * that year's transactions / 2007's
--     transactions. 100 = same volume as 2007, below/above 100 =
--     fewer/more transactions than 2007.
--   - Watch for: a transaction-volume index isn't the same signal as
--     a price index. It can show a brief spike or dip around a
--     policy change (e.g. a stamp duty deadline pulling completions
--     forward or back) that has nothing to do with 2008 or COVID.
--     Worth checking any sharp single-year move against the
--     historical calendar before attributing it to either shock.
--   - is_partial_year flagged as elsewhere, the 2026 index point
--     isn't comparable to a full year's figure.

--   - Finding: both shocks and the recovery between them match
--     documented history. 2008 (51.0) and 2009 (49.1) roughly halve
--     2007's volume, consistent with gov.uk's own framing of the
--     financial crisis as the point transactions fell off a steady
--     climb that had peaked in mid-2006. 2021 (85.4) is this series'
--     highest point since 2007, matching gov.uk's description of
--     2021-22 UK transactions as the highest since 2007-08, driven by
--     stamp-duty-holiday peaks in March/June/September 2021, which is a
--     direct confirmation of the caveats induced by various policies in place.
--     2020's COVID dip (59.2) is comparatively mild
--     next to 2008's, consistent with the holiday cushioning H2 2020
--     after Q2's lockdown-driven collapse (gov.uk).
-- ============================================================

WITH yearly_volume AS (
    SELECT
        d.year,
        COUNT(*) AS transactions
    FROM fact_sales f
    JOIN dim_date d ON d.date_key = f.date_key
    WHERE f.ppd_category = 'A'
    GROUP BY d.year
),
base AS (
    SELECT transactions AS base_transactions
    FROM yearly_volume
    WHERE year = 2007
)
SELECT
    yv.year,
    yv.transactions,
    ROUND(100.0 * yv.transactions / b.base_transactions, 1) AS volume_index_2007_base,
    (yv.year = EXTRACT(YEAR FROM CURRENT_DATE)::INT) AS is_partial_year
FROM yearly_volume yv
CROSS JOIN base b
ORDER BY yv.year;
