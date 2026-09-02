# Baptismal register: capture guidance

## Problem

Some register spreads cannot be read (faded/curved rules near the spine, a page
out of frame, uneven lighting), and the pipeline correctly refuses them rather
than risk mis-filing records of minors. But the app gives the user little help
turning a bad photo into a good one:

- The scan page's upload step is a bare "Upload or capture a register page" with
  no guidance on how to photograph the register.
- On refusal, the backend collapses every CV reason into a single generic
  `SPREAD_UNREADABLE` message ("retake with the book flat, both pages in frame,
  even lighting"), discarding the CV service's specific, already-staff-safe
  reason (which page, and whether rows/columns/grid/pitch failed).

The register is web/desktop file-upload (no live camera), so the lever is
guidance around the upload and after a refusal — not a camera overlay.

This work does **not** change detection or any safety gate. It helps the user
capture a readable photo; genuinely unreadable spreads still refuse.

## Approach

Two independent pieces, shipped in order:

- **Piece A — upfront how-to-photograph guide** (Flutter only): a concise
  checklist shown at the upload step and retained on the preview/retry step.
- **Piece B — specific refusal feedback** (CV → backend → Flutter): the CV
  service emits a machine-readable `reason` + `side` with each refusal; the
  backend maps them to curated capture guidance returned as a `detail` field;
  the app shows it under the existing message.

## Design

### Piece A — Upfront capture guide

`lib/screens/admin/pages/baptismal_ocr_scan_page.dart`. Add a small stateless
widget (a checklist card) and render it in `_pickStep` (above "Choose image")
and in `_previewStep` (so it is present exactly when the user is deciding how to
retake). Content, four items with icons:

- Lay the book **flat and press the spine down** — the most common cause of an
  unreadable page.
- Fit **both pages fully** in the frame, straight-on.
- **Even lighting** — no glare or shadow across the page.
- **Fill the frame** with the register; don't shoot from far away.

No backend change, no new dependency, no image asset required (icon + text
list). The card is collapsible only if it crowds the layout; default expanded.

### Piece B — Specific refusal feedback

**CV service.** Extend `OcrError` (`ocr_service/app/errors.py`) with optional
`reason: str | None` and `side: str | None`. `reason` is drawn from a small
fixed set; `side` is `"left" | "right" | "both"`. The exception handler
(`app/main.py`) adds them to the JSON when present:
`{"success": false, "code", "message", "reason", "side"}`. They carry no cell
text — only which structural check failed and on which page.

`_refuse` in `ocr_service/app/pipeline/table.py` gains `reason`/`side`
parameters, and each call site passes them:

| Situation (existing `_refuse` call) | `reason` | `side` |
| --- | --- | --- |
| a page's grid could not be found at all | `grid_not_found` | that page |
| `_check_template_fit`: column count / extent / corroboration | `columns_unmatched` | that page |
| the two pages disagree on column count | `columns_unmatched` | `both` |
| the two pages disagree on row count | `rows_disagree` | `both` |
| row spacing could not be measured / pitch disagreement | `pitch_mismatch` | `both` |

**Backend.** `cv_grid_client.js` captures `body.reason` and `body.side` on a
refusal and carries them on the `CvGridError` (alongside the existing code).
`baptismal_ocr_firestore.js` maps `(reason, side)` to a curated,
capture-oriented `detail` string (backend owns the wording), returned in the
`SPREAD_UNREADABLE` response body next to the existing `message`. Mapping (side
name interpolated: "left"/"right"/"the" for both):

- `grid_not_found` → "The {side} page's ruled lines couldn't be found — lay the
  book flat, fill the frame with the page, and retake."
- `columns_unmatched` → "The {side} page's column lines were too faint or
  curved to read — press the book flat near the spine and retake."
- `rows_disagree` / `pitch_mismatch` → "The two pages didn't line up — flatten
  the book so both pages are in the same plane, keep both fully in frame, and
  retake."
- unknown/missing reason → no `detail` (fall back to the generic message alone).

**Flutter.** `BaptismalOcrFailure` (`lib/services/baptismal_ocr_service.dart`)
gains an optional `detail` field, populated from `decoded['detail']`. The scan
page `_errorBanner` renders `detail` under `message` when present. Recovery
mapping is unchanged (`SPREAD_UNREADABLE` → `differentImage`).

## Data flow (Piece B)

```
CV _refuse(reason, side) -> OcrError(reason, side)
  -> /v1/grid 4xx JSON {code, message, reason, side}
  -> cv_grid_client CvGridError{code:CV_REFUSED, reason, side}
  -> route maps (reason, side) -> detail; responds {code:SPREAD_UNREADABLE, message, detail}
  -> Flutter BaptismalOcrFailure{message, detail} -> error banner
```

## Privacy

`reason` and `side` are structural (which check failed, which page). No counts,
no cell text, no file paths cross any boundary. The CV service log stays
"code only" as today.

## Testing

- **Piece A:** widget test that the checklist card renders on the pick step and
  on the preview step (by key/text).
- **Piece B — CV:** unit tests that each `_refuse` path raises `OcrError` with
  the expected `reason`/`side`; an endpoint test that a refusal response
  includes `reason`/`side`.
- **Piece B — backend:** a `CV_REFUSED` carrying each `(reason, side)` yields
  the mapped `detail`; an unknown reason yields no `detail`; the no-leak
  property (no cell text) still holds.
- **Piece B — Flutter:** `BaptismalOcrService` parses `detail`; the error banner
  shows it.
- Full suites green: Python `ocr_service/tests`, backend Jest, Flutter `test/`.
  Detection/geometry code and its tests are untouched.

## Out of scope

- Any change to grid/row/column detection or the safety gates (this is guidance
  only).
- A live camera overlay or on-device image quality analysis (the app is
  file-upload; not warranted).
- Forwarding the CV service's raw human message (backend owns the copy; CV emits
  only codes).
