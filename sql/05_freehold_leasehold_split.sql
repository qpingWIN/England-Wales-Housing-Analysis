-- ============================================================
-- Query 5 (Foundational): Freehold vs leasehold split, by property type
-- ============================================================
-- Business question: how does tenure (freehold vs leasehold) vary by
-- property type? Expected pattern: flats are predominantly leasehold
-- (shared structure/building means a lease + service charge is the
-- norm), houses predominantly freehold - this query is as much a
-- data sanity check as it is a finding. A wildly different split
-- would be a signal to go back and re-check the tenure column.
--
-- Notes:
--   - tenure = 'U' ("unknown") is a genuine third value in PPD's
--     Duration field, confirmed two ways: directly against this DB
--     (SELECT tenure, COUNT(*) ... GROUP BY tenure -> F=22,638,058,
--     L=6,826,797, U=532) and against an independent PPD schema
--     reference (ClickHouse's published docs for this dataset
--     enumerate duration as F/L/U -> freehold/leasehold/unknown).
--   - Those 532 rows (0.0018% of all Category A sales) are filtered
--     out entirely via WHERE f.tenure IN ('F', 'L'), not just left
--     out of the freehold/leasehold counts. So total_sales here means
--     "sales with known tenure of that type", not "all Category A
--     sales of that type": summed across all 4 property types it
--     comes to 29,464,855, exactly 532 less than 29,465,387.
...
-- ============================================================

SELECT
    pt.type_name,
    SUM(CASE WHEN f.tenure = 'F' THEN 1 ELSE 0 END) AS freehold,
    SUM(CASE WHEN f.tenure = 'L' THEN 1 ELSE 0 END) AS leasehold,
    COUNT(*) AS total_sales,
    ROUND(
        100.0 * SUM(CASE WHEN f.tenure = 'F' THEN 1 ELSE 0 END) / COUNT(*)
    , 1) AS freehold_pct
FROM fact_sales f
JOIN dim_property_type pt ON pt.type_code = f.type_code
WHERE f.ppd_category = 'A'
  AND f.tenure IN ('F', 'L')
GROUP BY pt.type_name
ORDER BY freehold_pct DESC;
