-- ============================================================
-- Query 8: Seasonality: volume and price by month
-- ============================================================
-- Business question: which calendar months see the most home-buying
-- activity and do prices run higher or lower in particular months?

-- Framed two ways: average transaction volume per month and each
-- month's price relative to its own year's annual median (so 31
-- years of nominal price growth don't contaminate the comparison).

-- Notes:
--   - Excludes the current partial year entirely (d.year < EXTRACT
--     (YEAR FROM CURRENT_DATE)): without this, Jan-Jun would average
--     in one more year of data than Jul-Dec, mechanically inflating
--     H1 volume averages and deflating H1 price averages.
--   - avg_pct_of_annual_median_price: for each (year, month), divides
--     that month's median price by that SAME year's annual median,
--     then averages the ratio across years. Deliberately NOT "average
--     monthly price across years" (which would just re-derive the
--     31-year nominal price trend). This is a within-year relative
--     measure so it isolates seasonality from three decades of price
--     growth. 100% = that month is exactly typical for its year,
--     above/below 100% = that month runs hot/cold relative to its own
--     year.
--   - avg_transactions_per_year is the average of monthly transaction
--     counts across the 31 complete years (1995-2025), not a total,
--     so it's directly comparable across months.

--   - Finding: volume is lowest Jan/Feb (~60-63k) and highest Jun-Aug
--     (~87-89k), matching gov.uk's own commentary that transactions
--     are seasonal with more activity in summer, less in winter.
--     March is the outlier. A sharp spike (80k) immediately followed
--     by an April dip (70k) which lines up with recurring stamp
--     duty deadlines pulling completions forward into March and out of April (mpamag.com,
--     theintermediary.co.uk). 
--     Price tells a complementary story: all
--     of Jan-May sit below 100% and all of Jun-Dec sit above it, which
--     fits gov.uk's note that completions trail offers by 2-4 months, thus
--     a Jun-Dec completion often reflects a price agreed back in
--     the busier, higher-asking spring market.
-- ============================================================

WITH annual AS (
    SELECT
        d.year,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY f.price) AS annual_median_price
    FROM fact_sales f
    JOIN dim_date d ON d.date_key = f.date_key
    WHERE f.ppd_category = 'A'
      AND d.year < EXTRACT(YEAR FROM CURRENT_DATE)::INT
    GROUP BY d.year
),
monthly AS (
    SELECT
        d.year,
        d.month,
        d.month_name,
        COUNT(*) AS monthly_transactions,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY f.price) AS monthly_median_price
    FROM fact_sales f
    JOIN dim_date d ON d.date_key = f.date_key
    WHERE f.ppd_category = 'A'
      AND d.year < EXTRACT(YEAR FROM CURRENT_DATE)::INT
    GROUP BY d.year, d.month, d.month_name
)
SELECT
    m.month,
    m.month_name,
    ROUND(AVG(m.monthly_transactions)) AS avg_transactions_per_year,
    ROUND(
        (100.0 * AVG(m.monthly_median_price / a.annual_median_price))::numeric
    , 1) AS avg_pct_of_annual_median_price
FROM monthly m
JOIN annual a ON a.year = m.year
GROUP BY m.month, m.month_name
ORDER BY m.month;
