---
title: Deployment
type: note
tags: [workflow, deployment]
summary: Where each part runs and how to ship it.
created: 2026-10-17
updated: 2026-10-17
status: growing
related: ["[[Workflow MOC]]"]
---

# Deployment

| Part | Host | How |
|---|---|---|
| Web app | Firebase Hosting | `scripts/deploy-web.ps1` |
| Android APK | file | `scripts/build-apk.ps1` |
| [[Backend API]] | Railway | push to `main` |
| [[OCR grid service]] | Railway (Singapore) | push to `main`; custom start command; `RAILPACK_PYTHON_VERSION=3.11` |

- The OCR service and backend share an `OCR_SERVICE_KEY`; it lives in Railway variables and `.env`, never in notes.
- Ask before deploying.

Related: [[Dev workflow]]
