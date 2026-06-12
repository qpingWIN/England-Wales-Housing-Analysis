# Profiling Notes — pp-complete.csv

Profiled: 2026-06-05

## Row counts
- Cat A (standard sales): 29,490,159
- Cat B (non-standard): 1,780,116
- **Decision: filter to Cat A only throughout**

## Data quality
- Missing postcodes: 14,203 (0.05%) — exclude from map, retain in national aggregates
- Duplicate transaction IDs: 0
- Suspiciously low prices (<£10k): 24,772 — **filter: WHERE price >= 10000**
- 2026 is partial (5 months) — **filter: WHERE year < 2026 in trend queries**

## Confirmed distributions
- Property type split: T 29.9% / S 28.1% / D 24.0% / F 18.0% — as expected
- New build: 10.5% of Cat A sales
- Year distribution: 2008 and 2020 dips visible and expected

## Filters applied in all downstream queries
WHERE ppd_category = 'A'
  AND price >= 10000