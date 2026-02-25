const express = require('express');
const cors = require('cors');
const helmet = require('helmet');
const rateLimit = require('express-rate-limit');
const swaggerUi = require('swagger-ui-express');
const path = require('path');
require('dotenv').config({ path: path.resolve(__dirname, '..', '.env') });

const { createSwaggerDocument } = require('./swagger');
const recordsRoutes = require('./routes/records_firestore');
const usersRoutes = require('./routes/users_firestore');
const adminRoutes = require('./routes/admin_firestore');
const requestsRoutes = require('./routes/requests_firestore');
const notificationsRoutes = require('./routes/notifications_firestore');
const staffRoutes = require('./routes/staff_firestore');
const ocrJobsRoutes = require('./routes/ocr_jobs_firestore');
const eventsRoutes = require('./routes/events_firestore');
const bookingsRoutes = require('./routes/bookings_firestore');
const financeRoutes = require('./routes/finance_firestore');
const donationsRoutes = require('./routes/donations_firestore');
const reportsFinancialRoutes = require('./routes/reports_financial_firestore');
const userDashboardRoutes = require('./routes/user_dashboard_firestore');
const userSelfRoutes = require('./routes/user_self_firestore');
const sacramentsRoutes = require('./routes/sacraments_firestore');
const appointmentsRoutes = require('./routes/appointments_firestore');
const { verifyFirebaseToken } = require('./middleware/auth');
const { logAudit } = require('./utils/audit');

const app = express();
const PORT = process.env.PORT || 3000;

// Minimal OpenAPI specification for developer docs
const swaggerDocument = createSwaggerDocument(PORT);

// Security middleware
app.use(helmet({
  // Relax CSP and cross-origin policies enough for Swagger UI and local tools
  contentSecurityPolicy: false,
  crossOriginEmbedderPolicy: false,
}));
const allowedOrigins = (process.env.ALLOWED_ORIGINS || '')
  .split(',')
  .map((v) => v.trim())
  .filter(Boolean);

app.use(
  cors({
    origin: (origin, cb) => {
      if (!origin) return cb(null, true);
      if (allowedOrigins.length === 0) return cb(null, true);
      if (allowedOrigins.includes(origin)) return cb(null, true);
      return cb(new Error('CORS origin not allowed'));
    },
    credentials: true,
  }),
);

// Rate limiting
const limiter = rateLimit({
  windowMs: 15 * 60 * 1000, // 15 minutes
  max: 100 // limit each IP to 100 requests per windowMs
});
app.use(limiter);

// Body parsing middleware
app.use(express.json({ limit: '10mb' }));
app.use(express.urlencoded({ extended: true }));

// Developer API docs (web IDE)
app.use('/docs', swaggerUi.serve, swaggerUi.setup(swaggerDocument));

// Health check endpoint
app.get('/health', (req, res) => {
  res.json({ 
    status: 'OK', 
    timestamp: new Date().toISOString(),
    database: 'disabled'
  });
});

app.use('/api', verifyFirebaseToken);

app.post('/api/audit', express.json({ limit: '10kb' }), async (req, res) => {
  try {
    const body = req.body || {};

    const action = (body.action || '').toString();
    if (!action) {
      return res.status(400).json({ error: 'Missing action' });
    }

    const resourceType = body.resource_type || body.resourceType || null;
    const resourceId = body.resource_id || body.resourceId || null;
    const oldValues = body.old_values || body.oldValues || null;
    const newValues = body.new_values || body.newValues || body.details || null;

    await logAudit(req, {
      action,
      resourceType: resourceType ? resourceType.toString() : null,
      resourceId: resourceId ? resourceId.toString() : null,
      oldValues,
      newValues,
    });

    return res.json({ ok: true });
  } catch (error) {
    console.error('Audit ingest error:', error);
    return res.status(500).json({ error: 'Failed to write audit log' });
  }
});

app.post('/api/auth/send-code', express.json({ limit: '10kb' }), async (req, res) => {
  try {
    const emailService = require('./services/email');
    const { email, code } = req.body || {};
    if (!email || !code) {
      return res.status(400).json({ error: 'Email and code are required' });
    }
    await emailService.sendVerificationCodeEmail(email.toString(), code.toString());
    return res.json({ ok: true });
  } catch (error) {
    console.error('Send verification code error:', error);
    return res.status(500).json({ error: 'Failed to send verification code' });
  }
});

app.use('/api/records', recordsRoutes);
app.use('/api/users', usersRoutes);
app.use('/api/admin', adminRoutes);
app.use('/api/requests', requestsRoutes);
app.use('/api/notifications', notificationsRoutes);
app.use('/api/staff', staffRoutes);
app.use('/api/ocr_jobs', ocrJobsRoutes);
app.use('/api/events', eventsRoutes);
app.use('/api/bookings', bookingsRoutes);
app.use('/api/finance', financeRoutes);
app.use('/api/donations', donationsRoutes);
app.use('/api/reports', reportsFinancialRoutes);
app.use('/api/users', userDashboardRoutes);
app.use('/api/users', userSelfRoutes);
app.use('/api/sacraments', sacramentsRoutes);
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
