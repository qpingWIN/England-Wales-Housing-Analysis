"""
04_backfill_lad_names.py
-------------------------
Adds human-readable Local Authority District (LAD) names to dim_geography.

What it does:
  1. ALTER TABLE dim_geography ADD COLUMN IF NOT EXISTS lad_name TEXT;
     (idempotent -safe to re-run)
  2. Loads the ONS "LAD Names and Codes" lookup (LAD25CD, LAD25NM) into a
     temp staging table via COPY.
  3. UPDATEs dim_geography.lad_name by joining the staging table to
     dim_geography on lad_code (uses the existing idx_geo_lad index).
  4. Reports match counts as a sanity check, a large "unmatched" count
     would mean the lookup file's vintage doesn't line up with ONSPD's
     lad25cd codes and is worth investigating before trusting query #4.

Source: ONS Open Geography Portal, "Local Authority Districts (April 2025)
Names and Codes in the UK (V2)", matches the lad25cd vintage used in
ONSPD_MAY_2026_UK.csv (both are 2025-boundary LAD codes).

Runtime: a few seconds - 361 lookup rows joined against dim_geography via
an indexed column, nowhere near the scale of the main ETL scripts.
"""

import os
import io
import pandas as pd
import psycopg2

DATA_DIR = os.path.join(os.path.dirname(__file__), '..', 'data', 'raw')
LAD_FILE = os.path.abspath(os.path.join(DATA_DIR, 'LAD25_names_and_codes.csv'))

# ── DB connection ──
DB = dict(
    host     = os.environ.get('PGHOST', 'localhost'),
    dbname   = os.environ.get('PGDATABASE', 'ew_housing'),
    user     = os.environ.get('PGUSER', 'postgres'),
    password = os.environ['PGPASSWORD'],   # required — KeyError if not set
    port     = int(os.environ.get('PGPORT', 5432)),
)

print("Reading LAD names/codes lookup ...")
print(f"  File: {LAD_FILE}")
df = pd.read_csv(LAD_FILE, dtype=str, usecols=['LAD25CD', 'LAD25NM'])
df = df.rename(columns={'LAD25CD': 'lad_code', 'LAD25NM': 'lad_name'})
print(f"  Lookup rows: {len(df):,}")

conn = psycopg2.connect(**DB)
conn.autocommit = False
cur = conn.cursor()

print("\nAdding lad_name column to dim_geography (if not already present) ...")
cur.execute("ALTER TABLE dim_geography ADD COLUMN IF NOT EXISTS lad_name TEXT;")
conn.commit()

print("Loading lookup into a temp staging table ...")
cur.execute("""
    CREATE TEMP TABLE staging_lad_names (
        lad_code TEXT,
        lad_name TEXT
    );
""")
buffer = io.StringIO()
df.to_csv(buffer, index=False, header=False)
buffer.seek(0)
cur.copy_expert(
    "COPY staging_lad_names (lad_code, lad_name) FROM STDIN WITH (FORMAT CSV)",
    buffer,
)
conn.commit()

print("Updating dim_geography.lad_name (non-destructive because no TRUNCATE) ...")
cur.execute("""
    UPDATE dim_geography g
    SET lad_name = s.lad_name
    FROM staging_lad_names s
    WHERE g.lad_code = s.lad_code;
""")
conn.commit()

cur.execute("""
    SELECT
        COUNT(*) AS total_rows,
        SUM(CASE WHEN lad_name IS NOT NULL THEN 1 ELSE 0 END) AS matched,
        SUM(CASE WHEN lad_code IS NOT NULL AND lad_name IS NULL THEN 1 ELSE 0 END) AS unmatched_with_code
    FROM dim_geography;
""")
total, matched, unmatched = cur.fetchone()
print(f"\n  dim_geography rows:              {total:,}")
print(f"  Rows with lad_name populated:    {matched:,}")
print(f"  Rows with lad_code but no match: {unmatched:,}")

cur.close()
conn.close()
print("\nDone.")
