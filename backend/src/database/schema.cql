-- Parish Records Database Schema for Cassandra (revised)
-- Keyspace: parish_records

-- Create keyspace
CREATE KEYSPACE IF NOT EXISTS parish_records
WITH REPLICATION = {
  'class': 'SimpleStrategy',
  'replication_factor': 3
};

USE parish_records;

-- Records by type (summary across all sacrament tables)
CREATE TABLE IF NOT EXISTS records_by_type (
  type TEXT,
  parish_id TEXT,
  id TEXT,
  name TEXT,
  date DATE,
  place TEXT,
  certificate_status TEXT,
  created_at TIMESTAMP,
  PRIMARY KEY (type, created_at, id)
) WITH CLUSTERING ORDER BY (created_at DESC, id ASC);

-- Sacrament record tables
CREATE TABLE IF NOT EXISTS baptism_records (
  parish_id TEXT,
  id TEXT,
  name TEXT,
  gender TEXT,
  date_of_birth DATE,
  place_of_birth TEXT,
  father_name TEXT,
  mother_name TEXT,
  godfather_name TEXT,
  godmother_name TEXT,
  date_of_baptism DATE,
  time_of_baptism TEXT,
  minister_name TEXT,
  date DATE,
  place TEXT,
  created_at TIMESTAMP,
  updated_at TIMESTAMP,
  created_by TEXT,
  book_number TEXT,
  page_number TEXT,
  line_number TEXT,
  PRIMARY KEY (parish_id, id)
);

CREATE TABLE IF NOT EXISTS marriage_records (
  parish_id TEXT,
  id TEXT,
  groom_name TEXT,
  bride_name TEXT,
  date DATE,
  time_of_marriage TEXT,
  place TEXT,
  officiant_name TEXT,
  groom_age_or_dob TEXT,
  groom_civil_status TEXT,
  groom_religion TEXT,
  groom_address TEXT,
  witness1_name TEXT,
  witness2_name TEXT,
  remarks TEXT,
  created_at TIMESTAMP,
  updated_at TIMESTAMP,
  created_by TEXT,
  registry_number TEXT,
  book_number TEXT,
  page_number TEXT,
  line_number TEXT,
  PRIMARY KEY (parish_id, id)
);

CREATE TABLE IF NOT EXISTS confirmation_records (
  parish_id TEXT,
  id TEXT,
  name TEXT,
  age_or_dob TEXT,
  place_of_birth TEXT,
  father_name TEXT,
  mother_name TEXT,
  address TEXT,
  sponsor_name TEXT,
  date DATE,
  place TEXT,
  minister_name TEXT,
  remarks TEXT,
  created_at TIMESTAMP,
  updated_at TIMESTAMP,
  created_by TEXT,
  registry_number TEXT,
  book_number TEXT,
  page_number TEXT,
  line_number TEXT,
  PRIMARY KEY (parish_id, id)
);

CREATE TABLE IF NOT EXISTS death_records (
  parish_id TEXT,
  id TEXT,
  name TEXT,
  gender TEXT,
  age_or_dob TEXT,
  date_of_birth DATE,
  date DATE,
  place TEXT,
  place_of_death TEXT,
  cause_of_death TEXT,
  civil_status TEXT,
  religion TEXT,
  address TEXT,
  father_name TEXT,
  mother_name TEXT,
  spouse_name TEXT,
  informant_name TEXT,
  informant_relation TEXT,
  burial_date DATE,
  burial_place TEXT,
  minister_name TEXT,
  created_at TIMESTAMP,
  updated_at TIMESTAMP,
  created_by TEXT,
  registry_number TEXT,
  book_number TEXT,
  page_number TEXT,
  line_number TEXT,
  PRIMARY KEY (parish_id, id)
);

-- Request tables
CREATE TABLE IF NOT EXISTS baptism_request (
  parish_id TEXT,
  id TEXT,
  record_id TEXT,
  requester_name TEXT,
  status TEXT,
  requested_at TIMESTAMP,
  processed_at TIMESTAMP,
  processed_by TEXT,
  notification_sent BOOLEAN,
  PRIMARY KEY (parish_id, id)
);

CREATE TABLE IF NOT EXISTS marriage_request (
  parish_id TEXT,
  id TEXT,
  record_id TEXT,
  requester_name TEXT,
  status TEXT,
  requested_at TIMESTAMP,
  processed_at TIMESTAMP,
  processed_by TEXT,
  notification_sent BOOLEAN,
  PRIMARY KEY (parish_id, id)
);

CREATE TABLE IF NOT EXISTS confirmation_request (
  parish_id TEXT,
  id TEXT,
  record_id TEXT,
  requester_name TEXT,
  status TEXT,
  requested_at TIMESTAMP,
  processed_at TIMESTAMP,
  processed_by TEXT,
  notification_sent BOOLEAN,
  PRIMARY KEY (parish_id, id)
);

CREATE TABLE IF NOT EXISTS death_request (
  parish_id TEXT,
  id TEXT,
  record_id TEXT,
  requester_name TEXT,
  status TEXT,
  requested_at TIMESTAMP,
  processed_at TIMESTAMP,
  processed_by TEXT,
  notification_sent BOOLEAN,
  PRIMARY KEY (parish_id, id)
);
 
-- Certificate requests (staff & admin)
CREATE TABLE IF NOT EXISTS certificate_requests (
  parish_id TEXT,
  request_id TEXT,
  record_id TEXT,
  request_type TEXT,
  requester_name TEXT,
  status TEXT,
  requested_at TIMESTAMP,
  processed_at TIMESTAMP,
  processed_by TEXT,
  notification_sent BOOLEAN,
  PRIMARY KEY (parish_id, request_id)
);

-- Analytics
CREATE TABLE IF NOT EXISTS analytics (
  date DATE,
  metric_type TEXT,
  metric_name TEXT,
  value BIGINT,
  metadata TEXT,
  PRIMARY KEY (date, metric_type, metric_name)
) WITH CLUSTERING ORDER BY (metric_type ASC, metric_name ASC);

-- Certificate
CREATE TABLE IF NOT EXISTS certificate (
  id TEXT PRIMARY KEY,
  parish_id TEXT,
  record_type TEXT,
  record_id TEXT,
  certificate_number TEXT,
  issued_date TIMESTAMP,
  issued_by TEXT,
  recipient_name TEXT,
  recipient_email TEXT,
  purpose TEXT,
  status TEXT,
  pdf_path TEXT,
  created_at TIMESTAMP
);

-- Audit logs
CREATE TABLE IF NOT EXISTS audit_logs (
  id TEXT PRIMARY KEY,
  user_id TEXT,
  action TEXT,
  resource_type TEXT,
  resource_id TEXT,
  old_values TEXT,
  new_values TEXT,
  timestamp TIMESTAMP,
  ip_address TEXT,
  user_agent TEXT
);

-- Attachment
CREATE TABLE IF NOT EXISTS attachment (
  id TEXT PRIMARY KEY,
  record_type TEXT,
  record_id TEXT,
  filename TEXT,
  file_path TEXT,
  file_size BIGINT,
  mime_type TEXT,
  uploaded_by TEXT,
  uploaded_at TIMESTAMP
);

-- Notifications
CREATE TABLE IF NOT EXISTS notifications (
  id TEXT PRIMARY KEY,
  user_id TEXT,
  title TEXT,
  message TEXT,
  type TEXT,
  read BOOLEAN,
  created_at TIMESTAMP,
  expires_at TIMESTAMP
);
