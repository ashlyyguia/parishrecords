const express = require('express');
const bcrypt = require('bcrypt');
const jwt = require('jsonwebtoken');
const { v4: uuidv4 } = require('uuid');
const cassandraClient = require('../database/cassandra');
const emailService = require('../services/email');
const { logAudit } = require('../utils/audit');

const router = express.Router();

// Register new user
router.post('/register', async (req, res) => {
  try {
    const { email, password, displayName, role = 'staff' } = req.body;

    // Check if user already exists
    const existingUser = await cassandraClient.execute(
      'SELECT email FROM users WHERE email = ? ALLOW FILTERING',
      [email]
    );

    if (existingUser.rows.length > 0) {
      return res.status(400).json({ error: 'User already exists' });
    }

    // Hash password
    const hashedPassword = await bcrypt.hash(password, 10);
    const userId = uuidv4();

    // Insert user
    await cassandraClient.execute(
      'INSERT INTO users (id, email, display_name, role, created_at, email_verified) VALUES (?, ?, ?, ?, ?, ?)',
      [userId, email, displayName, role, new Date(), false]
    );

    // Generate JWT token
    const token = jwt.sign(
      { userId, email, role },
      process.env.JWT_SECRET,
      { expiresIn: process.env.JWT_EXPIRES_IN }
    );

    // Audit: Account Created
    await logAudit(req, {
      userId: userId,
      action: 'Account Created',
      resourceType: 'user',
      resourceId: userId,
      newValues: { email, displayName, role },
    });

    res.status(201).json({
      message: 'User created successfully',
      token,
      user: { id: userId, email, displayName, role }
    });

  } catch (error) {
    console.error('Registration error:', error);
    res.status(500).json({ error: 'Registration failed' });
  }
});

// Login user
router.post('/login', async (req, res) => {
  try {
    const { email, password } = req.body;

    // Find user
    const result = await cassandraClient.execute(
      'SELECT * FROM users WHERE email = ? ALLOW FILTERING',
      [email]
    );

    if (result.rows.length === 0) {
      return res.status(401).json({ error: 'Invalid credentials' });
    }

    const user = result.rows[0];

    // For now, skip password verification since we're integrating with Firebase Auth
    // In production, you'd verify the Firebase token here

    // Update last login
    await cassandraClient.execute(
      'UPDATE users SET last_login = ? WHERE id = ?',
      [new Date(), user.id]
    );

    // Generate JWT token
    const token = jwt.sign(
      { userId: user.id, email: user.email, role: user.role },
      process.env.JWT_SECRET,
      { expiresIn: process.env.JWT_EXPIRES_IN }
    );

    // Audit: User Login
    await logAudit(req, {
      userId: user.id,
      action: 'User Login',
      resourceType: 'user',
      resourceId: user.id,
      newValues: { email: user.email },
    });

    res.json({
      message: 'Login successful',
      token,
      user: {
        id: user.id,
        email: user.email,
        displayName: user.display_name,
        role: user.role
      }
    });

  } catch (error) {
    console.error('Login error:', error);
    res.status(500).json({ error: 'Login failed' });
  }
});

// Verify token middleware
const verifyToken = (req, res, next) => {
  const token = req.headers.authorization?.split(' ')[1];

  if (!token) {
    return res.status(401).json({ error: 'No token provided' });
  }

  try {
    const decoded = jwt.verify(token, process.env.JWT_SECRET);
    req.user = decoded;
    next();
  } catch (error) {
    return res.status(401).json({ error: 'Invalid token' });
  }
};

// Get current user
router.get('/me', verifyToken, async (req, res) => {
  try {
    const result = await cassandraClient.execute(
      'SELECT * FROM users WHERE id = ?',
      [req.user.userId]
    );

    if (result.rows.length === 0) {
      return res.status(404).json({ error: 'User not found' });
    }

    const user = result.rows[0];
    res.json({
      id: user.id,
      email: user.email,
      displayName: user.display_name,
      role: user.role,
      emailVerified: user.email_verified,
      createdAt: user.created_at,
      lastLogin: user.last_login
    });

  } catch (error) {
    console.error('Get user error:', error);
    res.status(500).json({ error: 'Failed to get user' });
  }
});

// Send 6-digit verification code email
router.post('/send-code', async (req, res) => {
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

module.exports = router;
