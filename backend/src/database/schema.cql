-- Parish Records Database Schema for Cassandra
-- This file contains the complete database structure

-- Create keyspace
CREATE KEYSPACE IF NOT EXISTS parish_records
WITH REPLICATION = {
  'class': 'SimpleStrategy',
  'replication_factor': 3
};

USE parish_records;

-- Records table (main parish records)
CREATE TABLE IF NOT EXISTS records (
  id UUID PRIMARY KEY,
  type TEXT,
  name TEXT,
  date DATE,
  place TEXT,
  parish TEXT,
  notes TEXT,
  certificate_status TEXT,
  created_at TIMESTAMP,
  updated_at TIMESTAMP,
  created_by UUID,
  registry_number TEXT,
  book_number TEXT,
  page_number TEXT,
  line_number TEXT
);

-- Create indexes for common queries
CREATE INDEX IF NOT EXISTS records_type_idx ON records (type);
CREATE INDEX IF NOT EXISTS records_date_idx ON records (date);
CREATE INDEX IF NOT EXISTS records_parish_idx ON records (parish);
CREATE INDEX IF NOT EXISTS records_certificate_status_idx ON records (certificate_status);
CREATE INDEX IF NOT EXISTS records_created_at_idx ON records (created_at);

-- Records by type table (for efficient type-based queries)
CREATE TABLE IF NOT EXISTS records_by_type (
  type TEXT,
  created_at TIMESTAMP,
  id UUID,
  name TEXT,
  date DATE,
  place TEXT,
  parish TEXT,
  certificate_status TEXT,
  PRIMARY KEY (type, created_at, id)
) WITH CLUSTERING ORDER BY (created_at DESC, id ASC);

-- Records by parish table (for parish-specific queries)
CREATE TABLE IF NOT EXISTS records_by_parish (
  parish TEXT,
  created_at TIMESTAMP,
  id UUID,
  type TEXT,
  name TEXT,
  date DATE,
  place TEXT,
  certificate_status TEXT,
  PRIMARY KEY (parish, created_at, id)
) WITH CLUSTERING ORDER BY (created_at DESC, id ASC);

-- Users table (for authentication and user management)
CREATE TABLE IF NOT EXISTS users (
  id UUID PRIMARY KEY,
  email TEXT,
  display_name TEXT,
  role TEXT,
  created_at TIMESTAMP,
  last_login TIMESTAMP,
  email_verified BOOLEAN,
  status TEXT
);

-- Create unique index on email
CREATE INDEX IF NOT EXISTS users_email_idx ON users (email);
CREATE INDEX IF NOT EXISTS users_role_idx ON users (role);

-- Certificates table (for certificate tracking)
CREATE TABLE IF NOT EXISTS certificates (
  id UUID PRIMARY KEY,
  record_id UUID,
  certificate_number TEXT,
  issued_date TIMESTAMP,
  issued_by UUID,
  recipient_name TEXT,
  recipient_email TEXT,
  purpose TEXT,
  status TEXT,
  pdf_path TEXT,
  created_at TIMESTAMP
);

-- Create indexes for certificates
CREATE INDEX IF NOT EXISTS certificates_record_id_idx ON certificates (record_id);
CREATE INDEX IF NOT EXISTS certificates_status_idx ON certificates (status);
CREATE INDEX IF NOT EXISTS certificates_issued_date_idx ON certificates (issued_date);

-- Audit logs table (for tracking changes)
CREATE TABLE IF NOT EXISTS audit_logs (
  id UUID PRIMARY KEY,
  user_id UUID,
  action TEXT,
  resource_type TEXT,
  resource_id UUID,
  old_values TEXT,
  new_values TEXT,
  timestamp TIMESTAMP,
  ip_address TEXT,
  user_agent TEXT
);

-- Create indexes for audit logs
CREATE INDEX IF NOT EXISTS audit_logs_user_id_idx ON audit_logs (user_id);
CREATE INDEX IF NOT EXISTS audit_logs_timestamp_idx ON audit_logs (timestamp);
CREATE INDEX IF NOT EXISTS audit_logs_resource_type_idx ON audit_logs (resource_type);

-- Settings table (for application configuration)
CREATE TABLE IF NOT EXISTS settings (
  key TEXT PRIMARY KEY,
  value TEXT,
  description TEXT,
  updated_at TIMESTAMP,
  updated_by UUID
);

-- Notifications table (for system notifications)
CREATE TABLE IF NOT EXISTS notifications (
  id UUID PRIMARY KEY,
  user_id UUID,
  title TEXT,
  message TEXT,
  type TEXT,
  read BOOLEAN,
  created_at TIMESTAMP,
  expires_at TIMESTAMP
);

-- Create indexes for notifications
CREATE INDEX IF NOT EXISTS notifications_user_id_idx ON notifications (user_id);
CREATE INDEX IF NOT EXISTS notifications_created_at_idx ON notifications (created_at);

-- Statistics table (for analytics and reporting)
CREATE TABLE IF NOT EXISTS statistics (
  date DATE,
  metric_type TEXT,
  metric_name TEXT,
  value BIGINT,
  metadata TEXT,
  PRIMARY KEY (date, metric_type, metric_name)
) WITH CLUSTERING ORDER BY (metric_type ASC, metric_name ASC);

-- File attachments table (for document storage references)
CREATE TABLE IF NOT EXISTS attachments (
  id UUID PRIMARY KEY,
  record_id UUID,
  filename TEXT,
  file_path TEXT,
  file_size BIGINT,
  mime_type TEXT,
  uploaded_by UUID,
  uploaded_at TIMESTAMP
);

-- Create indexes for attachments
CREATE INDEX IF NOT EXISTS attachments_record_id_idx ON attachments (record_id);

-- Insert default settings
INSERT INTO settings (key, value, description, updated_at) VALUES 
('app_name', 'Parish Record System', 'Application name', toTimestamp(now()))
IF NOT EXISTS;

INSERT INTO settings (key, value, description, updated_at) VALUES 
('version', '1.0.0', 'Application version', toTimestamp(now()))
IF NOT EXISTS;

INSERT INTO settings (key, value, description, updated_at) VALUES 
('timezone', 'UTC', 'Default timezone', toTimestamp(now()))
IF NOT EXISTS;

INSERT INTO settings (key, value, description, updated_at) VALUES 
('max_file_size', '10485760', 'Maximum file upload size in bytes (10MB)', toTimestamp(now()))
IF NOT EXISTS;

-- Create materialized views for common queries
CREATE MATERIALIZED VIEW IF NOT EXISTS records_by_certificate_status AS
  SELECT id, type, name, date, certificate_status, created_at
  FROM records
  WHERE certificate_status IS NOT NULL AND id IS NOT NULL
  PRIMARY KEY (certificate_status, created_at, id)
  WITH CLUSTERING ORDER BY (created_at DESC, id ASC);

CREATE MATERIALIZED VIEW IF NOT EXISTS recent_records AS
  SELECT id, type, name, date, parish, certificate_status, created_at
  FROM records
  WHERE created_at IS NOT NULL AND id IS NOT NULL
  PRIMARY KEY (created_at, id)
  WITH CLUSTERING ORDER BY (created_at DESC);
