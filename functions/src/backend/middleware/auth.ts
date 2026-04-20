import { getAdmin } from '../firebase_admin';
import { Request, Response, NextFunction } from 'express';

// Simple in-memory role cache to reduce Firestore reads.
// Key: uid, Value: { role: string|null, expiresAtMs: number }
const roleCache = new Map<string, { role: string | null; expiresAtMs: number }>();

interface User {
  uid: string;
  email: string | null;
  claims: any;
  admin: boolean;
  role: string | null;
}

interface AuthenticatedRequest extends Request {
  user?: User;
}

async function resolveUserRole(uid: string): Promise<string | null> {
  if (!uid) return null;

  const cached = roleCache.get(uid);
  const now = Date.now();
  if (cached && cached.expiresAtMs > now) {
    return cached.role;
  }

  try {
    const admin = getAdmin();
    const snap = await admin.firestore().collection('users').doc(uid).get();
    const rawRole = snap.exists ? (snap.data()!.role || null) : null;
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

async function verifyFirebaseToken(req: AuthenticatedRequest, res: Response, next: NextFunction): Promise<void> {
  const authHeader = req.headers.authorization || '';
  const token = authHeader.startsWith('Bearer ')
    ? authHeader.slice('Bearer '.length)
    : null;

  if (!token) {
    res.status(401).json({ error: 'Missing Authorization Bearer token' });
    return;
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

    next();
  } catch (err) {
    res.status(401).json({ error: 'Invalid Firebase token' });
  }
}

function requireAdmin(req: AuthenticatedRequest, res: Response, next: NextFunction): void {
  const role = req.user && req.user.role;
  const isAdmin = (req.user && req.user.admin === true) || role === 'admin';

  if (!isAdmin) {
    res.status(403).json({ error: 'Admin access required' });
    return;
  }

  next();
}

function requireSelfOrStaff(getTargetUid: (req: Request) => string) {
  return function (req: AuthenticatedRequest, res: Response, next: NextFunction): void {
    const uid = req.user && req.user.uid ? req.user.uid.toString() : null;
    if (!uid) {
      res.status(401).json({ error: 'Unauthorized' });
      return;
    }

    let targetUid: string | null = null;
    try {
      targetUid = getTargetUid(req);
    } catch (_) {
      targetUid = null;
    }

    if (!targetUid) {
      res.status(400).json({ error: 'Missing target user id' });
      return;
    }
    targetUid = targetUid.toString();

    const isAdmin = req.user && req.user.admin === true;
    const role = req.user && req.user.role;
    const isStaff = role === 'staff' || role === 'admin' || isAdmin;

    if (targetUid !== uid && !isStaff) {
      res.status(403).json({ error: 'Forbidden' });
      return;
    }

    next();
  };
}

function requireStaff(req: AuthenticatedRequest, res: Response, next: NextFunction): void {
  const role = req.user && req.user.role;
  const allowed = role === 'staff' || role === 'admin' || (req.user && req.user.admin === true);

  if (!allowed) {
    res.status(403).json({ error: 'Staff access required' });
    return;
  }

  next();
}

function requireFinance(req: AuthenticatedRequest, res: Response, next: NextFunction): void {
  const role = req.user && req.user.role;
  const allowed = role === 'finance' || role === 'admin' || (req.user && req.user.admin === true);

  if (!allowed) {
    res.status(403).json({ error: 'Finance access required' });
    return;
  }

  next();
}

export {
  verifyFirebaseToken,
  requireAdmin,
  requireStaff,
  requireFinance,
  requireSelfOrStaff,
};
