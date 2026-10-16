---
title: System architecture
type: note
tags: [architecture]
summary: Three-layer overview of POMS.
created: 2026-10-17
updated: 2026-10-17
status: growing
related: ["[[Architecture MOC]]"]
---

# System architecture

| Layer | What | Where |
|---|---|---|
| Presentation | [[Flutter app]] (Riverpod, GoRouter) | Android, iOS, desktop, web (Firebase Hosting) |
| Service | [[Backend API]] (Node/Express) | Railway |
| Service | [[Cloud Functions]] (TypeScript) | Firebase |
| Service | [[OCR grid service]] (FastAPI + OpenCV) | Railway |
| Data | Firebase Auth, Cloud Firestore, Cloud Messaging | Firebase project `holyparish` |

## Register scan, end to end
1. Staff photograph a two-page register spread in the app.
2. The app sends it to the [[Backend API]].
3. The backend asks the [[OCR grid service]] for the page split and the ruled grid.
4. The backend sends each page to OCR.space (Engine 2) for handwriting.
5. The backend assigns each word to a row and column ([[Baptismal register OCR]], [[Marriage register OCR]]).
6. The rows come back as an OCR job; staff review and correct them, then Save & Lock.

On Android/iOS, ML Kit reads certificates on the device; web and desktop fall back to Tesseract.
