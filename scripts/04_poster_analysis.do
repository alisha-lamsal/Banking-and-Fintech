/*====================================================================*
   FILLING THE VOID? NEOBANK ENTRY AND COMMUNITY BANKING DESERTS
   AFTER BRANCH CLOSURES - full poster analysis (Stata)

   Reconstructed from the Stata log of the final run (19 Apr 2026).
   Changes from that run:
   - Folder paths are set once below.
   - The banking-desert profile (old Section 3D) runs after Section 5,
     which builds the merged panel it reads.
   - Branches are counted with (count) ... = year instead of = uninumbr.
     UNINUMBR is blank for 6-10% of branch records before 2011, so
     counting it undercounted branches in 1994-2010.

   Inputs ($input):  FDIC_Assets_New.csv (scripts/01_download_fdic_assets.py)
                     BEA_Income.csv (CAINC1), CO-EST2024-ALLDATA.csv,
                     CO-EST2019-ALLDATA.csv, CO-EST2000INT-TOT.csv,
                     ACS_Education\ACSST5Y<year>.S1501-Data.csv (2010-2024),
                     ACS_Broadband\ACSDT5Y<year>.B28002-Data.csv (2017-2024),
                     tl_2023_us_county shapefile (Census TIGER)
   SOD files ($sod_folder): output of scripts/02_slim_sod_files.py
   Requires: ssc install outreg2, shp2dta, spmap
====================================================================*/

/*--------------------------------------------------------------------*
   SECTION 0: SETUP - set the project folder once
*--------------------------------------------------------------------*/

clear all
set more off

global root       "."                              // project folder
global sod_folder "$root\data\processed\sod"
global input      "$root\data\raw"
global output     "$root\output"

capture mkdir "$output"
capture log close
log using "$output\Poster_Analysis_Log.txt", replace text

di "POSTER ANALYSIS STARTED: " c(current_date) " " c(current_time)

/*====================================================================*
   SECTION 1: STACK ALL YEARLY SOD FILES
   One row per branch per year. UNINUMBR = unique branch identifier.
====================================================================*/

clear
tempfile master
save `master', emptyok replace

local n_files = 0
local filelist : dir "$sod_folder" files "*.csv"

foreach f of local filelist {

    di "  Importing: `f'"

    import delimited "$sod_folder\\`f'",  ///
        varnames(1) stringcols(_all)       ///
        bindquote(strict) encoding(utf-8)  ///
        clear

    capture confirm variable year
    if _rc != 0 {
        di "  WARNING: no YEAR variable - skipping `f'"
        continue
    }

    foreach v in year stcntybr cert uninumbr rssdid depsumbr sims_latitude sims_longitude {
        capture confirm variable `v'
        if _rc == 0 destring `v', replace force
    }

    append using `master'
    save `master', replace

    local n_files = `n_files' + 1
    di "    -> OK (running total: " _N " obs)"
}

di "Files processed: `n_files'"
di "Total observations: " _N
tab year

label variable year      "FDIC SOD survey year (as of June 30)"
label variable cert      "FDIC Certificate number (institution merge key)"
label variable uninumbr  "Unique branch number (UNINUMBR)"
label variable rssdid    "Federal Reserve bank number (RSSDID)"
label variable stcntybr  "5-digit state+county FIPS - branch location"
label variable cntynamb  "County name - branch location"
label variable stalpbr   "State abbreviation - branch location"
capture label variable depsumbr "Branch deposits as of June 30 (thousands USD)"
label variable bkclass   "Institution charter class (FDIC)"
capture label variable namefull "Institution full name"
capture label variable brnum    "Branch office number"

destring brsertyp, replace force
gen fullservice = (brsertyp == 11 | brsertyp == 12)
label variable fullservice "=1 if full-service branch (BRSERTYP 11 or 12)"

gen commercial_bank = inlist(bkclass, "N", "NM", "SM")
gen savings_bank    = inlist(bkclass, "SB", "SI", "SL")
gen foreign_branch  = (bkclass == "OI")

label variable commercial_bank "=1 if commercial bank (BKCLASS N, NM, SM)"
label variable savings_bank    "=1 if savings institution (SB/SI/SL)"
label variable foreign_branch  "=1 if insured foreign branch (OI)"

gen community_bank = 0
gen regional_bank  = 0
gen megabank       = 0

save "$output\SOD_AllYears_Stacked.dta", replace
di "Section 1 complete: " _N " branch-year rows saved."

/*====================================================================*
   SECTION 1B: BANK TYPE CLASSIFICATION
   Uses FDIC_Assets_New.csv - nominal assets, no deflation.
   Merge key: cert + year
====================================================================*/

import delimited "$input\FDIC_Assets_New.csv", varnames(1) clear
destring cert year asset community_bank, replace force
label variable cert           "FDIC Certificate number"
label variable year           "Report year (December 31)"
label variable asset          "Total assets, nominal thousands USD"
label variable community_bank "=1 if asset <= $10B nominal"
rename community_bank asset_cb_flag
sort cert year
save "$output\FDIC_Assets_New.dta", replace
di "FDIC assets: " _N " institution-year rows"

use "$output\SOD_AllYears_Stacked.dta", clear

merge m:1 cert year using "$output\FDIC_Assets_New.dta", ///
    keepusing(asset asset_cb_flag)
drop if _merge == 2
drop _merge

replace asset         = .  if asset         == .
replace asset_cb_flag = 0  if asset_cb_flag == .

drop community_bank regional_bank megabank

gen community_bank = (asset_cb_flag == 1 & commercial_bank == 1)
gen regional_bank  = (commercial_bank == 1 & asset >  10000000 ///
                      & asset <= 100000000 & asset != .)
gen megabank       = (commercial_bank == 1 & asset > 100000000 & asset != .)

label variable asset          "Total assets, nominal thousands USD"
label variable community_bank "=1 if community bank: comm. bank assets <=$10B nominal"
label variable regional_bank  "=1 if regional bank: comm. bank assets $10B-$100B nominal"
label variable megabank       "=1 if megabank: comm. bank assets >$100B nominal"

gen banktype = ""
replace banktype = "1_Community" if community_bank == 1
replace banktype = "2_Regional"  if regional_bank  == 1
replace banktype = "3_Megabank"  if megabank        == 1
replace banktype = "4_Savings"   if savings_bank    == 1
replace banktype = "5_Foreign"   if foreign_branch  == 1
replace banktype = "6_Other"     if banktype        == ""
label variable banktype "Bank type (5 categories)"

di "===== BANK TYPE CLASSIFICATION CHECK ====="
tab banktype if inlist(year, 1994, 2009, 2024)

save "$output\SOD_AllYears_Stacked.dta", replace
di "Section 1B complete."

/*====================================================================*
   SECTION 2: FIGURE 1A - ALL BANK TYPES TREND (1994-2024)
   Legend placed below chart. Full bank type names used.
====================================================================*/

use "$output\SOD_AllYears_Stacked.dta", clear

preserve

    collapse                                  ///
        (count) total_br    = year    ///
        (sum)   community_br = community_bank  ///
        (sum)   regional_br  = regional_bank   ///
        (sum)   mega_br      = megabank         ///
        (sum)   savings_br   = savings_bank     ///
        , by(year)

    sort year

    label variable total_br     "All FDIC-insured branches"
    label variable community_br "Community Banks (assets <=$10B)"
    label variable regional_br  "Regional Banks ($10B-$100B)"
    label variable mega_br      "Mega Banks (>$100B)"
    label variable savings_br   "Savings Banks"

    save "$output\YearLevel_Summary.dta", replace

    * Figure 1A: All bank types
    * ylabel stops at 100,000 so lines are readable
    * Legend below chart (position 6), horizontal row (cols 5)
    twoway                                                              ///
        (line total_br     year,                                        ///
            lcolor(navy)         lwidth(medthick) lpattern(solid))     ///
        (line community_br year,                                        ///
            lcolor(cranberry)    lwidth(medthick) lpattern(solid))     ///
        (line regional_br  year,                                        ///
            lcolor(forest_green) lwidth(medthick) lpattern(solid))     ///
        (line mega_br      year,                                        ///
            lcolor(orange)       lwidth(medthick) lpattern(solid))     ///
        (line savings_br   year,                                        ///
            lcolor(purple)       lwidth(medthick) lpattern(solid)),    ///
        title("U.S. Bank Branches by Institution Type, 1994-2024",     ///
              size(medium))                                              ///
        xtitle("")                                                       ///
        ytitle("Number of Branches", size(small))                       ///
        xlabel(1994(5)2024, angle(0) labsize(vsmall))                  ///
        ylabel(0(20000)100000, angle(0) labsize(vsmall)                 ///
               format(%9.0fc))                                          ///
        legend(order(1 "All Branches"                                   ///
                     2 "Community Banks (<=$10B)"                       ///
                     3 "Regional Banks ($10B-$100B)"                    ///
                     4 "Mega Banks (>$100B)"                            ///
                     5 "Savings Banks")                                 ///
               position(6) ring(1) cols(3) size(vsmall)                ///
               region(lwidth(none) color(none)))                        ///
        graphregion(color(white)) plotregion(color(white))              ///
        xsize(10) ysize(7)

    graph export "$output\Figure1a_AllTypes_Trend.png", replace width(3200)
    di "Figure 1A saved."

    * Figure 1B: Community banks only
    * Y-axis 25,000-45,000 shows the 28% decline clearly
    twoway                                                              ///
        (line community_br year,                                        ///
            lcolor(cranberry) lwidth(thick) lpattern(solid)),           ///
        title("Community Bank Branches, 1994-2024",                     ///
              size(medium))                                              ///
        xtitle("")                                                       ///
        ytitle("Number of Branches", size(small))                       ///
        xlabel(1994(5)2024, angle(0) labsize(vsmall))                  ///
        ylabel(25000(5000)45000, angle(0) labsize(vsmall)              ///
               format(%9.0fc))                                          ///
        legend(order(1 "Community Banks (<=$10B)")                      ///
               position(6) ring(1) size(small)                          ///
               region(lwidth(none) color(none)))                        ///
        graphregion(color(white)) plotregion(color(white))              ///
        xsize(10) ysize(7)

    graph export "$output\Figure1b_Community_Trend.png", replace width(3200)
    di "Figure 1B saved."

restore

/*====================================================================*
   SECTION 2B: BAR CHART - BRANCH DISTRIBUTION BY BANK TYPE
   1994 vs 2024. Foreign and Other excluded.
====================================================================*/

use "$output\SOD_AllYears_Stacked.dta", clear

preserve
    keep if year == 1994 | year == 2024
    drop if banktype == "5_Foreign" | banktype == "6_Other"

    gen n = 1
    collapse (count) n, by(banktype year)
    rename n num_branches

    gen label = ""
    replace label = "Community Banks"  if banktype == "1_Community"
    replace label = "Regional Banks"   if banktype == "2_Regional"
    replace label = "Mega Banks"       if banktype == "3_Megabank"
    replace label = "Savings Banks"    if banktype == "4_Savings"
    drop if label == ""

    label define yrlab 1994 "1994" 2024 "2024"
    label values year yrlab

    graph bar num_branches,                                             ///
        over(year)                                                      ///
        over(label, sort(1) descending                                  ///
             label(labsize(vsmall) angle(0)))                           ///
        bar(1, color(navy))                                             ///
        bar(2, color(cranberry))                                        ///
        title("Bank Branches by Type: 1994 vs 2024",                   ///
              size(medium))                                              ///
        ytitle("Number of Branches", size(small))                       ///
        ylabel(, format(%9.0fc) labsize(vsmall))                       ///
        legend(order(1 "1994" 2 "2024")                                 ///
               position(6) ring(1) cols(2) size(small)                  ///
               region(lwidth(none) color(none)))                        ///
        graphregion(color(white)) plotregion(color(white))              ///
        xsize(10) ysize(7)

    graph export "$output\Figure2_BankType_Compare.png", replace width(3200)
    di "Figure 2 saved."
restore

/*====================================================================*
   SECTION 3: COUNTY-LEVEL DATASETS
====================================================================*/

use "$output\SOD_AllYears_Stacked.dta", clear

* 1994 county snapshot
preserve
    keep if year == 1994
    collapse                                     ///
        (count) num_branches   = year    ///
        (sum)   community_br   = community_bank   ///
        (sum)   regional_br    = regional_bank    ///
        (sum)   megabank_br    = megabank         ///
        (sum)   savings_br     = savings_bank     ///
        (sum)   deposits_total = depsumbr         ///
        , by(stcntybr cntynamb stalpbr)
    rename stcntybr fips_county
    rename cntynamb county_name
    rename stalpbr  state
    tostring fips_county, gen(fips_str) format("%05.0f")
    destring fips_str, gen(fips_num)
    drop if fips_num > 56999
    drop fips_num
    save "$output\County_1994.dta", replace
    di "County_1994.dta: " _N " counties"
restore

* 2024 county snapshot
preserve
    keep if year == 2024
    collapse                                     ///
        (count) num_branches   = year    ///
        (sum)   community_br   = community_bank   ///
        (sum)   regional_br    = regional_bank    ///
        (sum)   megabank_br    = megabank         ///
        (sum)   savings_br     = savings_bank     ///
        (sum)   deposits_total = depsumbr         ///
        , by(stcntybr cntynamb stalpbr)
    rename stcntybr fips_county
    rename cntynamb county_name
    rename stalpbr  state
    tostring fips_county, gen(fips_str) format("%05.0f")
    destring fips_str, gen(fips_num)
    drop if fips_num > 56999
    drop fips_num
    gen community_share = community_br / num_branches
    gen deposits_mil    = deposits_total / 1000
    save "$output\County_Latest.dta", replace
    di "County_Latest.dta: " _N " counties"
restore

* Full county panel
preserve
    collapse                                     ///
        (count) num_branches   = year    ///
        (sum)   community_br   = community_bank   ///
        (sum)   regional_br    = regional_bank    ///
        (sum)   megabank_br    = megabank         ///
        (sum)   savings_br     = savings_bank     ///
        (sum)   deposits_total = depsumbr         ///
        , by(stcntybr cntynamb stalpbr year)
    rename stcntybr fips_county
    rename cntynamb county_name
    rename stalpbr  state
    gen deposits_mil = deposits_total / 1000
    sort fips_county year
    save "$output\County_Panel.dta", replace
    di "County_Panel.dta: " _N " county-year observations"
restore

di "Section 3 complete."

/*====================================================================*
   SECTION 3B: BANKING DESERT IDENTIFICATION
====================================================================*/

use "$output\County_1994.dta", clear
rename num_branches  branches_1994
rename community_br  community_1994
rename regional_br   regional_1994
rename megabank_br   megabank_1994
rename savings_br    savings_1994
keep fips_county county_name state branches_1994 ///
     community_1994 regional_1994 megabank_1994 savings_1994

merge 1:1 fips_county using "$output\County_Latest.dta"
rename num_branches branches_latest

gen branches_latest_fill = branches_latest
replace branches_latest_fill = 0 if _merge == 1
drop _merge

gen branch_change = branches_latest_fill - branches_1994
gen pct_change    = (branch_change / branches_1994) * 100 ///
    if branches_1994 > 0 & branches_1994 != .

gen desert  = (branches_1994 > 0 & branches_latest_fill == 0 & branches_1994 != .)
gen ct_flag = (state == "CT")

label variable branch_change "Branch change (2024 minus 1994)"
label variable pct_change    "Percent change in branches"
label variable desert        "=1 if banking desert (had branches 1994, zero 2024)"
label variable ct_flag       "=1 if CT reorganization artifact"

save "$output\County_Comparison.dta", replace

di "===== BANKING DESERT SUMMARY ====="
count if desert == 1 & ct_flag == 0
di "True banking deserts (excl CT): " r(N)
count if desert == 1 & ct_flag == 1
di "CT reorganization artifact: " r(N)
count if branch_change < 0 & desert == 0 & ct_flag == 0
di "Partial decline counties: " r(N)
count if branch_change > 0
di "Counties with branch gains: " r(N)

preserve
    keep if desert == 1
    gsort ct_flag state county_name
    export delimited "$output\Table_BankingDeserts.csv", replace
restore

preserve
    keep if desert == 1 & ct_flag == 0
    gen n = 1
    collapse (count) n (sum) branches_lost = branches_1994, by(state)
    rename n desert_counties
    gsort -desert_counties
    export delimited "$output\Table_DesertsByState.csv", replace
restore

/*====================================================================*
   SECTION 3C: REGIONAL COMMUNITY BANK SHARE
   South split into 3 inlist calls (max 10 per call)
====================================================================*/

use "$output\SOD_AllYears_Stacked.dta", clear

* Clean state abbreviation - trim to 2 characters
gen stalpbr2 = substr(strtrim(stalpbr), 1, 2)

gen region = ""
replace region = "Northeast" if inlist(stalpbr2, ///
    "CT","ME","MA","NH","RI","VT","NJ","NY","PA")
replace region = "Midwest" if inlist(stalpbr2, ///
    "IL","IN","MI","OH","WI","IA","KS","MN")
replace region = "Midwest" if inlist(stalpbr2, ///
    "MO","NE","ND","SD")
replace region = "South" if inlist(stalpbr2, ///
    "DE","FL","GA","MD","NC","SC")
replace region = "South" if inlist(stalpbr2, ///
    "VA","DC","WV","AL")
replace region = "South" if inlist(stalpbr2, ///
    "KY","MS","TN","AR","LA","OK","TX")
replace region = "West" if inlist(stalpbr2, ///
    "AZ","CO","ID","MT","NV","NM","UT","WY")
replace region = "West" if inlist(stalpbr2, ///
    "AK","CA","HI","OR","WA")
drop if region == ""

preserve
    keep if year == 1994 | year == 2024

    collapse                               ///
        (count) total_br     = year    ///
        (sum)   community_br = community_bank ///
        , by(region year)

    gen community_pct = community_br / total_br * 100

    graph bar community_pct,                                            ///
        over(year)                                                      ///
        over(region)                                                    ///
        bar(1, color(navy))                                             ///
        bar(2, color(cranberry))                                        ///
        title("Community Bank Branch Share by Region",                  ///
              size(medium))                                              ///
        ytitle("Community Bank Share (%)", size(small))                 ///
        ylabel(0(10)80, labsize(vsmall))                                ///
        legend(order(1 "1994" 2 "2024")                                 ///
               position(6) ring(1) cols(2) size(small)                  ///
               region(lwidth(none) color(none)))                        ///
        graphregion(color(white)) plotregion(color(white))              ///
        xsize(8) ysize(7)

    graph export "$output\Figure3_RegionShare.png", replace width(3200)
    di "Figure 3 saved."

    export delimited "$output\Table_RegionSummary.csv", replace
restore

di "Section 3B-3C complete."

/*====================================================================*
   SECTION 4: MAPS - COUNTY BRANCH DENSITY (1994 vs 2024)
   Comment out shp2dta after first successful run.
====================================================================*/

shp2dta using "$input\tl_2023_us_county",    ///
    data("$output\counties_data.dta")         ///
    coor("$output\counties_coor.dta")         ///
    replace genid(mapid)
di "Shapefile converted."

* Map A: 1994
use "$output\counties_data.dta", clear
rename GEOID fips_str
destring fips_str, gen(fips_num)
drop if fips_num >= 2000  & fips_num < 3000
drop if fips_num >= 15000 & fips_num < 16000
drop if fips_num > 56999
drop fips_num
merge 1:1 fips_str using "$output\County_1994.dta"
replace num_branches = 0 if num_branches == .
drop if _merge == 2
drop _merge
spmap num_branches using "$output\counties_coor.dta", id(mapid)      ///
    fcolor(Blues) clnumber(6)                                          ///
    ocolor(white ..) osize(vvthin ..)                                  ///
    title("Bank Branches per County, 1994", size(large) color(navy))  ///
    legend(title("Branches", size(small)) size(small)                  ///
           position(4) ring(0) region(lwidth(none) color(none)))       ///
    graphregion(color(white) margin(zero)) plotregion(margin(zero))    ///
    xsize(10) ysize(7)
graph export "$output\Figure4a_Map_1994.png", replace width(3600)
di "Map 1994 saved."

* Map B: 2024
use "$output\counties_data.dta", clear
rename GEOID fips_str
destring fips_str, gen(fips_num)
drop if fips_num >= 2000  & fips_num < 3000
drop if fips_num >= 15000 & fips_num < 16000
drop if fips_num > 56999
drop fips_num
merge 1:1 fips_str using "$output\County_Latest.dta"
replace num_branches = 0 if num_branches == .
drop if _merge == 2
drop _merge
spmap num_branches using "$output\counties_coor.dta", id(mapid)      ///
    fcolor(Blues) clnumber(6)                                          ///
    ocolor(white ..) osize(vvthin ..)                                  ///
    title("Bank Branches per County, 2024", size(large) color(navy))  ///
    legend(title("Branches", size(small)) size(small)                  ///
           position(4) ring(0) region(lwidth(none) color(none)))       ///
    graphregion(color(white) margin(zero)) plotregion(margin(zero))    ///
    xsize(10) ysize(7)
graph export "$output\Figure4b_Map_2024.png", replace width(3600)
di "Map 2024 saved."

di "Section 4 complete."

/*====================================================================*
   SECTION 5: EXTERNAL DATASETS - CLEAN AND MERGE
   BEA income, Census population, ACS education + broadband.
   ACS files are single cross-sections (one row per county, no year).
   Each vintage is saved separately and assigned to panel years via
   a replace block - no fabricated rows, no expand.

   ACS Education variable by vintage:
     2010: S1501_C01_015E = Total % bachelor+ (C01 is percent in 2010)
     2015: S1501_C02_015E = Percent % bachelor+
     2020: S1501_C02_015E = Percent % bachelor+
     2023: S1501_C02_015E = Percent % bachelor+
   NOTE: In 2015/2020/2023, C01_015E is a COUNT not a percent.
         Only C02_015E gives the correct percentage value.

   Vintage assignment:
     Education 2010 -> panel years <= 2010
     Education 2015 -> panel years 2011-2015
     Education 2020 -> panel years 2016-2020
     Education 2023 -> panel years >= 2021
     Broadband 2017 -> panel years <= 2017
     Broadband 2020 -> panel years 2018-2020
     Broadband 2023 -> panel years >= 2021
====================================================================*/

* 5A: BEA PER CAPITA INCOME
import delimited "$input\BEA_Income.csv", varnames(1) clear
keep if linecode == 3
gen geofips2 = subinstr(geofips, char(34), "", .)
gen geofips3 = strtrim(geofips2)
destring geofips3, gen(fips_county) force
drop if fips_county == .
drop if mod(fips_county, 1000) == 0
* Wide: v34=1994, v35=1995, ..., v64=2024
keep fips_county v34-v64
forvalues y = 1994/2024 {
    local v = `y' - 1994 + 34
    capture rename v`v' inc`y'
}
* Verify column mapping worked
di "BEA income - checking year coverage:"
capture confirm variable inc1994
if _rc di "WARNING: inc1994 not found - check BEA column mapping"
else   di "inc1994 found - BEA columns mapped correctly"
reshape long inc, i(fips_county) j(year)
rename inc pcpincome
destring pcpincome, force replace
label variable pcpincome   "Per capita personal income (BEA CAINC1, USD)"
label variable fips_county "5-digit state+county FIPS"
sort fips_county year
save "$output\BEA_Clean.dta", replace
di "BEA_Clean.dta: " _N " county-year rows"

* 5B: CENSUS POPULATION
* Coverage: 2000-2024. Years 1994-1999 will be missing (no Census data).
* This restricts the regression sample to 2001-2024 (after 1-year lag).
* Trend charts in Section 2 are unaffected (use SOD data only).

import delimited "$input\CO-EST2024-ALLDATA.csv", varnames(1) clear
keep state county popestimate2020 popestimate2021 popestimate2022 ///
     popestimate2023 popestimate2024
gen fips_county = state * 1000 + county
drop if county == 0
reshape long popestimate, i(fips_county) j(year)
save "$output\Pop_2020s.dta", replace

import delimited "$input\CO-EST2019-ALLDATA.csv", varnames(1) clear
keep state county popestimate2010 popestimate2011 popestimate2012 ///
     popestimate2013 popestimate2014 popestimate2015 popestimate2016 ///
     popestimate2017 popestimate2018 popestimate2019
gen fips_county = state * 1000 + county
drop if county == 0
reshape long popestimate, i(fips_county) j(year)
save "$output\Pop_2010s.dta", replace

import delimited "$input\CO-EST2000INT-TOT.csv", varnames(1) clear
keep state county popestimate2000 popestimate2001 popestimate2002 ///
     popestimate2003 popestimate2004 popestimate2005 popestimate2006 ///
     popestimate2007 popestimate2008 popestimate2009
gen fips_county = state * 1000 + county
drop if county == 0
reshape long popestimate, i(fips_county) j(year)
save "$output\Pop_2000s.dta", replace

use "$output\Pop_2020s.dta", clear
append using "$output\Pop_2010s.dta"
append using "$output\Pop_2000s.dta"
drop if popestimate == . | popestimate == 0
drop state county
label variable popestimate "Annual county population estimate (Census)"
sort fips_county year
save "$output\Population_Panel.dta", replace
di "Population_Panel.dta: " _N " county-year rows (2000-2024)"

* 5C: ACS EDUCATION - one vintage per year 2010-2024
* Folder: $input\ACS_Education\
* Filenames: ACSST5YYYY_S1501-Data.csv (downloaded from data.census.gov)
*
* Correct variable by vintage (verified from actual files):
*   2010-2014: S1501_C01_015E = Total percent bachelor degree+
*   2015-2024: S1501_C02_015E = Percent bachelor degree+ (C01=count in these years)
*
* BOM status: only 2024 file has BOM - strip_bom.py must be run on it.
*   All 2010-2023 files have no BOM.
*
* Panel year assignment:
*   Panel years < 2010  -> use 2010 vintage (earliest available)
*   Panel years 2010-2024 -> exact one-to-one match

global acs_edu "$input\ACS_Education"

forvalues yr = 2010/2023 {

    import delimited "$acs_edu\ACSST5Y`yr'.S1501-Data.csv", varnames(1) clear
    drop in 1

    * FIPS - convert float to int to match panel fips_county type (long)
    gen fips_county_f = real(substr(geo_id, -5, 5))
    gen fips_county   = int(fips_county_f)
    drop fips_county_f
    drop if fips_county == .

    * Select correct percent variable by vintage
    * Destring source variable first (may contain "(X)" suppressed values)
    gen pct_bachelors_`yr' = .
    if `yr' <= 2014 {
        capture confirm variable s1501_c01_015e
        if !_rc {
            capture destring s1501_c01_015e, replace force
            capture replace pct_bachelors_`yr' = s1501_c01_015e
        }
    }
    else {
        capture confirm variable s1501_c02_015e
        if !_rc {
            capture destring s1501_c02_015e, replace force
            capture replace pct_bachelors_`yr' = s1501_c02_015e
        }
    }
    drop if pct_bachelors_`yr' == .

    keep fips_county pct_bachelors_`yr'
    duplicates drop fips_county, force
    sort fips_county
    save "$output\ACS_Educ_`yr'.dta", replace
    di "ACS Education `yr': " _N " counties"
}

* 2024 vintage has dot separator in filename: ACSST5Y2024.S1501-Data.csv
import delimited "$acs_edu\ACSST5Y2024.S1501-Data.csv", varnames(1) clear
drop in 1
gen fips_county_f = real(substr(geo_id, -5, 5))
gen fips_county   = int(fips_county_f)
drop fips_county_f
drop if fips_county == .
gen pct_bachelors_2024 = .
capture confirm variable s1501_c02_015e
if !_rc {
    capture destring s1501_c02_015e, replace force
    capture replace pct_bachelors_2024 = s1501_c02_015e
}
drop if pct_bachelors_2024 == .
keep fips_county pct_bachelors_2024
duplicates drop fips_county, force
sort fips_county
save "$output\ACS_Educ_2024.dta", replace
di "ACS Education 2024: " _N " counties"

* 5D: ACS BROADBAND - one vintage per year 2017-2024
* Folder: $input\ACS_Broadband\
* Filenames: ACSDT5YYYY_B28002-Data.csv
* broadband_rate = B28002_004E / B28002_001E
*
* BOM status: only 2024 file has BOM - strip_bom.py must be run on it.
*   All 2017-2023 files have no BOM.
*
* Panel year assignment:
*   Panel years < 2017  -> use 2017 vintage (earliest available)
*   Panel years 2017-2024 -> exact one-to-one match

global acs_bb "$input\ACS_Broadband"

forvalues yr = 2017/2023 {

    import delimited "$acs_bb\ACSDT5Y`yr'.B28002-Data.csv", varnames(1) clear
    drop in 1

    * FIPS - convert float to int to match panel fips_county type (long)
    gen fips_county_f = real(substr(geo_id, -5, 5))
    gen fips_county   = int(fips_county_f)
    drop fips_county_f
    drop if fips_county == .

    destring b28002_001e b28002_004e, replace force
    gen broadband_rate_`yr' = b28002_004e / b28002_001e
    replace broadband_rate_`yr' = . if broadband_rate_`yr' < 0 | broadband_rate_`yr' > 1

    keep fips_county broadband_rate_`yr'
    drop if broadband_rate_`yr' == .
    duplicates drop fips_county, force
    sort fips_county
    save "$output\ACS_BB_`yr'.dta", replace
    di "ACS Broadband `yr': " _N " counties"
}

* 2024 vintage has dot separator in filename: ACSDT5Y2024.B28002-Data.csv
import delimited "$acs_bb\ACSDT5Y2024.B28002-Data.csv", varnames(1) clear
drop in 1
gen fips_county_f = real(substr(geo_id, -5, 5))
gen fips_county   = int(fips_county_f)
drop fips_county_f
drop if fips_county == .
destring b28002_001e b28002_004e, replace force
gen broadband_rate_2024 = b28002_004e / b28002_001e
replace broadband_rate_2024 = . if broadband_rate_2024 < 0 | broadband_rate_2024 > 1
keep fips_county broadband_rate_2024
drop if broadband_rate_2024 == .
duplicates drop fips_county, force
sort fips_county
save "$output\ACS_BB_2024.dta", replace
di "ACS Broadband 2024: " _N " counties"

* 5E: MERGE ALL INTO COUNTY PANEL
* BEA + Population: panel merges on fips_county + year
* ACS: cross-section merges on fips_county only
* One-to-one vintage assignment after all merges.

use "$output\County_Panel.dta", clear

* BEA income
merge m:1 fips_county year using "$output\BEA_Clean.dta"
drop if _merge == 2
drop _merge

* Population
merge m:1 fips_county year using "$output\Population_Panel.dta"
drop if _merge == 2
drop _merge

* Education - merge all 15 vintages (2010-2024) as cross-sections
forvalues yr = 2010/2024 {
    merge m:1 fips_county using "$output\ACS_Educ_`yr'.dta"
    drop if _merge == 2
    drop _merge
}

* Assign education one-to-one by panel year
* Years before 2010 get 2010 vintage (earliest available)
gen pct_bachelors = .
replace pct_bachelors = pct_bachelors_2010 if year < 2010
forvalues yr = 2010/2024 {
    replace pct_bachelors = pct_bachelors_`yr' if year == `yr'
}
forvalues yr = 2010/2024 {
    drop pct_bachelors_`yr'
}
label variable pct_bachelors "% adults 25+ bachelor's+ (ACS S1501, one vintage per year)"

* Broadband - merge all 8 vintages (2017-2024) as cross-sections
forvalues yr = 2017/2024 {
    merge m:1 fips_county using "$output\ACS_BB_`yr'.dta"
    drop if _merge == 2
    drop _merge
}

* Assign broadband one-to-one by panel year
* Years before 2017 get 2017 vintage (earliest available)
gen broadband_rate = .
replace broadband_rate = broadband_rate_2017 if year < 2017
forvalues yr = 2017/2024 {
    replace broadband_rate = broadband_rate_`yr' if year == `yr'
}
forvalues yr = 2017/2024 {
    drop broadband_rate_`yr'
}
label variable broadband_rate "HH broadband rate (ACS B28002, one vintage per year)"

* Derived variables
gen branches_pc  = (num_branches / popestimate) * 10000
gen community_pc = (community_br / popestimate) * 10000
gen log_pop      = log(popestimate)
gen log_income   = log(pcpincome)

drop if popestimate == . | popestimate == 0
drop if pcpincome   == . | pcpincome   <= 0

label variable branches_pc   "Total branches per 10,000 population"
label variable community_pc  "Community bank branches per 10,000 population"
label variable log_pop       "Log county population"
label variable log_income    "Log per capita personal income (BEA)"

sort fips_county year
save "$output\County_Panel_Merged.dta", replace
di "Section 5 complete. County_Panel_Merged.dta: " _N " county-year rows"
di "Education : 2010-2024 vintages (C01 for 2010-2014, C02 for 2015-2024)"
di "Broadband : 2017-2024 vintages (one per year)"

/*====================================================================*
   SECTION 5F (originally 3D): BANKING DESERT PROFILE - EDUCATION AND BROADBAND
   Moved here because it reads County_Panel_Merged.dta, which Section 5 creates.
   Compares true banking desert counties against all other counties
   on education (pct_bachelors) and broadband (broadband_rate).
   Uses ACS data from County_Panel_Merged.dta (most recent year per county).
   
   Key question: Do deserted counties have lower education and broadband
   than the rest of the country? If yes, this supports the argument that
   digital substitution is NOT available to these communities.
====================================================================*/

* Get most recent ACS values per county from the merged panel
* (same approach used for maps in Section 7)
use "$output\County_Panel_Merged.dta", clear
bysort fips_county (year): keep if _n == _N
keep fips_county pct_bachelors broadband_rate popestimate pcpincome
duplicates drop fips_county, force
save "$output\County_ACS_Latest.dta", replace
di "County_ACS_Latest.dta: " _N " counties with ACS data"

* Merge ACS data into county comparison dataset
use "$output\County_Comparison.dta", clear

* Convert fips_county to numeric for merge (it may be string in comparison file)
capture confirm string variable fips_county
if !_rc destring fips_county, replace force

merge 1:1 fips_county using "$output\County_ACS_Latest.dta"
drop if _merge == 2
drop _merge

* Define groups for comparison
* Group 1: True banking deserts (had branches 1994, zero 2024, excl CT)
* Group 2: All other counties (non-desert, non-CT)
gen desert_true = (desert == 1 & ct_flag == 0)
gen other       = (desert == 0 & ct_flag == 0)

*  Summary statistics by group 
di ""
di "===== BANKING DESERT vs ALL OTHER COUNTIES ====="
di "True banking deserts (n=" 
count if desert_true == 1
di r(N) ")"
di ""

di "--- Education (% adults 25+ with bachelor degree) ---"
di "  Desert counties:"
quietly summarize pct_bachelors if desert_true == 1
di "    Mean: " %5.1f r(mean) "% | SD: " %5.1f r(sd) " | N=" r(N)
di "  All other counties:"
quietly summarize pct_bachelors if other == 1
di "    Mean: " %5.1f r(mean) "% | SD: " %5.1f r(sd) " | N=" r(N)

di ""
di "--- Broadband (fraction of HH with broadband) ---"
di "  Desert counties:"
quietly summarize broadband_rate if desert_true == 1
di "    Mean: " %5.3f r(mean) " (" %5.1f r(mean)*100 "%) | N=" r(N)
di "  All other counties:"
quietly summarize broadband_rate if other == 1
di "    Mean: " %5.3f r(mean) " (" %5.1f r(mean)*100 "%) | N=" r(N)

di ""
di "--- Per capita income (USD) ---"
di "  Desert counties:"
quietly summarize pcpincome if desert_true == 1
di "    Mean: $" %8.0fc r(mean) " | N=" r(N)
di "  All other counties:"
quietly summarize pcpincome if other == 1
di "    Mean: $" %8.0fc r(mean) " | N=" r(N)

di ""
di "--- Population ---"
di "  Desert counties:"
quietly summarize popestimate if desert_true == 1
di "    Mean: " %8.0fc r(mean) " | N=" r(N)
di "  All other counties:"
quietly summarize popestimate if other == 1
di "    Mean: " %8.0fc r(mean) " | N=" r(N)

*  Export comparison table to Excel 
* Build a county-level table for the Excel workbook
preserve
    keep if desert_true == 1 | other == 1

    * Create group label
    gen Group = "True Banking Desert" if desert_true == 1
    replace Group = "All Other Counties" if other == 1

    * Collapse to group means
    collapse (mean) pct_bachelors broadband_rate pcpincome popestimate ///
             (count) n_counties = fips_county, by(Group)

    * Format broadband as percent
    gen broadband_pct = broadband_rate * 100
    drop broadband_rate

    * Round for readability
    format pct_bachelors  %5.1f
    format broadband_pct  %5.1f
    format pcpincome      %8.0fc
    format popestimate    %10.0fc

    label variable Group          "County Group"
    label variable n_counties     "Number of Counties"
    label variable pct_bachelors  "% Adults 25+ Bachelor Degree (ACS)"
    label variable broadband_pct  "% HH with Broadband (ACS)"
    label variable pcpincome      "Per Capita Income (USD)"
    label variable popestimate    "Mean Population"

    export excel Group n_counties pct_bachelors broadband_pct pcpincome popestimate ///
        using "$output\Analysis_Tables.xlsx",                                        ///
        sheet("Desert_vs_Others") sheetreplace firstrow(varlabels)
    di "Desert vs Others comparison exported to Excel"
restore

*  County-level detail table for all desert counties 
preserve
    keep if desert_true == 1
    keep county_name state branches_1994 pct_bachelors broadband_rate pcpincome popestimate

    gen broadband_pct = broadband_rate * 100
    drop broadband_rate

    format pct_bachelors %5.1f
    format broadband_pct %5.1f
    format pcpincome     %8.0fc
    format popestimate   %10.0fc

    rename county_name   County
    rename state         State
    rename branches_1994 Branches_1994
    rename pct_bachelors Pct_Bachelors
    rename broadband_pct Broadband_Pct
    rename pcpincome     PerCapita_Income
    rename popestimate   Population

    gsort State County

    export excel County State Branches_1994 Pct_Bachelors Broadband_Pct ///
        PerCapita_Income Population                                       ///
        using "$output\Analysis_Tables.xlsx",                             ///
        sheet("Desert_County_Detail") sheetreplace firstrow(varlabels)
    di "Desert county detail exported to Excel"
restore

*  Two-sample t-test: are differences statistically significant? 
di ""
di "===== T-TESTS: DESERT vs OTHER COUNTIES ====="
di ""
di "Education:"
ttest pct_bachelors, by(desert_true)
di ""
di "Broadband:"
ttest broadband_rate, by(desert_true)
di ""
di "Per capita income:"
ttest pcpincome, by(desert_true)

di "Section 3D complete."

/*====================================================================*
   SECTION 6: REGRESSIONS
   Y = num_branches or branches_pc
   X = lag_log_income, lag_log_pop, pct_bachelors, broadband_rate
   Only income and population are lagged (time-varying).
   ACS variables used contemporaneously (5-year averages).
   Three columns: No FE | County FE | Year FE
   Output: Word tables via outreg2
====================================================================*/

use "$output\County_Panel_Merged.dta", clear
duplicates drop fips_county year, force
xtset fips_county year

gen lag_log_income = L.log_income
gen lag_log_pop    = L.log_pop

label variable lag_log_income "Log per capita income, t-1"
label variable lag_log_pop    "Log population, t-1"
label variable pct_bachelors  "% adults 25+ bachelor's degree"
label variable broadband_rate "Broadband HH rate"

mark insample
markout insample lag_log_income lag_log_pop pct_bachelors broadband_rate ///
    num_branches branches_pc
keep if insample == 1
drop insample

di "Regression sample: " _N " county-year observations"
quietly tab fips_county
di "Unique counties: " r(r)

capture which outreg2
if _rc ssc install outreg2

* Table A: Number of branches
regress num_branches lag_log_income pct_bachelors broadband_rate lag_log_pop, robust
estimates store A1_OLS
outreg2 using "$output\Table_NumBranches.doc", replace word ctitle("No FE") label se

xtreg num_branches lag_log_income pct_bachelors broadband_rate lag_log_pop, fe robust
estimates store A2_FE
outreg2 using "$output\Table_NumBranches.doc", append word ctitle("County FE") label se

regress num_branches lag_log_income pct_bachelors broadband_rate lag_log_pop ///
    i.year, robust
estimates store A3_YFE
outreg2 using "$output\Table_NumBranches.doc", append word ctitle("Year FE") label se drop(*.year)

di "Table A saved: Table_NumBranches.doc"

* Table B: Branches per capita
regress branches_pc lag_log_income pct_bachelors broadband_rate lag_log_pop, robust
estimates store B1_OLS
outreg2 using "$output\Table_BranchesPC.doc", replace word ctitle("No FE") label se

xtreg branches_pc lag_log_income pct_bachelors broadband_rate lag_log_pop, fe robust
estimates store B2_FE
outreg2 using "$output\Table_BranchesPC.doc", append word ctitle("County FE") label se

regress branches_pc lag_log_income pct_bachelors broadband_rate lag_log_pop ///
    i.year, robust
estimates store B3_YFE
outreg2 using "$output\Table_BranchesPC.doc", append word ctitle("Year FE") label se drop(*.year)

di "Table B saved: Table_BranchesPC.doc"
di "Section 6 complete."

/*====================================================================*
   SECTION 7: FINANCIAL SOPHISTICATION MAPS
   Use most recent year per county for mapping
====================================================================*/

use "$output\County_Panel_Merged.dta", clear
bysort fips_county (year): keep if _n == _N
keep fips_county pct_bachelors broadband_rate
duplicates drop fips_county, force
tostring fips_county, gen(fips_str) format("%05.0f")
save "$output\County_Soph_CS.dta", replace

* Education map
use "$output\counties_data.dta", clear
rename GEOID fips_str
destring fips_str, gen(fips_num)
drop if fips_num >= 2000  & fips_num < 3000
drop if fips_num >= 15000 & fips_num < 16000
drop if fips_num > 56999
drop fips_num
merge 1:1 fips_str using "$output\County_Soph_CS.dta"
drop if _merge == 2
drop _merge
spmap pct_bachelors using "$output\counties_coor.dta", id(mapid)     ///
    fcolor(Reds)                                                        ///
    clmethod(custom) clbreaks(0 10 20 30 40 50 70)                     ///
    ocolor(white ..) osize(vvthin ..)                                   ///
    title("% Adults 25+ with Bachelor's Degree", size(large) color(navy)) ///
    legend(title("Percent (%)", size(small)) size(small)                ///
           position(4) ring(0) region(lwidth(none) color(none)))        ///
    graphregion(color(white) margin(zero)) plotregion(margin(zero))     ///
    xsize(10) ysize(7)
graph export "$output\Figure5_Map_Education.png", replace width(3600)
di "Education map saved."

* Broadband map
use "$output\counties_data.dta", clear
rename GEOID fips_str
destring fips_str, gen(fips_num)
drop if fips_num >= 2000  & fips_num < 3000
drop if fips_num >= 15000 & fips_num < 16000
drop if fips_num > 56999
drop fips_num
merge 1:1 fips_str using "$output\County_Soph_CS.dta"
drop if _merge == 2
drop _merge
gen broadband_pct = broadband_rate * 100
spmap broadband_pct using "$output\counties_coor.dta", id(mapid)     ///
    fcolor(Greens)                                                      ///
    clmethod(custom) clbreaks(0 50 60 70 80 90 100)                    ///
    ocolor(white ..) osize(vvthin ..)                                   ///
    title("% Households with Broadband Internet", size(large) color(navy)) ///
    legend(title("Percent (%)", size(small)) size(small)                ///
           position(4) ring(0) region(lwidth(none) color(none)))        ///
    graphregion(color(white) margin(zero)) plotregion(margin(zero))     ///
    xsize(10) ysize(7)
graph export "$output\Figure6_Map_Broadband.png", replace width(3600)
di "Broadband map saved."

di "Section 7 complete."

/*====================================================================*
   SECTION 8: EXCEL OUTPUT TABLES
====================================================================*/

* Sheet 1: Annual branch counts
use "$output\YearLevel_Summary.dta", clear
gen community_pct = community_br / total_br * 100
gen regional_pct  = regional_br  / total_br * 100
gen megabank_pct  = mega_br      / total_br * 100
gen savings_pct   = savings_br   / total_br * 100
format community_pct regional_pct megabank_pct savings_pct %5.1f
export excel year total_br community_br regional_br mega_br savings_br ///
    community_pct regional_pct megabank_pct savings_pct                ///
    using "$output\Analysis_Tables.xlsx",                               ///
    sheet("Summary_Stats") sheetreplace firstrow(varlabels)
di "Sheet 1 saved"

* Sheet 2: County comparison
use "$output\County_Comparison.dta", clear
gsort state county_name
rename county_name          County
rename state                State
rename branches_1994        Branches_1994
rename branches_latest_fill Branches_2024
rename branch_change        Branch_Change
rename pct_change           Pct_Change
rename desert               Banking_Desert
rename ct_flag              CT_Artifact
format Pct_Change %6.1f
export excel County State Branches_1994 Branches_2024                 ///
    Branch_Change Pct_Change Banking_Desert CT_Artifact               ///
    using "$output\Analysis_Tables.xlsx",                              ///
    sheet("County_Change") sheetreplace firstrow(varlabels)
di "Sheet 2 saved"

* Sheet 3: Banking deserts
use "$output\County_Comparison.dta", clear
keep if desert == 1
gsort ct_flag state county_name
gen Notes = cond(ct_flag == 0, "True banking desert", ///
    "CT reorganization - not a true desert")
rename county_name   County
rename state         State
rename branches_1994 Branches_in_1994
export excel County State Branches_in_1994 Notes                       ///
    using "$output\Analysis_Tables.xlsx",                               ///
    sheet("Banking_Deserts") sheetreplace firstrow(varlabels)
di "Sheet 3 saved"

* Sheet 4: Deserts by state
import delimited "$output\Table_DesertsByState.csv", varnames(1) clear
export excel using "$output\Analysis_Tables.xlsx",                     ///
    sheet("Deserts_by_State") sheetreplace firstrow(varlabels)
di "Sheet 4 saved"

* Sheet 5: Top 10 losers
use "$output\County_Comparison.dta", clear
drop if state == "CT"
keep if branches_1994 > 0 & branches_1994 != .
gsort branch_change
keep in 1/10
rename county_name          County
rename state                State
rename branches_1994        Branches_1994
rename branches_latest_fill Branches_2024
rename branch_change        Branch_Change
rename pct_change           Pct_Change
format Pct_Change %6.1f
export excel County State Branches_1994 Branches_2024 Branch_Change Pct_Change ///
    using "$output\Analysis_Tables.xlsx",                                        ///
    sheet("Top10_Losers") sheetreplace firstrow(varlabels)
di "Sheet 5 saved"

* Sheet 6: Top 10 gainers
use "$output\County_Comparison.dta", clear
drop if state == "CT"
keep if branches_1994 > 0 & branches_1994 != .
gsort -branch_change
keep in 1/10
rename county_name          County
rename state                State
rename branches_1994        Branches_1994
rename branches_latest_fill Branches_2024
rename branch_change        Branch_Change
rename pct_change           Pct_Change
format Pct_Change %6.1f
export excel County State Branches_1994 Branches_2024 Branch_Change Pct_Change ///
    using "$output\Analysis_Tables.xlsx",                                        ///
    sheet("Top10_Gainers") sheetreplace firstrow(varlabels)
di "Sheet 6 saved"

* Sheet 7: Region summary
import delimited "$output\Table_RegionSummary.csv", varnames(1) clear
export excel using "$output\Analysis_Tables.xlsx",                     ///
    sheet("Region_Summary") sheetreplace firstrow(varlabels)
di "Sheet 7 saved"

* Sheet 8: Branch by type per year
use "$output\YearLevel_Summary.dta", clear
export excel year total_br community_br regional_br mega_br savings_br ///
    using "$output\Analysis_Tables.xlsx",                               ///
    sheet("Branch_by_Type_Year") sheetreplace firstrow(varlabels)
di "Sheet 8 saved"

di "ALL EXCEL SHEETS SAVED: Analysis_Tables.xlsx"

/*====================================================================*
   SECTION 9: FINISH
====================================================================*/

di ""
di "====================================================="
di "ANALYSIS COMPLETE: " c(current_date) " " c(current_time)
di "Outputs saved to: $output"
di ""
di "FIGURES:"
di "  Figure1a_AllTypes_Trend.png"
di "  Figure1b_Community_Trend.png"
di "  Figure2_BankType_Compare.png"
di "  Figure3_RegionShare.png"
di "  Figure4a_Map_1994.png"
di "  Figure4b_Map_2024.png"
di "  Figure5_Map_Education.png"
di "  Figure6_Map_Broadband.png"
di ""
di "REGRESSION TABLES:"
di "  Table_NumBranches.doc"
di "  Table_BranchesPC.doc"
di ""
di "EXCEL: Analysis_Tables.xlsx (8 sheets)"
di "====================================================="

log close
