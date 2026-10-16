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

Status: **next to work on**.

Code:
- Backend: `services/marriage_grid_assign.js`, `services/marriage_register_layout.js`, `routes/marriage_ocr_firestore.js`
- App: `lib/services/marriage_ocr_service.dart`

What carries over from baptismal: the [[OCR grid service]] fixes (perspective, bottom anchoring, header check) apply to marriage pages too.

What doesn't: the line-to-row assignment was tuned for the baptismal columns. Marriage columns need their own caps and rules.

Samples: 8 photos in `attachments/marriage` (`IMG_3123.jpeg` and 7 `IMG_20260915_*.jpg`). The `IMG_3936–3990.HEIC` files in that folder are copies of baptismal photos, not marriage.

To start a session: bring one marriage photo and its console result.

Related: [[Baptismal register OCR]], [[OCR fix log]]
