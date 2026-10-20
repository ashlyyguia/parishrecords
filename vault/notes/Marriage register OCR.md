---
title: Marriage register OCR
type: note
tags: [ocr, marriage]
summary: Marriage register scanning: current state and next steps.
created: 2026-10-17
updated: 2026-10-17
status: growing
related: ["[[OCR MOC]]"]
---

# Marriage register OCR

Status: **improved 2026-10-19** (grid service 2.4.0 + line-based assignment, see [[OCR fix log]]). Still rough: OCR misreads, parents' order inside a party, occasional split licence numbers.

Code:
- Backend: `services/marriage_grid_assign.js`, `services/marriage_register_layout.js`, `routes/marriage_ocr_firestore.js`
- App: `lib/services/marriage_ocr_service.dart`

What carries over from baptismal: the [[OCR grid service]] fixes (perspective, bottom anchoring, header check) apply to marriage pages too.

Marriage columns now have their own line caps (4 per entry in the paired columns, 3 for the date of marriage, 1 for the licence) in `marriage_grid_assign.js`.

Samples: 7 marriage photos in `attachments/marriage` (`IMG_20260915_*.jpg`). `IMG_3123.jpeg` in that folder is a **baptismal** page, and the `IMG_3936–3990.HEIC` files are copies of the baptismal photos.

To start a session: bring one marriage photo and its console result.

Related: [[Baptismal register OCR]], [[OCR fix log]]
