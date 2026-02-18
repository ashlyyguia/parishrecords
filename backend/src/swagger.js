function createSwaggerDocument(port) {
  return {
    openapi: '3.0.0',
    info: {
      title: 'Parish Record API',
      version: '1.0.0',
      description: 'API documentation and interactive console for the Parish Record backend.',
    },
    servers: [
      {
        url: `http://localhost:${port}`,
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
                    notes: {
                      type: 'string',
                      example: '{"metadata": {"recordId": "abc123"}}',
                    },
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
                    notes: {
                      type: 'string',
                      example: '{"baptism": {"date": "2024-01-01"}}',
                    },
                    certificateStatus: {
                      type: 'string',
                      example: 'approved',
                    },
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
      '/api/attachments': {
        post: {
          summary: 'Upload an attachment (e.g., exported backup file)',
          requestBody: {
            required: true,
            content: {
              'application/json': {
                schema: {
                  type: 'object',
                  properties: {
                    record_type: { type: 'string', example: 'backup' },
                    record_id: { type: 'string', example: 'all-records' },
                    filename: { type: 'string', example: 'records.csv' },
                    mime_type: { type: 'string', example: 'text/csv' },
                    content_base64: {
                      type: 'string',
                      example: 'BASE64_BYTES_HERE',
                    },
                  },
                  required: ['filename', 'content_base64'],
                },
              },
            },
          },
          responses: {
            201: { description: 'Attachment stored' },
            400: { description: 'Invalid payload' },
            401: { description: 'Unauthorized' },
            500: { description: 'Server error' },
          },
        },
      },
    },
  };
}

module.exports = { createSwaggerDocument };
