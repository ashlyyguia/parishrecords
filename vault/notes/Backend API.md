---
title: Backend API
type: note
tags: [architecture, backend]
summary: Node/Express backend on Railway.
created: 2026-10-17
updated: 2026-10-17
status: growing
related: ["[[Architecture MOC]]"]
---

# Backend API

Folder `backend/src/`:
- `routes/`: one file per area (admin, users, households, requests, donations, finance, records, OCR jobs, baptismal/marriage OCR, notifications, ...)
- `services/`: register OCR (`baptismal_*`, `marriage_*`, `cv_grid_client.js`, `ocrspace_service.js`, `heic_to_jpeg.js`), `email.js` (SMTP with EmailJS fallback for the welcome email)
- `middleware/auth.js`: Firebase token check

Config lives in `backend/.env` (gitignored). Locally, the OCR service URL points at `http://127.0.0.1:8000`; on Railway it points at the Railway OCR service.

Debug helper: `node backend/scripts/dump_grid_words.js <photo> <out.json> [register]` writes grid + word boxes to `build/ocr_debug/` (gitignored, see [[Data privacy rules]]).

Related: [[OCR grid service]], [[Baptismal register OCR]], [[Deployment]]
