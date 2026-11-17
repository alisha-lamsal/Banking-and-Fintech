# 03_strip_bom_acs.py
# Removes the hidden byte-order mark (BOM) that some ACS CSV downloads from
# data.census.gov start with. Stata misreads the first column name when it is
# there. Run this once before scripts/04_poster_analysis.do.
# Files are modified in place; files without a BOM are left unchanged.

import glob
import os

FOLDERS = [
    os.path.join("data", "raw", "ACS_Education"),   # ACSST5Y<year>.S1501-Data.csv
    os.path.join("data", "raw", "ACS_Broadband"),   # ACSDT5Y<year>.B28002-Data.csv
]

BOM = b'\xef\xbb\xbf'

print("Stripping BOM from ACS files...")
print()

for folder in FOLDERS:
    for path in sorted(glob.glob(os.path.join(folder, "*.csv"))):
        filename = os.path.basename(path)
        with open(path, 'rb') as f:
            content = f.read()

        if content[:3] == BOM:
            with open(path, 'wb') as f:
                f.write(content[3:])
            print("  FIXED: " + filename + " (BOM removed)")
        else:
            print("  OK:    " + filename + " (no BOM, unchanged)")

print()
print("Done. Now run scripts/04_poster_analysis.do in Stata.")
