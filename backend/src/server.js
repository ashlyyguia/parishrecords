const express = require('express');
const cors = require('cors');
const helmet = require('helmet');
const rateLimit = require('express-rate-limit');
const swaggerUi = require('swagger-ui-express');
require('dotenv').config();

const cassandraClient = require('./database/cassandra');
const authRoutes = require('./routes/auth');
const recordsRoutes = require('./routes/records');
const usersRoutes = require('./routes/users');
const adminRoutes = require('./routes/admin');
const requestsRoutes = require('./routes/requests');

const app = express();
const PORT = process.env.PORT || 3000;

// Minimal OpenAPI specification for developer docs
const swaggerDocument = {
  openapi: '3.0.0',
  info: {
    title: 'Parish Record API',
    version: '1.0.0',
    description: 'API documentation and interactive console for the Parish Record backend.',
  },
  servers: [
    {
      url: `http://localhost:${PORT}`,
      description: 'Local server',
    },
  ],
  components: {
    securitySchemes: {
      bearerAuth: {
        type: 'http',
        scheme: 'bearer',
        bearerFormat: 'JWT',
      },
    },
  },
  security: [
    {
      bearerAuth: [],
    },
  ],
  paths: {
    '/health': {
      get: {
        summary: 'Health check',
        responses: {
          200: {
            description: 'Health status of the API and database',
          },
        },
      },
    },
    '/api/auth/send-code': {
      post: {
        summary: 'Send verification code email',
        requestBody: {
          required: true,
          content: {
            'application/json': {
              schema: {
                type: 'object',
                properties: {
                  email: { type: 'string', example: 'user@example.com' },
                  code: { type: 'string', example: '123456' },
                },
                required: ['email', 'code'],
              },
            },
          },
        },
        responses: {
          200: { description: 'Verification email sent' },
          400: { description: 'Missing email or code' },
          500: { description: 'Internal server error' },
        },
      },
    },
    '/api/records': {
      get: {
        summary: 'List parish records',
        responses: {
          200: { description: 'List of records' },
          401: { description: 'Unauthorized' },
        },
      },
      post: {
        summary: 'Create new record',
        requestBody: {
          required: true,
          content: {
            'application/json': {
              schema: {
                type: 'object',
                properties: {
                  type: { type: 'string', example: 'baptism' },
                  text: { type: 'string', example: 'John Doe' },
                  source: { type: 'string', example: 'parish_1' },
                  notes: { type: 'string', example: '{"metadata": {"recordId": "abc123"}}' },
                },
                required: ['type', 'text'],
              },
            },
          },
        },
        responses: {
          201: { description: 'Record created' },
          400: { description: 'Invalid payload' },
          401: { description: 'Unauthorized' },
          500: { description: 'Server error' },
        },
      },
    },
    '/api/records/{id}': {
      put: {
        summary: 'Update existing record (from notes JSON)',
        parameters: [
          {
            name: 'id',
            in: 'path',
            required: true,
            schema: { type: 'string' },
          },
        ],
        requestBody: {
          required: true,
          content: {
            'application/json': {
              schema: {
                type: 'object',
                properties: {
                  notes: { type: 'string', example: '{"baptism": {"date": "2024-01-01"}}' },
                  certificateStatus: { type: 'string', example: 'approved' },
                },
                required: ['notes'],
              },
            },
          },
        },
        responses: {
          200: { description: 'Record updated' },
          400: { description: 'Missing notes' },
          401: { description: 'Unauthorized' },
          404: { description: 'Record not found' },
        },
      },
      delete: {
        summary: 'Delete a record',
        parameters: [
          {
            name: 'id',
            in: 'path',
            required: true,
            schema: { type: 'string' },
          },
        ],
        responses: {
          200: { description: 'Record deleted' },
          401: { description: 'Unauthorized' },
          404: { description: 'Record not found' },
        },
      },
    },
    '/api/records/{id}/certificate-status': {
      put: {
        summary: 'Update certificate status for a record',
        parameters: [
          {
            name: 'id',
            in: 'path',
            required: true,
            schema: { type: 'string' },
          },
        ],
        requestBody: {
          required: true,
          content: {
            'application/json': {
              schema: {
                type: 'object',
                properties: {
                  status: { type: 'string', example: 'approved' },
                },
                required: ['status'],
              },
            },
          },
        },
        responses: {
          200: { description: 'Certificate status updated' },
          400: { description: 'Missing status' },
          401: { description: 'Unauthorized' },
          404: { description: 'Record not found' },
        },
      },
    },
    '/api/admin/records/recent': {
      get: {
        summary: 'List recent records for admin (for backup/export)',
        parameters: [
          {
            name: 'limit',
            in: 'query',
            schema: { type: 'integer', example: 100 },
          },
          {
            name: 'days',
            in: 'query',
            schema: { type: 'integer', example: 7 },
          },
        ],
        responses: {
          200: { description: 'Recent records returned' },
          401: { description: 'Unauthorized' },
          500: { description: 'Server error' },
        },
      },
    },
  },
};

// Security middleware
app.use(helmet({
  // Relax CSP and cross-origin policies enough for Swagger UI and local tools
  contentSecurityPolicy: false,
  crossOriginEmbedderPolicy: false,
}));
app.use(cors({
  origin: process.env.ALLOWED_ORIGINS?.split(',') || ['http://localhost:3000'],
  credentials: true
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

// Developer API docs (web IDE)
app.use('/docs', swaggerUi.serve, swaggerUi.setup(swaggerDocument));

// Health check endpoint
app.get('/health', (req, res) => {
  res.json({ 
    status: 'OK', 
    timestamp: new Date().toISOString(),
    database: cassandraClient.getState() === 'connected' ? 'connected' : 'disconnected'
  });
});

// API routes
app.use('/api/auth', authRoutes);
app.use('/api/records', recordsRoutes);
app.use('/api/users', usersRoutes);
app.use('/api/admin', adminRoutes);
app.use('/api/requests', requestsRoutes);

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
    // Connect to Cassandra
    await cassandraClient.connect();
    console.log('✅ Connected to Cassandra database');
    
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
  await cassandraClient.shutdown();
  process.exit(0);
});

startServer();
