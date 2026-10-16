---
title: Flutter app
type: note
tags: [architecture, flutter]
summary: The Flutter client: structure and key folders.
created: 2026-10-17
updated: 2026-10-17
status: growing
related: ["[[Architecture MOC]]"]
---

# Flutter app

Folder `lib/`:
- `screens/`: admin, dashboard, finance, landing, login, notifications, ocr, profile, records, splash, staff, user
- `providers/`: Riverpod state. User-scoped providers watch `currentUidProvider` so they refresh on login/logout.
- `services/`: data access and OCR clients (`baptismal_ocr_service.dart`, `marriage_ocr_service.dart`, `ocr_debug_log.dart`)
- `widgets/`, `models/`, `utils/`, `config/`, `app/`

Notes:
- Config comes from `dart_define.json` / `dart_define.local.json` (local runs point at the local backend).
- In debug builds, register scan results are printed to the console (`logOcrScanResult`).
- Certificates are generated from the parish template with logos in the header.

Related: [[Backend API]], [[Testing]]
