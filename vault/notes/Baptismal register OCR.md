---
title: Baptismal register OCR
type: note
tags: [ocr, baptismal]
summary: How a baptismal spread becomes 24 rows.
created: 2026-10-17
updated: 2026-10-17
status: growing
related: ["[[OCR MOC]]"]
---

# Baptismal register OCR

Layout: 24 entries per spread. Left page: No., name of child, place and date of birth, L/ILL, parents. Right page: residence, date of baptism, minister, sponsors, observations.

Steps after the [[OCR grid service]] returns the grid:
1. OCR.space reads each page.
2. `baptismal_grid_assign.js` groups words into handwritten lines, then a dynamic-programming pass assigns lines to rows in order. Costs: distance 3, overfull 1, empty 0.4. Caps: minister 1 line, place and birth date 3, others 2. A year ends an entry in the birth-date and baptism-date columns.
3. Left and right pages are aligned by height; the header row is dropped by its label words.

Known issues:
- Some left pages are still one row off when the grid starts in the title (e.g. 3984L, 3988L).
- OCR.space sometimes merges lines; Cyrillic look-alike letters.
- The "In certification thereof" footer can leak into the last row.

Samples: `attachments/baptismal` (local only).

Related: [[OCR fix log]], [[Marriage register OCR]]
