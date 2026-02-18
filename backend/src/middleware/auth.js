const { getAdmin } = require('../firebase_admin');

// Simple in-memory role cache to reduce Firestore reads.
// Key: uid, Value: { role: string|null, expiresAtMs: number }
const roleCache = new Map();

async function resolveUserRole(uid) {
  if (!uid) return null;

  const cached = roleCache.get(uid);
  const now = Date.now();
  if (cached && cached.expiresAtMs > now) {
    return cached.role;
  }

  try {
    const admin = getAdmin();
    const snap = await admin.firestore().collection('users').doc(uid).get();
    const rawRole = snap.exists ? (snap.data().role || null) : null;
    const role = rawRole ? rawRole.toString().trim().toLowerCase() : null;

    roleCache.set(uid, {
      role: role,
      expiresAtMs: now + 60 * 1000,
    });

    return role;
  } catch (_) {
    // If Firestore lookup fails, we fall back to token claims only.
    return null;
  }
}

async function verifyFirebaseToken(req, res, next) {
  const authHeader = req.headers.authorization || '';
  const token = authHeader.startsWith('Bearer ')
    ? authHeader.slice('Bearer '.length)
    : null;

  if (!token) {
    return res.status(401).json({ error: 'Missing Authorization Bearer token' });
  }

  try {
    const admin = getAdmin();
    const decoded = await admin.auth().verifyIdToken(token);

    // Normalize user info on request
    req.user = {
      uid: decoded.uid,
      email: decoded.email || null,
      claims: decoded,
      // Prefer Firestore role; claims are only a fallback when Firestore is unavailable.
      admin: false,
      role: null,
    };

    // Prefer Firestore role if present
    const roleFromDb = await resolveUserRole(decoded.uid);
    if (roleFromDb) {
      req.user.role = roleFromDb;
      req.user.admin = roleFromDb === 'admin';
    } else {
      // Fallback to claim patterns only if Firestore lookup failed.
      const claimAdmin = decoded.admin === true || decoded.isAdmin === true;
      req.user.admin = claimAdmin;
      req.user.role = claimAdmin ? 'admin' : null;
    }

    return next();
  } catch (err) {
    return res.status(401).json({ error: 'Invalid Firebase token' });
  }
}

function requireAdmin(req, res, next) {
  const role = req.user && req.user.role;
  const isAdmin = (req.user && req.user.admin === true) || role === 'admin';

  if (!isAdmin) {
    return res.status(403).json({ error: 'Admin access required' });
  }

  return next();
}

function requireStaff(req, res, next) {
  const role = req.user && req.user.role;
  const allowed = role === 'staff' || role === 'admin' || (req.user && req.user.admin === true);

  if (!allowed) {
    return res.status(403).json({ error: 'Staff access required' });
  }

  return next();
}

module.exports = {
  verifyFirebaseToken,
  requireAdmin,
  requireStaff,
};
