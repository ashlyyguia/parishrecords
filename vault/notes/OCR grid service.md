---
title: OCR grid service
type: note
tags: [ocr, architecture]
summary: Python FastAPI + OpenCV service that finds the register grid.
created: 2026-10-17
updated: 2026-10-17
status: growing
related: ["[[OCR MOC]]"]
---

# OCR grid service

Folder `ocr_service/` (Python, FastAPI, OpenCV). It does not read text; it finds where the text is.

Pipeline (`app/pipeline/`):
1. `orientation.py`, `inversion.py`: fix rotation and inverted images
2. `spread.py`: split the two-page spread into left and right pages
3. `rectify.py`: straighten each page
4. `table.py`: detect the column rules and fit the declared row grid
5. `column_template.py`: map columns to register fields

Row grid in `table.py` (the hard part):
- `_fit_declared_row_grid`: lines up a comb of rows with the strongest row rules
- `_refine_declared_rows`: bends it to follow photo perspective (quadratic fit)
- `_anchor_declared_rows_to_table`: slides it so the last row meets the table's bottom border
- `_keep_entry_one_below_header`: right page only; keeps entry 1 below the column header

`SERVICE_VERSION` in `app/main.py` is bumped on every pipeline change; `/health` reports it.

Hosting: Railway (Singapore region, Python 3.11 via `RAILPACK_PYTHON_VERSION`, config in `ocr_service/railway.json`). Locally: uvicorn on `127.0.0.1:8000`.

Related: [[OCR fix log]], [[Baptismal register OCR]]
