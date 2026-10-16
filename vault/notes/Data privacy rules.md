---
title: Data privacy rules
type: note
tags: [privacy]
summary: What must never leave the machine or enter git.
created: 2026-10-17
updated: 2026-10-17
status: growing
related: ["[[Home]]"]
---

# Data privacy rules

The registers hold personal records, many of them of minors.

- Register photos (`attachments/`), scans, OCR dumps (`build/ocr_debug/`) and OCR fixtures stay local. They are gitignored and excluded from graphify.
- Never copy names, dates, parents or sponsors from a register into notes, issues or commits. Use the photo's file name.
- Don't put register photos in this vault's `assets/` folder.
- Secrets (`.env`, `dart_define*.json`, service keys) never go in notes.

Related: [[Code map (graphify)]], [[OCR MOC]]
