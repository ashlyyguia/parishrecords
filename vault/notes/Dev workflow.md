---
title: Dev workflow
type: note
tags: [workflow]
summary: Branches, commits and running locally.
created: 2026-10-17
updated: 2026-10-17
status: growing
related: ["[[Workflow MOC]]"]
---

# Dev workflow

- Work on `development`, never directly on `main`. Feature branches as needed.
- Commit every piece of work.
- To release: merge `main` into `development`, then `development` into `main`, then push. Pushing `main` redeploys Railway.
- Files are CRLF on Windows.

Running locally:
- App: `flutter run` with `dart_define.local.json`
- Backend: `backend/` with `backend/.env`
- OCR service: uvicorn on `127.0.0.1:8000`; restart it after pipeline changes and check `/health` for the version

Related: [[Testing]], [[Deployment]]
