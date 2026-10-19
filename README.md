# What Each Data Repair Step Is Worth in Next-Hour Traffic Forecasting

Code, SQL, results and paper source for the study *"What Each Data Repair Step Is Worth in Next-Hour Traffic Forecasting on the Istanbul Open Data and What Happens on Holidays"* (ICIIT 2027 submission).

**Authors:** Quang Tran, An Truong, Loc Truong, Thu Le — FPT University, Ho Chi Minh City, Vietnam

## Overview

Most traffic forecasting papers report one error number and say little about how much of it comes from data preparation. This project measures that on the hourly traffic density open data of Istanbul (36 monthly files, 2022–2024, 58.4 million records), restricted to the 150 busiest road cells of 2022.

- **Task:** forecast the vehicle count of a cell in the next hour.
- **Models:** Ridge, Extra Trees, LightGBM, MLP, against persistence and three simple baselines.
- **Evaluation:** eight quarterly test folds (2023-Q1 … 2024-Q4) with an expanding training window; MAE and MASE.
- **Repair ladder (R0–R5):** raw records → one row per cell-hour → complete hourly grid → outage/faulty hours removed → calendar flags → holiday-aware weekly lag.
- **Weekly lag variants (L0–L4):** how to build the "same hour last week" feature around public holidays.

### Main results

| Finding | Value |
|---|---|
| Best mean MAE (LightGBM) | 37.9 vehicles per cell-hour, 43.7% below persistence (68.1) |
| LightGBM vs MLP vs Extra Trees | 37.9 / 38.0 / 39.9 — gaps smaller than the quarter-to-quarter SD |
| All repair steps together | mean MAE of four models 46.1 → 40.8 |
| Contribution of the complete hourly grid (R2) | 4.22 of the 5.3 vehicles gained |
| Error peak after a holiday (plain weekly lag) | 66.8 on day +7 vs 38.5 on the holiday itself |
| Week-after-holiday MAE, plain lag → nearest ordinary week | 54.2 → 41.8 |

## Repository structure

```
.
├── Source Code/
│   ├── Notebook_A_v2_IstanbulTraffic_2022_2024.ipynb   # data download, cleaning, calendar, SQL, RQ1
│   ├── Notebook_B_v2_IstanbulTraffic_2022_2024.ipynb   # 8 quarterly folds, 4 models, RQ2 and RQ3
│   └── requirements.txt
├── sql/
│   └── queries.sql                  # SQL queries (DuckDB) written by Notebook A
├── data/
│   ├── calendar_2022_2025.csv       # hand-built holiday / event calendar (needed by Notebook A)
│   ├── cells_selected.csv           # the 150 selected cells
│   ├── dataset_inventory.csv        # inventory of the 36 monthly files
│   ├── processed/manifest.json      # hashes checked by Notebook B
│   ├── raw/                         # NOT in Git: monthly CSV files from the IBB portal
│   └── interim/                     # NOT in Git: rebuilt by Notebook A
├── report/                          # every table (CSV) and figure (PNG) used in the paper
└── ICIIT2027_latex/                 # paper source (ACM sigconf): main.tex, references.bib, figures
```

Large files are excluded by `.gitignore` (raw data ≈ 5 GB, parquet caches, model caches, virtual environment).

## Getting started

### 1. Environment

Tested with Python 3.11.

```bash
python -m venv .venv
# Windows
.venv\Scripts\activate
# macOS / Linux
source .venv/bin/activate

pip install -r "Source Code/requirements.txt"
```

Optional: `pip install contextily` to draw the web base map in the cell map figure.

### 2. Data

The data are **not** stored in this repository. Source: Istanbul Metropolitan Municipality (IBB) open data portal, *Hourly Traffic Density Data Set*:
<https://data.ibb.gov.tr/en/dataset/hourly-traffic-density-data-set>

Notebook A downloads the 36 monthly files (2022–2024) automatically through the portal API (`AUTO_DOWNLOAD = True`). If the download fails, download the monthly files by hand and put them (CSV or ZIP) in `data/raw/`; the notebook picks them up from there. Check the license terms on the dataset page before redistributing the data.

### 3. Run order

Run the notebooks from start to end, in this order:

1. **Notebook A** — downloads and checks the 36 files, selects the 150 cells, builds the complete hourly grid and the calendar, runs the SQL queries and writes the RQ1 tables and figures. Output: `data/processed/*.parquet`, `data/processed/manifest.json`, `sql/queries.sql`, `report/`.
2. **Notebook B** — checks the hand-over from Notebook A (`manifest.json`), runs the eight quarterly folds for all configurations and writes the RQ2/RQ3 tables and figures to `report/`.

The notebooks can be opened from `Source Code/`; they switch the working folder to the project root automatically.

**Quick test run:** set `FAST = True` in the configuration cell of Notebook B (one seed, smaller training sample and models). Use `FAST = False` for the results reported in the paper.

Each model fit uses 150,000 sampled training rows (`TRAIN_CAP`), a limit chosen for a 16 GB laptop.

## Where the paper's tables and figures come from

| Paper | File in `report/` |
|---|---|
| Figure 1 (pipeline) | `fig_pipeline.png` |
| Figure 2 (map of cells) | `fig_map_cells.png` |
| Figure 3a / 3b | `fig_rq1_heatmap_hour_dow.png` / `fig_rq1_hourly_profile.png` |
| Figure 4 (models vs baselines) | `fig_rq2_models.png` |
| Table 1 (overall error) | `table_rq2.csv` |
| Table 2 (per quarter) | `table_rq2_by_fold.csv` |
| Table 3 (repair ladder) | `table_rq3_repair_ladder.csv` |
| Table 4 (event study) | computed from `table_rq3_event_study.csv` |
| Table 5 (weekly lag variants by day group) | computed from `table_rq3_weekly_lag_variants.csv` |
| Table 6 (feature-group shuffle) | `table_rq3_impact_4models.csv` |
| Wilcoxon tests | `table_rq3_wilcoxon.csv` |

## Paper

The LaTeX source is in `ICIIT2027_latex/` (ACM `acmart`, `sigconf`). Upload the folder to Overleaf or compile locally with `pdflatex` → `bibtex` → `pdflatex` ×2.

## Acknowledgments

Data: Istanbul Metropolitan Municipality open data portal. Claude (Anthropic) was used to assist with analysis code and language editing; all code, numbers and text were checked by the authors.
