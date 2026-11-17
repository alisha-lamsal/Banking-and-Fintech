import pandas as pd
import os
import glob
import re

INPUT_FOLDER  = os.path.join("data", "raw", "sod")         # FDIC SOD CSVs, one per year
OUTPUT_FOLDER = os.path.join("data", "processed", "sod")

KEEP_COLS = [
    'YEAR',
    'CERT',
    'UNINUMBR',
    'RSSDID',
    'NAMEFULL',
    'BRNUM',
    'STCNTYBR',
    'CNTYNAMB',
    'STALPBR',
    'STNAMEBR',
    'BKCLASS',
    'BRSERTYP',
    'DEPSUMBR',
    'SIMS_LATITUDE',
    'SIMS_LONGITUDE',
]

os.makedirs(OUTPUT_FOLDER, exist_ok=True)
csv_files = sorted(glob.glob(os.path.join(INPUT_FOLDER, "*.csv")))

if not csv_files:
    print("ERROR: No CSV files found in: " + INPUT_FOLDER)
    exit(1)

print("=" * 60)
print("SOD Slimming Script")
print("Input:  " + INPUT_FOLDER)
print("Output: " + OUTPUT_FOLDER)
print("Keeping " + str(len(KEEP_COLS)) + " columns including YEAR")
print("Files found: " + str(len(csv_files)))
print("=" * 60)

total_rows = 0

for filepath in csv_files:
    filename = os.path.basename(filepath)
    out_path = os.path.join(OUTPUT_FOLDER, filename)

    # Extract year from filename - looks for 4-digit year e.g. 1994, 2021
    year_match = re.search(r'(\d{4})_06_30', filename)
    if not year_match:
        year_match = re.search(r'(\d{4})', filename)
    if not year_match:
        print("  WARNING: Cannot extract year from: " + filename + " - skipping")
        continue
    file_year = int(year_match.group(1))

    # Read file - skip bad rows, handle special characters
    df = pd.read_csv(filepath, low_memory=False,
                     on_bad_lines='skip',
                     encoding='latin-1')

    df.columns = [c.upper() for c in df.columns]

    # Add YEAR column from filename if not already present
    if 'YEAR' not in df.columns:
        df['YEAR'] = file_year
   
    # Keep only needed columns
    cols_present = [c for c in KEEP_COLS if c in df.columns]
    cols_missing  = [c for c in KEEP_COLS if c not in df.columns]

    df_slim = df[cols_present].copy()
    df_slim.to_csv(out_path, index=False)

    total_rows += len(df_slim)
    msg = "  " + filename + " (year=" + str(file_year) + ") -> " + str(len(df_slim)) + " rows"
    if cols_missing:
        msg += " | MISSING: " + ", ".join(cols_missing)
    print(msg)

print()
print("DONE. Total rows: " + str(total_rows))
print("Expected: ~2,746,868 rows across 31 files")
print("Output: " + OUTPUT_FOLDER)