-- ============================================================
-- Query 17: Sample extract for the hedonic-lite regression (Phase 6)
--
-- Purpose: pull a ~1M-row random sample of sales with the
-- attributes PPD actually carries (type, tenure, new-build,
-- region, year) for a log-price OLS. The year coefficients
-- become a constant-quality price index. Comparing it to the
-- raw median index quantifies the mix effect documented in the README.
--
-- Filters mirror the project's standard analysis filters:
--   - years 1995-2025 (exclude partial 2026)
--   - property type 'O' (Other) excluded
--   - tenure restricted to F/L (a handful of rows carry other codes, e.g. 'U' for unknown)
--   - geo_key required: region is a regressor, so the 0.05%
--     without a postcode cannot be used here
--
-- Sampling: uniform via random(), seeded for reproducibility.
-- ~4% of ~28M eligible rows -> ~1.1M sample. Uniform sampling
-- preserves each year's share of transactions, so no year is
-- over/under-represented relative to the market.
--
--
-- Run (from repo root):
--   psql -U postgres -d ew_housing -f sql/17_hedonic_sample_extract.sql
-- Writes: data/processed/hedonic_sample.csv (gitignored)
-- ============================================================

SELECT setseed(0.42);

\o data/processed/hedonic_sample.csv

COPY (
    SELECT
        f.price,
        d.year,
        p.type_name,
        f.tenure,
        f.is_new_build::int AS is_new_build,
        g.region_name
    FROM fact_sales f
    JOIN dim_date          d ON d.date_key  = f.date_key
    JOIN dim_property_type p ON p.type_code = f.type_code
    JOIN dim_geography     g ON g.geo_key   = f.geo_key
    WHERE d.year BETWEEN 1995 AND 2025
      AND f.type_code <> 'O'
      AND f.tenure IN ('F', 'L')
      AND random() < 0.04
) TO STDOUT WITH (FORMAT csv, HEADER true);

\o
