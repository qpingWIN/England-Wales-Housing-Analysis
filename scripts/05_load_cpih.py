"""
Loads the ONS CPIH (Consumer Prices Index including owner occupiers'
housing costs) annual index into dim_cpih, for deflating nominal house
prices to real terms in query #16.

What it does:
  1. CREATE TABLE IF NOT EXISTS dim_cpih (idempotent, safe to re-run,
     and deliberately does NOT touch fact_sales/dim_geography/dim_date/
     dim_property_type. sql/00_schema_ddl.sql documents dim_cpih as
     part of the canonical schema for from-scratch rebuilds, but that
     file DROPs every table. We don't want to re-run smth against the
     already populated live database. This script is the actual
     mechanism for adding dim_cpih to a database that already has
     29M fact_sales rows loaded.)
  2. Reads the ONS time series CSV, which interleaves annual, quarterly
     and monthly rows in a single file. Keeps only rows whose period
     is a bare 4-digit year (e.g. "2015") via regex, quarterly rows
     are labelled like "2015 Q1" and monthly rows like "2015 JAN", so
     anchoring on "digits only" cleanly separates annual figures
     without depending on the exact header boilerplate ONS puts above
     the data.
  3. Upserts into dim_cpih, so re-running after
     ONS revises a figure or after a new year's figure is published,
     doesn't require a manual delete first.
  4. Reports the loaded row count and year range as a sanity check.

Source: ONS series L522, "CPIH INDEX 00: ALL ITEMS 2015=100", part of
the "Consumer price inflation time series" dataset (MM23).
Download: https://www.ons.gov.uk/generator?format=csv&uri=/economy/inflationandpriceindices/timeseries/l522/mm23
Licence: Open Government Licence v3.0 (same as the PPD/ONSPD sources).

Runtime: under a second, 38 rows.
"""

import os
import re
import csv
import psycopg2

DATA_DIR = os.path.join(os.path.dirname(__file__), '..', 'data', 'raw')
CPIH_FILE = os.path.abspath(os.path.join(DATA_DIR, 'cpih_l522.csv'))

# ── DB connection ──
DB = dict(
    host     = os.environ.get('PGHOST', 'localhost'),
    dbname   = os.environ.get('PGDATABASE', 'ew_housing'),
    user     = os.environ.get('PGUSER', 'postgres'),
    password = os.environ['PGPASSWORD'],   # required — KeyError if not set
    port     = int(os.environ.get('PGPORT', 5432)),
)

YEAR_ROW = re.compile(r'^\d{4}$')

print("Reading CPIH annual index ...")
print(f"  File: {CPIH_FILE}")
rows = []
with open(CPIH_FILE, newline='') as f:
    for row in csv.reader(f):
        if len(row) >= 2 and YEAR_ROW.match(row[0].strip()):
            year = int(row[0].strip())
            value = float(row[1].strip())
            rows.append((year, value))

if not rows:
    raise SystemExit(
        "No annual CPIH rows parsed — check that the file is the L522 "
        "time series CSV and that its period column still uses bare "
        "4-digit years for annual figures."
    )
print(f"  Annual rows found: {len(rows)} ({rows[0][0]}-{rows[-1][0]})")

conn = psycopg2.connect(**DB)
conn.autocommit = False
cur = conn.cursor()

print("\nCreating dim_cpih (if not already present) ...")
cur.execute("""
    CREATE TABLE IF NOT EXISTS dim_cpih (
        year        SMALLINT      PRIMARY KEY,
        cpih_index  NUMERIC(6, 1) NOT NULL   -- 2015 = 100.0
    );
""")
conn.commit()

print("Upserting annual CPIH values ...")
cur.executemany("""
    INSERT INTO dim_cpih (year, cpih_index)
    VALUES (%s, %s)
    ON CONFLICT (year) DO UPDATE SET cpih_index = EXCLUDED.cpih_index;
""", rows)
conn.commit()

cur.execute("SELECT COUNT(*), MIN(year), MAX(year) FROM dim_cpih;")
total, min_yr, max_yr = cur.fetchone()
print(f"\n  dim_cpih rows: {total} (years {min_yr}-{max_yr})")

cur.close()
conn.close()
print("\nDone.")
