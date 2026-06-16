"""
Run 02_load_onspd.py first to populate dim_geography, then run this script to load the Price Paid Data (PPD) into fact_sales

03_load_ppd.py
--------------
Loads HM Land Registry Price Paid Data into the star schema.

Strategy — ELT (Extract -> Load -> Transform):
  Step 1: COPY raw CSV into staging_ppd (all text, no transforms yet).
          This is the fastest possible ingest — Postgres handles the I/O.
  Step 2: INSERT distinct sale dates into dim_date.
  Step 3: INSERT filtered sales into fact_sales, joining staging_ppd
          to dim_geography on postcode.

Performance note: fact_sales' 4 indexes are DROPPED before the Step 3
insert and REBUILT in bulk afterward. Maintaining 4 B-tree indexes
incrementally across a ~29.5M-row insert is dramatically slower than
building each index once over the finished table.
work_mem is also raised for the session so the join doesn't spill to disk, and maintenance_work_mem
is raised so the index rebuild itself runs faster.

Filters applied at load (documented in profiling_notes.md as the
"all downstream queries" baseline — data-quality exclusions only):
  - ppd_category = 'A'   (standard sales only; B = repossessions/portfolios)
  - price >= 10000        (removes 24,772 suspiciously low entries)

NOT filtered here: partial-year 2026 data. profiling_notes.md scopes that
exclusion to "trend queries" specifically — it's an analysis-time fairness
concern (comparing 5 months of 2026 to full prior years).
A 2026 Cat A sale >= £10k is valid and belongs in the warehouse,
e.g. "latest median price" / "YTD transaction count" KPIs need it. Queries
that compute YoY or other full-year comparisons should add their own
guard, e.g. WHERE year < EXTRACT(YEAR FROM CURRENT_DATE)::INT.

Runtime: ~10–20 min on a MacBook (dominated by the 6.5 GB COPY in Step 1).
"""

import os
import psycopg2

DATA_DIR = os.path.join(os.path.dirname(__file__), '..', 'data', 'raw')
PPD_FILE = os.path.abspath(os.path.join(DATA_DIR, 'pp-complete.csv'))

# ── DB connection ──
DB = dict(
    host     = os.environ.get('PGHOST', 'localhost'),
    dbname   = os.environ.get('PGDATABASE', 'ew_housing'),
    user     = os.environ.get('PGUSER', 'postgres'),
    password = os.environ['PGPASSWORD'],   # required — KeyError if not set
    port     = int(os.environ.get('PGPORT', 5432)),
)

conn = psycopg2.connect(**DB)
conn.autocommit = False   # explicit transaction control throughout
cur  = conn.cursor()

# ── Step 1: Staging table ──
# pp-complete.csv has NO header row. Columns in order:
#   transaction_id, price, date_of_transfer, postcode, property_type,
#   old_new, duration, paon, saon, street, locality, town, district,
#   county, ppd_category, record_status
print("Step 1: Creating staging table and loading raw CSV ...")
print(f"  File: {PPD_FILE}")

cur.execute("DROP TABLE IF EXISTS staging_ppd;")
cur.execute("""
    CREATE UNLOGGED TABLE staging_ppd (
        transaction_id   TEXT,
        price            TEXT,
        date_of_transfer TEXT,
        postcode         TEXT,
        property_type    TEXT,
        old_new          TEXT,
        duration         TEXT,
        paon             TEXT,
        saon             TEXT,
        street           TEXT,
        locality         TEXT,
        town             TEXT,
        district         TEXT,
        county           TEXT,
        ppd_category     TEXT,
        record_status    TEXT
    );
""")
# UNLOGGED = no write-ahead log for this table; much faster for a temp staging table, but data will be lost if the transaction fails or the server crashes. 
# We will drop this table at the end of the script.

with open(PPD_FILE, 'r', encoding='utf-8') as f:
    cur.copy_expert(
        "COPY staging_ppd FROM STDIN WITH (FORMAT CSV, QUOTE '\"')",
        f,
    )

conn.commit()

cur.execute("SELECT COUNT(*) FROM staging_ppd;")
total = cur.fetchone()[0]
print(f"  Rows loaded into staging_ppd: {total:,}")


# ── Step 2: Populate dim_date ──
print("\nStep 2: Populating dim_date ...")

cur.execute("TRUNCATE dim_date CASCADE;")
cur.execute("""
    INSERT INTO dim_date (date_key, full_date, year, quarter, month, month_name)
    SELECT DISTINCT
        TO_CHAR(d, 'YYYYMMDD')::INT            AS date_key,
        d                                       AS full_date,
        EXTRACT(YEAR    FROM d)::SMALLINT       AS year,
        EXTRACT(QUARTER FROM d)::SMALLINT       AS quarter,
        EXTRACT(MONTH   FROM d)::SMALLINT       AS month,
        TO_CHAR(d, 'Month')                     AS month_name
    FROM (
        SELECT DISTINCT
            TO_DATE(LEFT(date_of_transfer, 10), 'YYYY-MM-DD') AS d
        FROM staging_ppd
        WHERE date_of_transfer IS NOT NULL
    ) dates
    ORDER BY date_key;
""")
conn.commit()

cur.execute("SELECT COUNT(*) FROM dim_date;")
print(f"  dim_date rows: {cur.fetchone()[0]:,}")


# ── Step 3: Populate fact_sales ──
print("\nStep 3: Populating fact_sales (this is the slow step) ...")

# Drop fact_sales' 4 indexes before the bulk insert. Maintaining indexes
# incrementally across a ~29.5M-row insert is far slower than building
# each one once over the finished table — see the module docstring.
print("  Dropping indexes on fact_sales ...")
cur.execute("DROP INDEX IF EXISTS idx_fact_date;")
cur.execute("DROP INDEX IF EXISTS idx_fact_geo;")
cur.execute("DROP INDEX IF EXISTS idx_fact_type;")
cur.execute("DROP INDEX IF EXISTS idx_fact_year;")
conn.commit()

# Raise work_mem / maintenance_work_mem for this session only (SET).
# Gives the join more room before it spills to disk, and speeds up the index rebuild below.
cur.execute("SET work_mem = '256MB';")
cur.execute("SET maintenance_work_mem = '1GB';")

cur.execute("TRUNCATE fact_sales;")
cur.execute("""
    INSERT INTO fact_sales (
        transaction_id,
        price,
        date_key,
        type_code,
        tenure,
        is_new_build,
        ppd_category,
        geo_key
    )
    SELECT
        -- Strip curly braces from UUID: {2A289E9F-...} -> 2A289E9F-...
        REPLACE(REPLACE(s.transaction_id, '{', ''), '}', '')::UUID,
        s.price::INT,
        TO_CHAR(TO_DATE(LEFT(s.date_of_transfer, 10), 'YYYY-MM-DD'), 'YYYYMMDD')::INT,
        s.property_type,
        s.duration,
        (s.old_new = 'Y'),   -- 'Y' -> true (new build), 'N' -> false
        s.ppd_category,
        g.geo_key            -- NULL if postcode not found in dim_geography
    FROM staging_ppd s
    LEFT JOIN dim_geography g ON g.postcode = TRIM(s.postcode)
    WHERE s.ppd_category = 'A'
      AND s.price::INT     >= 10000;
    -- Intentionally no year filter (see module docstring Partial-2026 note)
""")
conn.commit()

cur.execute("SELECT COUNT(*) FROM fact_sales;")
print(f"  fact_sales rows: {cur.fetchone()[0]:,}")

# Rebuild indexes now that the table is fully loaded, same definitions as sql/01_schema_ddl.sql.
print("  Rebuilding indexes on fact_sales ...")
cur.execute("CREATE INDEX idx_fact_date ON fact_sales(date_key);")
cur.execute("CREATE INDEX idx_fact_geo  ON fact_sales(geo_key);")
cur.execute("CREATE INDEX idx_fact_type ON fact_sales(type_code);")
cur.execute("CREATE INDEX idx_fact_year ON fact_sales((date_key / 10000));")
conn.commit()

# ANALYZE refreshes planner statistics now that fact_sales holds real data,
# without it, the planner is still working off stats from the (empty) truncated table which can lead to bad query plans later.
print("  Running ANALYZE on fact_sales ...")
cur.execute("ANALYZE fact_sales;")
conn.commit()


# ── Step 4: Sanity checks ──
print("\nStep 4: Sanity checks ...")

cur.execute("""
    SELECT
        MIN(date_key / 10000) AS min_year,
        MAX(date_key / 10000) AS max_year,
        MIN(price)            AS min_price,
        MAX(price)            AS max_price,
        COUNT(*)              AS total_sales,
        SUM(CASE WHEN geo_key IS NULL THEN 1 ELSE 0 END) AS unmapped_postcodes
    FROM fact_sales;
""")
row = cur.fetchone()
print(f"  Year range:         {row[0]} – {row[1]}")
print(f"  Price range:        £{row[2]:,} – £{row[3]:,}")
print(f"  Total sales:        {row[4]:,}")
print(f"  Unmapped postcodes: {row[5]:,}")

cur.execute("""
    SELECT pt.type_name, COUNT(*) AS sales
    FROM fact_sales f
    JOIN dim_property_type pt ON pt.type_code = f.type_code
    GROUP BY pt.type_name
    ORDER BY sales DESC;
""")
print("\n  Sales by property type:")
for name, count in cur.fetchall():
    print(f"    {name:<20} {count:>12,}")

cur.execute("""
    SELECT dg.region_name, COUNT(*) AS sales
    FROM fact_sales f
    JOIN dim_geography dg ON dg.geo_key = f.geo_key
    GROUP BY dg.region_name
    ORDER BY sales DESC;
""")
print("\n  Sales by region:")
for region, count in cur.fetchall():
    print(f"    {str(region):<30} {count:>12,}")

# Drop staging table
cur.execute("DROP TABLE staging_ppd;")
conn.commit()
print("\nStaging table dropped. Done.")

cur.close()
conn.close()
