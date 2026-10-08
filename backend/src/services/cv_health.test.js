const { cvGridStatus } = require('./cv_health');

describe('cvGridStatus', () => {
  test('reports not configured when OCR_SERVICE_URL is unset', async () => {
    const s = await cvGridStatus({ env: {}, fetchImpl: async () => { throw new Error('should not fetch'); } });
    expect(s.configured).toBe(false);
    expect(s.reachable).toBe(false);
    expect(s.message).toMatch(/fallback/i);
  });

  test('reports reachable when the service health check is OK', async () => {
    const calls = [];
    const fetchImpl = async (url) => {
      calls.push(url);
      return { ok: true, json: async () => ({ status: 'ok', version: '2.1.0', registers: ['baptismal', 'marriage'] }) };
    };
    const s = await cvGridStatus({ env: { OCR_SERVICE_URL: 'http://cv:8000/' }, fetchImpl });
    expect(s.configured).toBe(true);
    expect(s.reachable).toBe(true);
    expect(s.version).toBe('2.1.0');
    expect(calls[0]).toBe('http://cv:8000/health'); // trailing slash normalized
  });

  test('flags a reachable but out-of-date service (no version / no marriage template)', async () => {
    const fetchImpl = async () => ({ ok: true, json: async () => ({ status: 'ok' }) });
    const s = await cvGridStatus({ env: { OCR_SERVICE_URL: 'http://cv:8000' }, fetchImpl });
    expect(s.reachable).toBe(false);
    expect(s.stale).toBe(true);
    expect(s.message).toMatch(/OUT OF DATE/);
  });

  test('reports unreachable when the health check fails', async () => {
    const s = await cvGridStatus({
      env: { OCR_SERVICE_URL: 'http://cv:8000' },
      fetchImpl: async () => { throw new Error('ECONNREFUSED'); },
    });
    expect(s.configured).toBe(true);
    expect(s.reachable).toBe(false);
    expect(s.message).toMatch(/fallback/i);
  });

  test('reports unreachable on a non-OK health status', async () => {
    const s = await cvGridStatus({
      env: { OCR_SERVICE_URL: 'http://cv:8000' },
      fetchImpl: async () => ({ ok: false, status: 502 }),
    });
    expect(s.reachable).toBe(false);
  });
});
