-- ============================================================
-- England & Wales Housing Analysis — Star Schema DDL
-- PostgreSQL 18
-- Safe to re-run: drops tables in reverse FK order first.
-- ============================================================

DROP TABLE IF EXISTS fact_sales        CASCADE;
DROP TABLE IF EXISTS dim_geography     CASCADE;
DROP TABLE IF EXISTS dim_property_type CASCADE;
DROP TABLE IF EXISTS dim_date          CASCADE;


-- ============================================================
-- Dimension: Date
-- ============================================================
CREATE TABLE dim_date (
    date_key    INT      PRIMARY KEY,   -- YYYYMMDD integer surrogate key
    full_date   DATE     NOT NULL,
    year        SMALLINT NOT NULL,
    quarter     SMALLINT NOT NULL,
    month       SMALLINT NOT NULL,
    month_name  TEXT     NOT NULL
);


-- ============================================================
-- Dimension: Property Type
-- Populated inline — only 5 values, never changes.
-- ============================================================
CREATE TABLE dim_property_type (
    type_code   CHAR(1) PRIMARY KEY,   -- D / S / T / F / O
    type_name   TEXT    NOT NULL
);

INSERT INTO dim_property_type VALUES
    ('D', 'Detached'),
    ('S', 'Semi-detached'),
    ('T', 'Terraced'),
    ('F', 'Flat / Maisonette'),
    ('O', 'Other');


-- ============================================================
-- Dimension: Geography
-- Populated from ONSPD — the authoritative source for postcode
-- lookups. PPD town/district/county fields are NOT used: they
-- are free-text, inconsistent across 30 years of submissions,
-- and unreliable for geographic grouping.
-- ============================================================
CREATE TABLE dim_geography (
    geo_key         SERIAL       PRIMARY KEY,
    postcode        TEXT         NOT NULL UNIQUE,
    outcode         TEXT         NOT NULL,   -- e.g. 'SW1A' from 'SW1A 2AA'
    lad_code        TEXT,                    -- Local Authority District code (lad25cd)
    region_code     TEXT,                    -- ONS region code (rgn25cd)
    region_name     TEXT,                    -- Human-readable, derived from region_code
    country         TEXT,                    -- 'England' or 'Wales'
    latitude        NUMERIC(9, 6),
    longitude       NUMERIC(9, 6)
);

CREATE INDEX idx_geo_postcode ON dim_geography(postcode);
CREATE INDEX idx_geo_lad      ON dim_geography(lad_code);
CREATE INDEX idx_geo_region   ON dim_geography(region_code);


-- ============================================================
-- Fact: Sales
-- One row per Category A transaction (standard residential sale).
-- Category B rows (repossessions, portfolio transfers) are excluded
-- at load time and documented in profiling_notes.md.
-- Price is nominal GBP — not inflation-adjusted.
-- ============================================================
CREATE TABLE fact_sales (
    transaction_id  UUID    PRIMARY KEY,
    price           INT     NOT NULL,        -- Nominal £GBP
    date_key        INT     REFERENCES dim_date(date_key),
    type_code       CHAR(1) REFERENCES dim_property_type(type_code),
    tenure          CHAR(1),                 -- F = Freehold, L = Leasehold
    is_new_build    BOOLEAN NOT NULL,
    ppd_category    CHAR(1) NOT NULL,        -- Always 'A' in this dataset
    geo_key         INT     REFERENCES dim_geography(geo_key)
    -- geo_key is NULL for the 0.05% of rows with missing/invalid postcodes;
    -- these are retained in national aggregates but excluded from map queries.
);

CREATE INDEX idx_fact_date ON fact_sales(date_key);
CREATE INDEX idx_fact_geo  ON fact_sales(geo_key);
CREATE INDEX idx_fact_type ON fact_sales(type_code);
-- Partial index to make year-level filters fast without a full scan
CREATE INDEX idx_fact_year ON fact_sales((date_key / 10000));
