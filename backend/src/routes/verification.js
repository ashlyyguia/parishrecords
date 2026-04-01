const express = require('express');
const { sendVerificationCodeEmail } = require('../services/email');
const { getAdmin } = require('../firebase_admin');

const router = express.Router();

/**
 * POST /api/verification/send-code
 * Send verification code email via EmailJS
 * Body: { email: string, code: string, displayName?: string }
 */
router.post('/send-code', async (req, res) => {
  try {
    const { email, code, displayName } = req.body;

    console.log('[EmailJS] Received send-code request:', { email, code: code ? '***' : 'missing', displayName });
    console.log('[EmailJS] Environment check:', {
      serviceId: process.env.EMAILJS_SERVICE_ID ? 'set' : 'missing',
      templateId: process.env.EMAILJS_TEMPLATE_ID ? 'set' : 'missing',
      publicKey: process.env.EMAILJS_PUBLIC_KEY ? 'set' : 'missing',
      privateKey: process.env.EMAILJS_PRIVATE_KEY ? 'set' : 'missing'
    });

    if (!email || !code) {
      console.log('[EmailJS] Missing required fields');
      return res.status(400).json({ error: 'Email and code are required' });
    }

    // Send email via EmailJS
    console.log('[EmailJS] Calling sendVerificationCodeEmail...');
    await sendVerificationCodeEmail(email, code);
    console.log('[EmailJS] Email sent successfully');

    res.json({ 
      success: true, 
      message: 'Verification email sent successfully' 
    });
  } catch (error) {
    console.error('[EmailJS] Error sending verification email:', error);
    res.status(500).json({ 
      error: 'Failed to send verification email',
      details: error.message 
    });
  }
});

/**
 * POST /api/verification/resend-code
 * Resend verification code and update Firestore
 * Body: { uid: string }
 */
router.post('/resend-code', async (req, res) => {
  try {
    const { uid } = req.body;

    if (!uid) {
      return res.status(400).json({ error: 'User ID is required' });
    }

    const admin = getAdmin();
    // Get user document
    const userDoc = await admin.firestore().collection('users').doc(uid).get();
    
    if (!userDoc.exists) {
      return res.status(404).json({ error: 'User not found' });
    }

    const userData = userDoc.data();

    if (userData?.verificationCodeVerified) {
      return res.status(400).json({ error: 'User already verified' });
    }

    // Generate new 6-digit code
    const code = Math.floor(100000 + Math.random() * 900000).toString();
    const expiresAt = new Date(Date.now() + 15 * 60 * 1000); // 15 minutes

    // Update Firestore
    await admin.firestore().collection('users').doc(uid).update({
      verificationCode: code,
      verificationCodeExpiresAt: expiresAt,
      verificationCodeVerified: false,
    });

    // Send email
    await sendVerificationCodeEmail(userData.email, code);

    res.json({ 
      success: true, 
      message: 'Verification code resent successfully' 
    });
  } catch (error) {
    console.error('Error resending verification code:', error);
    res.status(500).json({ 
      error: 'Failed to resend verification code',
      details: error.message 
    });
  }
});

module.exports = router;
