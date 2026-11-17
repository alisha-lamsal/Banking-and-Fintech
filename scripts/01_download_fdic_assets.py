"""
01_download_fdic_assets.py
==========================
Downloads year-end total assets for every FDIC-insured institution
from the FDIC BankFind Suite API (Financials endpoint).

SOURCE:
  FDIC BankFind Suite API - Financials
  https://banks.data.fdic.gov/api/financials
  Variable: ASSET = Total assets, thousands of nominal USD
  Report date: December 31 each year (year-end Call Report)

DESIGN CHOICE:
  Assets are kept in NOMINAL dollars each year (not deflated).
  community_bank = 1 if assets <= $10 billion that year.

COMMUNITY BANK DEFINITION (Minton et al. 2024, NBER WP 32521):
  Commercial bank (BKCLASS N, NM, SM) with total assets
  <= $10 billion in that year's nominal dollars.
  $10 billion = 10,000,000 thousands of dollars.

OUTPUT:
  FDIC_Assets_New.csv with columns:
    cert           - FDIC certificate number (merge key to SOD)
    year           - report year (December 31)
    asset          - total assets, nominal thousands USD
    community_bank - 1 if asset <= $10B (nominal)
                     NOTE: commercial bank filter (BKCLASS N/NM/SM)
                     is applied in Stata after merging with SOD.

MERGE KEY TO SOD:
  Merge on: cert + year

USAGE:
  python 01_download_fdic_assets.py
  Output saved to data/raw/FDIC_Assets_New.csv (read by the Stata do-file).
"""

import requests
import pandas as pd
import time
import os

# Settings
API_BASE   = "https://banks.data.fdic.gov/api/financials"
THRESHOLD  = 10000000      # $10 billion in thousands of USD
START_YEAR = 1993          # one year before sample start (for lagging)
END_YEAR   = 2024
LIMIT      = 10000         # max rows per API request
OUT_FILE   = os.path.join("data", "raw",
                          "FDIC_Assets_New.csv")

print("=" * 60)
print("FDIC BankFind API - Annual Asset Download")
print("Coverage: " + str(START_YEAR) + "-" + str(END_YEAR) + " (December 31 year-end)")
print("Threshold: $10 billion = " + str(THRESHOLD) + " thousands USD")
print("Output: " + OUT_FILE)
print("=" * 60)

# Download one year at a time - more reliable than one giant request
all_records = []

for year in range(START_YEAR, END_YEAR + 1):

    # December 31 report date in YYYYMMDD format
    repdte = str(year) + "1231"

    print("  Downloading " + str(year) + " (repdte=" + repdte + ")...", end=" ")

    offset = 0
    year_records = []

    while True:
        params = {
            "filters":    "REPDTE:" + repdte,
            "fields":     "CERT,REPDTE,ASSET",
            "limit":      LIMIT,
            "offset":     offset,
            "sort_by":    "CERT",
            "sort_order": "ASC",
            "output":     "json"
        }

        try:
            resp = requests.get(API_BASE, params=params, timeout=60)
            resp.raise_for_status()
            data = resp.json()
        except requests.exceptions.RequestException as e:
            print("\n    WARNING: Request failed: " + str(e))
            print("    Retrying in 10 seconds...")
            time.sleep(10)
            try:
                resp = requests.get(API_BASE, params=params, timeout=60)
                resp.raise_for_status()
                data = resp.json()
            except Exception as e2:
                print("    ERROR: Second attempt failed: " + str(e2))
                break

        records = data.get("data", [])

        if not records:
            break

        for rec in records:
            d = rec.get("data", rec)
            cert  = d.get("CERT")  or d.get("cert")
            asset = d.get("ASSET") or d.get("asset")

            if cert is None or asset is None:
                continue

            try:
                cert  = int(cert)
                asset = float(asset)
            except (ValueError, TypeError):
                continue

            year_records.append({
                "cert":  cert,
                "year":  year,
                "asset": asset
            })

        if len(records) < LIMIT:
            break

        offset += LIMIT
        time.sleep(0.2)

    print(str(len(year_records)) + " institutions")
    all_records.extend(year_records)
    time.sleep(0.5)

# Build dataframe
print()
print("Building dataset...")
df = pd.DataFrame(all_records)

if df.empty:
    print("ERROR: No data downloaded. Check internet connection.")
    exit(1)

print("Total rows before cleaning: " + str(len(df)))

# Remove duplicates
df = df.drop_duplicates(subset=["cert", "year"], keep="first")
print("Total rows after dedup:     " + str(len(df)))

# Drop missing or zero assets
df = df[df["asset"].notna() & (df["asset"] > 0)]
print("Total rows after asset drop: " + str(len(df)))

# Apply community bank flag
# 1 if assets <= $10 billion nominal
# Commercial bank filter (BKCLASS) applied later in Stata
df["community_bank"] = (df["asset"] <= THRESHOLD).astype(int)

# Sort and save
df = df.sort_values(["cert", "year"]).reset_index(drop=True)
os.makedirs(os.path.dirname(OUT_FILE), exist_ok=True)
df.to_csv(OUT_FILE, index=False)

# Summary
print()
print("=" * 60)
print("DOWNLOAD COMPLETE")
print("Output: " + OUT_FILE)
print("Total rows: " + str(len(df)))
print()
print("Year | Institutions | Below $10B | Pct")
summary = df.groupby("year").agg(
    n=("cert", "count"),
    cb=("community_bank", "sum")
).reset_index()
summary["pct"] = summary["cb"] / summary["n"] * 100
for _, r in summary.iterrows():
    print("  " + str(int(r.year)) + ":  " + str(int(r.n)) + "  |  " +
          str(int(r.cb)) + "  |  " + str(round(r.pct, 1)) + "%")

print()
print("Column descriptions:")
print("  cert           - FDIC certificate number (merge to SOD on cert+year)")
print("  year           - Report year (December 31 year-end)")
print("  asset          - Total assets, nominal thousands USD")
print("  community_bank - 1 if asset <= $10B nominal")
print()
print("NEXT: In Stata, merge on cert+year, then apply BKCLASS filter")
print("  gen community_bank_final = community_bank & inlist(bkclass,'N','NM','SM')")
print("=" * 60)
