# Initialize Parish Record Database Schema
# Run this after Cassandra is running

Write-Host "Initializing Parish Record Database..." -ForegroundColor Green

# Create the keyspace and tables
$cqlScript = @"
-- Create keyspace used by Cloud Functions (functions/src/api.ts)
CREATE KEYSPACE IF NOT EXISTS parish
WITH REPLICATION = {
    'class': 'SimpleStrategy',
    'replication_factor': 1
};

USE parish;

-- Users table (generic, for potential future use)
CREATE TABLE IF NOT EXISTS users (
    id UUID PRIMARY KEY,
    email TEXT,
    display_name TEXT,
    role TEXT,
    created_at TIMESTAMP,
    last_login TIMESTAMP,
    email_verified BOOLEAN
);

-- Core sacramental records used by /api/records
-- Baptism records
DROP TABLE IF EXISTS baptism_records;
CREATE TABLE IF NOT EXISTS baptism_records (
    parish_id TEXT,
    baptism_date TIMESTAMP,
    record_id UUID,
    person_name TEXT,
    birthdate DATE,
    parents TEXT,
    scanned_document_url TEXT,
    ocr_text TEXT,
    created_by TEXT,
    created_at TIMESTAMP,
    PRIMARY KEY ((parish_id), baptism_date, record_id)
) WITH CLUSTERING ORDER BY (baptism_date DESC, record_id DESC);

-- Marriage records
DROP TABLE IF EXISTS marriage_records;
CREATE TABLE IF NOT EXISTS marriage_records (
    parish_id TEXT,
    marriage_date TIMESTAMP,
    record_id UUID,
    groom_name TEXT,
    bride_name TEXT,
    witness_names LIST<TEXT>,
    scanned_document_url TEXT,
    ocr_text TEXT,
    created_by TEXT,
    created_at TIMESTAMP,
    PRIMARY KEY ((parish_id), marriage_date, record_id)
) WITH CLUSTERING ORDER BY (marriage_date DESC, record_id DESC);

-- Confirmation records
DROP TABLE IF EXISTS confirmation_records;
CREATE TABLE IF NOT EXISTS confirmation_records (
    parish_id TEXT,
    confirmation_date TIMESTAMP,
    record_id UUID,
    person_name TEXT,
    sponsor_names LIST<TEXT>,
    scanned_document_url TEXT,
    ocr_text TEXT,
    created_by TEXT,
    created_at TIMESTAMP,
    PRIMARY KEY ((parish_id), confirmation_date, record_id)
) WITH CLUSTERING ORDER BY (confirmation_date DESC, record_id DESC);

-- Certificate requests used by /api/requests
DROP TABLE IF EXISTS certificate_requests;
CREATE TABLE IF NOT EXISTS certificate_requests (
    parish_id TEXT,
    request_id UUID,
    record_id UUID,
    request_type TEXT,
    requester_name TEXT,
    status TEXT,
    requested_at TIMESTAMP,
    processed_at TIMESTAMP,
    processed_by TEXT,
    notification_sent BOOLEAN,
    PRIMARY KEY ((parish_id), request_id)
) WITH CLUSTERING ORDER BY (request_id DESC);

-- User audit log used by /api/admin/logs
DROP TABLE IF EXISTS user_audit_log;
CREATE TABLE IF NOT EXISTS user_audit_log (
    parish_id TEXT,
    action_time TIMESTAMP,
    user_id TEXT,
    target_record_id UUID,
    action TEXT,
    details TEXT,
    PRIMARY KEY ((parish_id), action_time, user_id, target_record_id)
) WITH CLUSTERING ORDER BY (action_time DESC);
"@

# Write CQL script to temp file
$tempFile = [System.IO.Path]::GetTempFileName() + ".cql"
$cqlScript | Out-File -FilePath $tempFile -Encoding UTF8

try {
    Write-Host "Executing database schema..." -ForegroundColor Yellow
    Get-Content $tempFile | docker exec -i cassandra-parish cqlsh
    Write-Host "✅ Database schema created successfully!" -ForegroundColor Green
} catch {
    Write-Host "❌ Failed to create database schema: $_" -ForegroundColor Red
    exit 1
} finally {
    Remove-Item $tempFile -ErrorAction SilentlyContinue
}

Write-Host "🎉 Parish Record Database is ready!" -ForegroundColor Green
