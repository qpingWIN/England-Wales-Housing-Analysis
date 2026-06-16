"""
02_load_onspd.py
----------------
Loads the ONS Postcode Directory (ONSPD) into dim_geography.

What it does:
  1. Reads ONSPD_MAY_2026_UK.csv (all postcodes in the UK file)
  2. Filters to England & Wales only (ctry25cd starting with E or W)
  3. Derives outcode and region_name from raw codes
  4. Bulk-inserts into dim_geography using COPY (fast path)

Runtime: ~30 seconds on a 2M-row ONSPD file.
"""

import os
import io
import pandas as pd
import psycopg2

# ── Config ─
DATA_DIR   = os.path.join(os.path.dirname(__file__), '..', 'data', 'raw')
ONSPD_FILE = os.path.join(DATA_DIR, 'ONSPD_MAY_2026_UK.csv')

# ── DB connection ──
DB = dict(
    host     = os.environ.get('PGHOST', 'localhost'),
    dbname   = os.environ.get('PGDATABASE', 'ew_housing'),
    user     = os.environ.get('PGUSER', 'postgres'),
    password = os.environ['PGPASSWORD'],   # required — KeyError if not set
    port     = int(os.environ.get('PGPORT', 5432)),
)

# ONS region code -> human-readable name
REGION_NAMES = {
    'E12000001': 'North East',
    'E12000002': 'North West',
    'E12000003': 'Yorkshire and The Humber',
    'E12000004': 'East Midlands',
    'E12000005': 'West Midlands',
    'E12000006': 'East of England',
    'E12000007': 'London',
    'E12000008': 'South East',
    'E12000009': 'South West',
    'W92000004': 'Wales',
}

# ── Load ──
print("Reading ONSPD file ...")
df = pd.read_csv(
    ONSPD_FILE,
    usecols=['pcds', 'lad25cd', 'rgn25cd', 'ctry25cd', 'lat', 'long'],
    dtype=str,          # read everything as text first, cast below
    low_memory=False,
)
print(f"  Total rows: {len(df):,}")

# Filter: England (E) and Wales (W) only, drop Scotland (S) and Norn Ireland (N)
df = df[df['ctry25cd'].str.startswith(('E', 'W'), na=False)].copy()
print(f"  After E&W filter: {len(df):,}")

# Drop rows with no postcode or no lat/long (terminated postcodes etc)
df = df.dropna(subset=['pcds', 'lat', 'long'])
df = df[df['lat'] != '99.999999']   # ONSPD value for "no coordinates"
print(f"  After dropping missing coords: {len(df):,}")

# Derive columns
df['postcode'] = df['pcds'].str.strip()
df['outcode'] = df['postcode'].str.split(' ').str[0]
df['lad_code'] = df['lad25cd'].str.strip()
df['region_code'] = df['rgn25cd'].str.strip()
df['region_name'] = df['region_code'].map(REGION_NAMES)
df.loc[df['ctry25cd'].str.startswith('W'), 'region_name'] = 'Wales'  # Wales has no rgn25cd
df['country'] = df['ctry25cd'].apply(
    lambda x: 'Wales' if x.startswith('W') else 'England'
)
df['latitude'] = pd.to_numeric(df['lat'],  errors='coerce')
df['longitude'] = pd.to_numeric(df['long'], errors='coerce')

# Final column selection, matches dim_geography (excluding auto geo_key)
output = df[[
    'postcode', 'outcode', 'lad_code', 'region_code',
    'region_name', 'country', 'latitude', 'longitude',
]]

print(f"\nSample (first 3 rows):")
print(output.head(3).to_string(index=False))

# ── Insert via COPY ───
print(f"\nConnecting to database …")
conn = psycopg2.connect(**DB)
cur  = conn.cursor()

# Truncate first so the script is safe to re-run
cur.execute("TRUNCATE dim_geography RESTART IDENTITY CASCADE;")

print(f"Copying {len(output):,} rows into dim_geography …")
buffer = io.StringIO()
output.to_csv(buffer, index=False, header=False, na_rep='')
buffer.seek(0)

cur.copy_expert(
    """
    COPY dim_geography (postcode, outcode, lad_code, region_code,
                        region_name, country, latitude, longitude)
    FROM STDIN WITH (FORMAT CSV, NULL '')
    """,
    buffer,
)

conn.commit()
cur.close()
conn.close()

print("Done. dim_geography loaded.")

# ── Quick sanity check ───
conn = psycopg2.connect(**DB)
cur  = conn.cursor()
cur.execute("""
    SELECT country, region_name, COUNT(*) AS postcodes
    FROM dim_geography
    GROUP BY country, region_name
    ORDER BY country, region_name;
""")
rows = cur.fetchall()
print("\nPostcodes by region:")
print(f"  {'Country':<10} {'Region':<30} {'Postcodes':>10}")
print(f"  {'-'*10} {'-'*30} {'-'*10}")
for country, region, count in rows:
    print(f"  {str(country):<10} {str(region):<30} {count:>10,}")

cur.close()
conn.close()
