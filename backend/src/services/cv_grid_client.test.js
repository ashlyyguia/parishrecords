const { fetchGrid, CvGridError } = require('./cv_grid_client');

const env = { OCR_SERVICE_URL: 'http://cv.local', OCR_SERVICE_KEY: 'k', OCR_TIMEOUT_MS: '5000' };
const okBody = {
  success: true, rotation_applied: 90, deskew_deg: 1.1, warnings: [],
  pages: {
    left: { image_b64: Buffer.from('LEFTIMG').toString('base64'), width: 100, height: 200, rows: 6, cols: 5,
            cells: [{ key: 'child_name', row: 0, x: 1, y: 2, w: 3, h: 4 }] },
    right: { image_b64: Buffer.from('RIGHTIMG').toString('base64'), width: 100, height: 200, rows: 6, cols: 5, cells: [] },
  },
};

test('parses a successful grid response into buffers + cells', async () => {
  const fetchImpl = async () => ({ ok: true, status: 200, json: async () => okBody });
  const grid = await fetchGrid(Buffer.from('img'), { env, fetchImpl });
  expect(grid.rotationApplied).toBe(90);
  expect(grid.pages.left.imageBuffer.toString()).toBe('LEFTIMG');
  expect(grid.pages.left.cells[0].key).toBe('child_name');
  expect(grid.pages.right.rows).toBe(6);
});

test('CV_DISABLED when no service URL is configured', async () => {
  await expect(fetchGrid(Buffer.from('img'), { env: {}, fetchImpl: async () => ({}) }))
    .rejects.toMatchObject({ code: 'CV_DISABLED' });
});

test('CV_UNREACHABLE on a network throw', async () => {
  const fetchImpl = async () => { throw new Error('ECONNREFUSED'); };
  await expect(fetchGrid(Buffer.from('img'), { env, fetchImpl }))
    .rejects.toMatchObject({ code: 'CV_UNREACHABLE' });
});

test('CV_REFUSED on a 4xx OcrError body', async () => {
  const fetchImpl = async () => ({ ok: false, status: 422, json: async () => ({ success: false, code: 'no_table_detected' }) });
  await expect(fetchGrid(Buffer.from('img'), { env, fetchImpl }))
    .rejects.toMatchObject({ code: 'CV_REFUSED' });
});

test('CV_AUTH (not CV_REFUSED) when the service rejects the key', async () => {
  // A 401/unauthorized is a server config fault (wrong OCR_SERVICE_KEY), not
  // the service judging the photo unreadable. The route must be able to tell
  // the two apart -- one falls back, the other tells the user to retake.
  const fetchImpl = async () => ({ ok: false, status: 401, json: async () => ({ success: false, code: 'unauthorized' }) });
  await expect(fetchGrid(Buffer.from('img'), { env, fetchImpl }))
    .rejects.toMatchObject({ code: 'CV_AUTH' });
});

test('CV_REFUSED carries the reason and side from the service', async () => {
  const fetchImpl = async () => ({ ok: false, status: 422, json: async () => ({
    success: false, code: 'no_table_detected', reason: 'columns_unmatched', side: 'left',
  }) });
  await expect(fetchGrid(Buffer.from('img'), { env, fetchImpl }))
    .rejects.toMatchObject({ code: 'CV_REFUSED', reason: 'columns_unmatched', side: 'left' });
});

test('CV_BAD_RESPONSE on malformed success body', async () => {
  const fetchImpl = async () => ({ ok: true, status: 200, json: async () => ({ success: true }) });
  await expect(fetchGrid(Buffer.from('img'), { env, fetchImpl }))
    .rejects.toMatchObject({ code: 'CV_BAD_RESPONSE' });
});

test('CvGridError is exported', () => {
  expect(new CvGridError('X').code).toBe('X');
});
