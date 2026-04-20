const express = require('express');
const { getAdmin } = require('../firebase_admin');
const emailService = require('../services/email');
const { logAudit } = require('../utils/audit');
const { verifyFirebaseToken } = require('../middleware/auth');

const router = express.Router();

router.post('/register', (_req, res) => {
  return res.status(410).json({
    error: 'auth_register_removed',
    message: 'Registration is handled by Firebase Auth. Create users via Firebase Auth and store profiles under Firestore users/{uid}.',
  });
});

router.post('/login', (_req, res) => {
  return res.status(410).json({
    error: 'auth_login_removed',
    message: 'Login is handled by Firebase Auth. Send Firebase ID token as Authorization: Bearer <token> to access /api routes.',
  });
});

router.get('/me', verifyFirebaseToken, async (req, res) => {
  try {
    const uid = req.user && req.user.uid ? req.user.uid.toString() : null;
    if (!uid) {
      return res.status(401).json({ error: 'Unauthorized' });
    }

    const admin = getAdmin();
    const db = admin.firestore();

    const userDoc = await db.collection('users').doc(uid).get();
    const data = userDoc.exists ? (userDoc.data() || {}) : {};

    await logAudit(req, {
      userId: uid,
      action: 'User Profile Viewed',
      resourceType: 'user',
      resourceId: uid,
      newValues: { email: req.user.email || null },
    });

    return res.json({
      id: uid,
      uid,
      email: req.user.email || data.email || null,
      displayName: data.display_name || data.displayName || req.user.name || null,
      role: data.role || (req.user.admin ? 'admin' : 'staff'),
      emailVerified: req.user.email_verified === true || data.email_verified === true,
      disabled: data.disabled === true,
      createdAt: data.created_at || null,
      lastLogin: data.last_login || null,
    });
  } catch (error) {
    console.error('Get user error:', error);
    return res.status(500).json({ error: 'Failed to get user' });
  }
});

// Send 6-digit verification code email
router.post('/send-code', verifyFirebaseToken, async (req, res) => {
  try {
    const { email, code } = req.body || {};

    if (!email || !code) {
      return res.status(400).json({ error: 'Email and code are required' });
    }

    await emailService.sendVerificationCodeEmail(email.toString(), code.toString());

    res.json({ ok: true });
  } catch (error) {
    console.error('Send verification code error:', error);
    res.status(500).json({ error: 'Failed to send verification code' });
  }
});

// Generate password reset link
router.post('/reset-password', async (req, res) => {
  try {
    const { email } = req.body || {};
    if (!email) {
      return res.status(400).json({ error: 'Email is required' });
    }

    const admin = getAdmin();
    // Ensure user exists
    try {
      await admin.auth().getUserByEmail(email);
    } catch (e) {
      // Don't leak user existence in production, just return success
      return res.json({ success: true });
    }

    const link = await admin.auth().generatePasswordResetLink(email);

    if (!process.env.EMAILJS_SERVICE_ID) {
      console.warn('\n======================================================');
      console.warn('⚠️ EMAILJS IS NOT CONFIGURED IN .env FILE');
      console.warn(`📩 MOCK PASSWORD RESET SENT TO: ${email}`);
      console.warn(`🔗 RESET LINK: ${link}`);
      console.warn('======================================================\n');
      
      // Send the link back to the client in dev mode so they don't need the terminal
      return res.json({ success: true, devModeLink: link });
    }

    // If EmailJS is configured, normally you'd send an email here.
    // For now, we rely on the default Firebase flow for prod, or just return success.
    res.json({ success: true, message: 'Password reset processed' });
  } catch (error) {
    console.error('Password reset error:', error);
    res.status(500).json({ error: 'Failed to generate reset link' });
  }
});

module.exports = router;
