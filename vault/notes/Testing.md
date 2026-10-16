---
title: Testing
type: note
tags: [workflow, testing]
summary: The automated test suites.
created: 2026-10-17
updated: 2026-10-17
status: growing
related: ["[[Workflow MOC]]"]
---

# Testing

| Part | Tool | Where |
|---|---|---|
| [[Flutter app]] | `flutter test` | `test/` (OCR parsing and validation) |
| [[Backend API]] | Jest | `backend/src/**/*.test.js` |
| [[OCR grid service]] | pytest | `ocr_service/tests/` (slow: about 8 minutes) |

Register photo regression: sample photos in `attachments/` are scored for row alignment after each grid change. They stay local ([[Data privacy rules]]).
