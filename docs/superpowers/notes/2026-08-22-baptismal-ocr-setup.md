# Baptismal OCR — setup and verification

## Enabling Google Cloud Vision

1. In the Google Cloud console, open the project that owns the Firebase
   service account (Firebase console → Project settings → Service accounts
   will tell you which GCP project that is) and enable the **Cloud Vision
   API** (APIs & Services → Library → search "Cloud Vision API" → Enable).
2. Credentials — pick one:
   - **Reuse the Firebase service account** (simplest, no new key to manage):
     do nothing extra. `backend/src/services/baptismal_ocr_service.js`
     (`resolveVisionCredentials`) falls back to `FIREBASE_SERVICE_ACCOUNT_JSON`
     when `GOOGLE_CLOUD_VISION_CREDENTIALS_JSON` is not set, and that account
     already lives in the same GCP project, so it only needs the API enabled
     as in step 1.
   - **Dedicated service account** (tighter scoping): this codebase calls the
     classic Cloud Vision API (`vision.googleapis.com`) via `@google-cloud/vision`
     — do **not** grant a "Vision AI" role (`roles/visionai.*`); those belong
     to the separate Vision AI / Vertex AI Vision product and do not apply
     here. For the classic Vision API, what actually matters is (a) the API
     is enabled on the project (step 1) and (b) the service account has a
     role that includes the `serviceusage.services.use` permission, e.g.
     `roles/serviceusage.serviceUsageConsumer`, or a broader role such as
     Editor that already includes it. We have not pinned down whether a
     narrower Vision-specific predefined role exists for this API — if you
     find the IAM role picker doesn't have anything more specific, granting
     `roles/serviceusage.serviceUsageConsumer` (IAM & Admin → Service Accounts
     → Create service account → grant that role → Keys → Add key → JSON) is
     the documented-safe choice. Collapse the downloaded key file to a single
     line (e.g. `jq -c . key.json`) and set it as
     `GOOGLE_CLOUD_VISION_CREDENTIALS_JSON`.
     **If you just want it working with the least ceremony, use the "reuse
     the Firebase service account" option above instead** — it already has
     project access, so this whole IAM-role question doesn't come up.
3. Where to set the env var:
   - **Locally**: add the chosen variable (`GOOGLE_CLOUD_VISION_CREDENTIALS_JSON`
     or `FIREBASE_SERVICE_ACCOUNT_JSON`) to `backend/.env`, single-line JSON,
     matching the existing `FIREBASE_SERVICE_ACCOUNT_JSON` pattern already in
     that file.
   - **Render**: Dashboard → the backend web service → Environment → add the
     same key/value, then trigger a redeploy (env var changes don't hot-reload).
4. Restart the backend after any credentials change (`npm run dev` locally
   picks up `.env` on start; Render redeploys automatically when you save the
   env var).
5. **How a misconfiguration presents**: if neither env var is set, or the
   JSON doesn't parse, or Vision rejects the credentials (permission denied /
   unauthenticated), the backend surfaces error code `VISION_AUTH`
   (`backend/src/services/baptismal_ocr_service.js`) and the Flutter UI shows
   "OCR is not configured on the server." Seeing that message in the UI means
   check the env var first, not the image.

## Recording test fixtures

Layout tests run against synthetic fixtures by default. To pin them to real
OCR output, run against the real API with credentials set as above:

```bash
cd backend && npm run record:vision-fixtures
```

This writes `backend/test/fixtures/vision-img_3120.json`,
`vision-img_3121.json`, and `vision-img_3122.json` from the three sample
images in `attachments/` (a bound Baptismal Register spread photographed at
90°, 180°, and 180° rotation respectively). Each fixture is the normalized
word list (`{ words }`), not the raw Vision payload — small and stable across
Vision API/library version bumps.

**Do NOT commit the resulting JSON files.** They are a full OCR
transcription of three real register spreads — real children's names, birth
and baptism dates, parents, sponsors and residences. `backend/test/fixtures/`
is listed in `.gitignore` specifically to keep this output out of version
control; leave it there. Keep the recorded fixtures local only, and treat
them with the same care as the source images in `attachments/` (also
gitignored).

**Note for whoever runs this**: `backend/scripts/record_vision_fixture.js`
cannot be executed in the development/CI environment used to build this task
— there are no Vision credentials available there. The script has only been
verified for its no-credentials guard path (exits 1 with a clear message, no
stack trace, no network call); actually recording fixture content is a
follow-up for whoever holds the GCP key.

## Manual verification checklist

Several parts of this feature genuinely cannot be exercised by the automated
suites (156 backend / 144 Flutter tests, both green) and must be checked by
hand before shipping. Use the three real sample images in `attachments/`:
`IMG_3120.jpeg` (rotated 90°), `IMG_3121.jpeg` (rotated 180°), and
`IMG_3122.jpeg` (rotated 180°).

### Field-to-column accuracy
- [ ] On all three sample images, fields land in the correct columns; names
      are not mixed with dates, and dates are not mixed with ministers.
- [ ] The rotated pages (all three samples) produce the same rows, in the
      same order, as an upright photo of the same spread would.

### Known limitation: `parents` and `sponsors` are not sub-column-split
The printed register has two physical sub-columns under `NAME OF PARENTS`
(father, then mother) and under `SPONSORS`, but `assignCells` in
`backend/src/services/baptismal_register_layout.js` calibrates and reads each
of those as a SINGLE combined band -- there is no sub-column split anywhere
in the pipeline. Both names land in one field as a plain space-joined blob
(e.g. "JUAN DELA CRUZ MARIA SANTOS"), with no `/` separator and no way to
tell programmatically where the father's name ends and the mother's begins.
- [ ] Confirm this by hand on all three sample images: the `parents` and
      `sponsors` cells contain both names run together, not split.
- [ ] A reviewer must manually re-type these two fields as
      "Father / Mother" (matching `ManualRegisterNotes._parentsValue`'s
      expected `"father / mother"` format) before saving, every time.
- [ ] Follow-up (not yet implemented): teach `assignCells` to track each
      sub-column's own x-range so it can split `parents`/`sponsors`
      correctly, instead of guessing via an x-midpoint split (which risks
      mis-assigning a name to the wrong parent -- worse than the current
      honest, visibly-unsplit blob).

### Review-state tinting and editing
- [ ] Low-confidence cells are tinted amber.
- [ ] Fill-down-inherited cells (e.g. a minister/date carried down from the
      row above) are tinted blue.
- [ ] Cells with blocking issues (e.g. a cleared required field) are tinted
      red.
- [ ] Editing any flagged cell updates the value and clears that cell's
      review flag/tint.
- [ ] Required fields are visibly marked as such before Save is pressed, not
      only after a failed save attempt.
- [ ] Clearing a required name blocks Save and names the offending row.

### OCR error paths (each end to end, through the real UI)
- [ ] Uploading an unsupported file type (e.g. a PDF) is rejected with a
      clear, specific message — not a generic failure.
- [ ] Uploading an oversized image is rejected with a clear message (image
      preprocessing caps decode at 40 MP; confirm the user-facing message
      matches, not a raw error/stack trace).
- [ ] With the backend stopped (simulated network failure), scanning shows a
      retryable network error, and the already-selected/captured image
      survives the failure (the user isn't forced to re-pick it).
- [ ] Scanning a deliberately wrong document (something that isn't a
      register page, e.g. a blank sheet or an unrelated photo) fails
      gracefully with a message that doesn't imply success.

### Paths with ZERO automated coverage — must be checked manually
These are unreachable from the widget-test suite because `RecordsNotifier`
has an eager `FirebaseFirestore.instance` field initializer, which the test
harness cannot substitute. No amount of `flutter test` running green says
anything about these paths — they must be run against a real Firebase
project by hand:
- [ ] The real Firebase Storage upload of the scanned image and the
      resulting `getDownloadURL()` call actually succeed and return a
      usable URL.
- [ ] Real `FirebaseAuth` token resolution works for the signed-in staff
      user making the OCR request (not a mocked/fake token).
- [ ] The real Firestore write via `recordsProvider.notifier.addRecordsBatch`
      persists the reviewed rows as records.
- [ ] The real image picker / camera capture flow (device or browser file
      picker, camera permission prompts) works, not just a pre-supplied test
      buffer.

### Regression pass — untouched paths still work
- [ ] `/admin/records` → **Manual Register** entry still works unchanged.
- [ ] `/admin/records` → **Import CSV** still works unchanged.
- [ ] `/admin/records` → **Scan Certificate** still works unchanged.
- [ ] `/admin/records` → **Add Record** still works unchanged.
- [ ] The legacy `/staff/ocr/upload` flow still works unchanged.

### End-to-end record integrity
- [ ] A record saved through the new baptismal OCR flow opens correctly in
      the existing flat register editor (fields map to the right columns,
      nothing is dropped or garbled).
- [ ] The archived scan image (the one written to Storage) actually displays
      when viewing the saved record — not a broken image link.
