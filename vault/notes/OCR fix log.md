---
title: OCR fix log
type: note
tags: [ocr, log]
summary: History of OCR problems and fixes.
created: 2026-10-17
updated: 2026-10-17
status: growing
related: ["[[OCR MOC]]"]
---

# OCR fix log

Newest first. One entry per fix: symptom, cause, fix, commit. Use [[Fix log entry]] as the template.

## 2026-10-17: right page one row late (IMG_3949)
- **Symptom:** header labels (RESIDENTS OF, DATE OF BAPTISM, ...) in row 1; every right-page field one row late.
- **Cause:** the row grid was slightly too tall; anchoring it to the bottom border pushed entry 1 onto the header band.
- **Fix:** right page only, refit the grid from the bottom border through the detected row rules so entry 1 starts below the header. Service 2.3.0.
- **Commit:** `30a946bd`

## 2026-10: handwriting on a ruled line went to the wrong entry (IMG_3120)
- **Fix:** group words into handwritten lines, then assign lines to rows with a DP (costs and caps in [[Baptismal register OCR]]).
- **Commit:** `0c22e570`

## 2026-10: grid rows started too high
- **Fix:** anchor the row grid to the table's bottom border.
- **Commit:** `40c6baed`

## 2026-10: rows drifted across the page
- **Cause:** a straight comb can't follow photo perspective.
- **Fix:** quadratic refinement of the row grid. Service 2.2.0.
- **Commit:** `9053f31f`

## 2026-10: 45 rows instead of 24 locally
- **Cause:** `backend/.env` still pointed at the old VPS OCR service.
- **Fix:** point it at Railway, or at `127.0.0.1:8000` when running the service locally.
