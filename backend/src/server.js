const express = require('express');
const cors = require('cors');
const helmet = require('helmet');
const rateLimit = require('express-rate-limit');
require('dotenv').config();

const authRoutes = require('./routes/auth');
const recordsRoutes = require('./routes/records_firestore');
const usersRoutes = require('./routes/users_firestore');
const userDashboardRoutes = require('./routes/user_dashboard_firestore');
const notificationsRoutes = require('./routes/notifications_firestore');
const adminRoutes = require('./routes/admin_firestore');
const verificationRoutes = require('./routes/verification');
const householdsRoutes = require('./routes/households');
const requestsRoutes = require('./routes/requests');
const appointmentsRoutes = require('./routes/appointments');
const profileRoutes = require('./routes/profile');
const { verifyFirebaseToken } = require('./middleware/auth');

const app = express();
// Render sits behind a proxy and sets X-Forwarded-* headers.
// express-rate-limit validates these headers and requires trust proxy to be enabled.
app.set('trust proxy', 1);
const PORT = process.env.PORT || 10000;

// Security middleware
app.use(helmet());
app.use(cors({
  origin: function(origin, callback) {
    // Allow any localhost origin for development
    if (!origin || origin.includes('localhost') || origin.includes('127.0.0.1')) {
      return callback(null, true);
    }
    // Check against allowed origins from env
    const allowedOrigins = process.env.ALLOWED_ORIGINS?.split(',') || [];
    if (allowedOrigins.includes(origin) || allowedOrigins.includes('*')) {
      return callback(null, true);
    }
    callback(null, true); // Allow all for now during development
  },
  credentials: true,
  methods: ['GET', 'POST', 'PUT', 'DELETE', 'PATCH', 'OPTIONS'],
  allowedHeaders: ['Content-Type', 'Authorization', 'X-Requested-With']
}));

// Rate limiting
const limiter = rateLimit({
  windowMs: 15 * 60 * 1000, // 15 minutes
  max: 100 // limit each IP to 100 requests per windowMs
});
app.use(limiter);

// Body parsing middleware
app.use(express.json({ limit: '10mb' }));
app.use(express.urlencoded({ extended: true }));

// Health check endpoint
app.get('/health', (req, res) => {
  res.json({ 
    status: 'OK', 
    timestamp: new Date().toISOString(),
    database: 'disabled'
  });
});

// EmailJS config test (public endpoint)
app.get('/api/verification/test-config', (req, res) => {
  res.json({
    emailjsConfigured: {
      serviceId: !!process.env.EMAILJS_SERVICE_ID,
      templateId: !!process.env.EMAILJS_TEMPLATE_ID,
      publicKey: !!process.env.EMAILJS_PUBLIC_KEY,
      privateKey: !!process.env.EMAILJS_PRIVATE_KEY,
      fromName: process.env.EMAILJS_FROM_NAME || 'ParishRecord'
    },
    timestamp: new Date().toISOString()
  });
});

// API routes
app.use('/api/auth', authRoutes);
app.use('/api/verification', verificationRoutes);

// All remaining /api routes require a valid Firebase ID token
app.use('/api', verifyFirebaseToken);

app.use('/api/records', recordsRoutes);
app.use('/api/users', usersRoutes);
app.use('/api/users', userDashboardRoutes);
app.use('/api/users', profileRoutes);
app.use('/api/notifications', notificationsRoutes);
app.use('/api/admin', adminRoutes);
app.use('/api/households', householdsRoutes);
app.use('/api/requests', requestsRoutes);
app.use('/api/appointments', appointmentsRoutes);

// Error handling middleware
app.use((err, req, res, next) => {
  console.error('Error:', err);
  res.status(err.status || 500).json({
    error: process.env.NODE_ENV === 'production' ? 'Internal Server Error' : err.message
  });
});

// 404 handler
app.use('*', (req, res) => {
  res.status(404).json({ error: 'Route not found' });
});

// Start server
async function startServer() {
  try {
    app.listen(PORT, () => {
      console.log(`🚀 Parish Record API server running on port ${PORT}`);
      console.log(`📊 Health check: http://localhost:${PORT}/health`);
    });
  } catch (error) {
    console.error('❌ Failed to start server:', error);
    process.exit(1);
  }
}

// Graceful shutdown
process.on('SIGINT', async () => {
  console.log('\n🛑 Shutting down server...');
  process.exit(0);
});

startServer();
