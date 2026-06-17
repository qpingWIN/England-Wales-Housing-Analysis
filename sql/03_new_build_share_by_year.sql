-- ============================================================
-- Query 3 (Foundational): New-build vs established share of sales per year
-- ============================================================
-- Business question: what fraction of each year's sales are new
-- builds vs established (resale) homes and is that share growing or
-- shrinking over time? (New-build share is a standard proxy for
-- housebuilding supply reaching the market)

-- Notes:
--   - is_partial_year carried through as in 01_volume_by_year.sql
--     new-build share can shift mechanically in a partial year if
--     new-build completions cluster in particular months.
--   - KNOWN LIMITATION -- registration lag, not just a partial year:
--     new_build_pct collapses to ~4% in 2025 and ~0% in 2026, far too
--     sharp to be a real housebuilding slowdown. HMLR's standard PPD
--     lag is 2 weeks-2 months for an ordinary sale (see
--     gov.uk/guidance/about-the-price-paid-data), but a new-build sale
--     requires a *first registration* of a brand-new title, which
--     HMLR's currently published processing times put at up to 12
--     months, vs near-instant for a dealing on an already-registered
--     title (what every resale uses). So a 2025 new-build sale can
--     legitimately still be missing from this data pull while a 2025
--     resale almost certainly isn't. is_partial_year doesn't catch
--     this: 2025 is a complete calendar year but its new-build figure
--     is still under-recorded. I will treat new_build_pct as increasingly
--     provisional from ~2024 onward and say so wherever it's charted.
-- ============================================================

SELECT
    d.year,
    SUM(CASE WHEN f.is_new_build THEN 1 ELSE 0 END) AS new_build_sales,
    SUM(CASE WHEN NOT f.is_new_build THEN 1 ELSE 0 END) AS established_sales,
    COUNT(*) AS total_sales,
    ROUND(
        100.0 * SUM(CASE WHEN f.is_new_build THEN 1 ELSE 0 END) / COUNT(*)
    , 1) AS new_build_pct,
    (d.year = EXTRACT(YEAR FROM CURRENT_DATE)::INT) AS is_partial_year
FROM fact_sales f
JOIN dim_date d ON d.date_key = f.date_key
WHERE f.ppd_category = 'A'
GROUP BY d.year
ORDER BY d.year;
