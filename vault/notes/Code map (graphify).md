---
title: Code map (graphify)
type: note
tags: [tools, architecture]
summary: Auto-generated code map and how to rebuild it.
created: 2026-10-17
updated: 2026-10-17
status: growing
related: ["[[Architecture MOC]]"]
---

# Code map (graphify)

graphify builds a map of the code locally (code only, no AI calls).

- Rebuild: `.\scripts\graphify.ps1`
- Browser view: `graphify-out/graph.html`
- Summary: `graphify-out/GRAPH_REPORT.md`
- Obsidian view: a separate vault at `graphify-out/obsidian` (thousands of auto-generated notes, kept out of this vault so its graph stays readable)

What it may read is limited by `.gitignore` and `.graphifyignore` ([[Data privacy rules]]). The output is gitignored.
