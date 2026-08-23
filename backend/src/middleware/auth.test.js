jest.mock('../firebase_admin', () => ({
  getAdmin: jest.fn(),
}));

const { verifyFirebaseToken } = require('./auth');

function makeReq(headers = {}, overrides = {}) {
  return { headers, params: {}, body: {}, ...overrides };
}

function makeRes() {
  const res = {};
  res.status = jest.fn().mockReturnValue(res);
  res.json = jest.fn().mockReturnValue(res);
  return res;
}

describe('verifyFirebaseToken dev bypass', () => {
  const originalEnv = process.env.DEV_BYPASS_AUTH;

  afterEach(() => {
    process.env.DEV_BYPASS_AUTH = originalEnv;
  });

  // FIX 1 regression: `Origin` is a header the client fully controls, unlike
  // `Host`. A request to a real production host that merely SETS
  // `Origin: http://localhost` used to be granted `req.user.admin = true`
  // with zero credentials -- e.g.
  // `curl -H 'Origin: http://localhost' https://<prod-host>/api/ocr/baptismal/scan`.
  // This must now fall through to the real (missing-token) 401 path instead.
  test('an Origin: http://localhost header alone does not grant admin bypass', async () => {
    delete process.env.DEV_BYPASS_AUTH;
    const req = makeReq({ host: 'api.example.com', origin: 'http://localhost' });
    const res = makeRes();
    const next = jest.fn();

    await verifyFirebaseToken(req, res, next);

    expect(req.user).toBeUndefined();
    expect(next).not.toHaveBeenCalled();
    expect(res.status).toHaveBeenCalledWith(401);
  });

  test('a spoofed Origin header does not bypass auth even when other headers look benign', async () => {
    delete process.env.DEV_BYPASS_AUTH;
    const req = makeReq({
      host: 'holyparish-backend.onrender.com',
      origin: 'http://localhost:3000',
    });
    const res = makeRes();
    const next = jest.fn();

    await verifyFirebaseToken(req, res, next);

    expect(req.user).toBeUndefined();
    expect(next).not.toHaveBeenCalled();
    expect(res.json).toHaveBeenCalledWith(
      expect.objectContaining({ error: expect.any(String) }),
    );
  });

  // Regression guard the OTHER direction: the legitimate local-dev bypass
  // (matched on Host, not Origin) must keep working unchanged.
  test('a genuine localhost Host still bypasses auth as admin', async () => {
    delete process.env.DEV_BYPASS_AUTH;
    const req = makeReq({ host: 'localhost:3000' });
    const res = makeRes();
    const next = jest.fn();

    await verifyFirebaseToken(req, res, next);

    expect(next).toHaveBeenCalledTimes(1);
    expect(req.user).toMatchObject({ admin: true, role: 'admin' });
  });

  test('DEV_BYPASS_AUTH=true still bypasses auth regardless of host', async () => {
    process.env.DEV_BYPASS_AUTH = 'true';
    const req = makeReq({ host: 'api.example.com' });
    const res = makeRes();
    const next = jest.fn();

    await verifyFirebaseToken(req, res, next);

    expect(next).toHaveBeenCalledTimes(1);
    expect(req.user).toMatchObject({ admin: true, role: 'admin' });
  });
});
