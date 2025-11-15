# Initialize Parish Record Database Schema
# Run this after Cassandra is running

Write-Host "Initializing Parish Record Database..." -ForegroundColor Green

# Create the keyspace and tables
$cqlScript = @"
-- Create keyspace
CREATE KEYSPACE IF NOT EXISTS parish_records 
WITH REPLICATION = {
    'class': 'SimpleStrategy',
    'replication_factor': 1
};

USE parish_records;

-- Users table
CREATE TABLE IF NOT EXISTS users (
    id UUID PRIMARY KEY,
    email TEXT,
    display_name TEXT,
    role TEXT,
    created_at TIMESTAMP,
    last_login TIMESTAMP,
    email_verified BOOLEAN
);

-- Parish records table
CREATE TABLE IF NOT EXISTS records (
    id UUID PRIMARY KEY,
    type TEXT,
    name TEXT,
    date_of_event DATE,
    place_of_event TEXT,
    notes TEXT,
    certificate_status TEXT,
    created_by UUID,
    created_at TIMESTAMP,
    updated_at TIMESTAMP
);

-- Baptism records
CREATE TABLE IF NOT EXISTS baptism_records (
    id UUID PRIMARY KEY,
    registry_no TEXT,
    book_no TEXT,
    page_no TEXT,
    line_no TEXT,
    child_name TEXT,
    child_gender TEXT,
    date_of_birth DATE,
    place_of_birth TEXT,
    father_name TEXT,
    mother_name TEXT,
    godfather_name TEXT,
    godmother_name TEXT,
    minister_name TEXT,
    date_of_baptism DATE,
    place_of_baptism TEXT,
    certificate_issued BOOLEAN,
    created_by UUID,
    created_at TIMESTAMP
);

-- Marriage records
CREATE TABLE IF NOT EXISTS marriage_records (
    id UUID PRIMARY KEY,
    registry_no TEXT,
    groom_name TEXT,
    bride_name TEXT,
    date_of_marriage DATE,
    place_of_marriage TEXT,
    witness1_name TEXT,
    witness2_name TEXT,
    minister_name TEXT,
    certificate_issued BOOLEAN,
    created_by UUID,
    created_at TIMESTAMP
);

-- Confirmation records
CREATE TABLE IF NOT EXISTS confirmation_records (
    id UUID PRIMARY KEY,
    registry_no TEXT,
    confirmed_name TEXT,
    date_of_confirmation DATE,
    place_of_confirmation TEXT,
    sponsor_name TEXT,
    minister_name TEXT,
    certificate_issued BOOLEAN,
    created_by UUID,
    created_at TIMESTAMP
);

-- Death records
CREATE TABLE IF NOT EXISTS death_records (
    id UUID PRIMARY KEY,
    registry_no TEXT,
    deceased_name TEXT,
    date_of_death DATE,
    place_of_death TEXT,
    cause_of_death TEXT,
    age_at_death INT,
    burial_date DATE,
    burial_place TEXT,
    certificate_issued BOOLEAN,
    created_by UUID,
    created_at TIMESTAMP
);

-- Certificate requests
CREATE TABLE IF NOT EXISTS certificate_requests (
    id UUID PRIMARY KEY,
    record_type TEXT,
    record_id UUID,
    requester_name TEXT,
    requester_contact TEXT,
    purpose TEXT,
    status TEXT,
    requested_at TIMESTAMP,
    processed_at TIMESTAMP,
    processed_by UUID
);

-- Audit log
CREATE TABLE IF NOT EXISTS audit_log (
    id UUID PRIMARY KEY,
    user_id UUID,
    action TEXT,
    table_name TEXT,
    record_id UUID,
    old_values TEXT,
    new_values TEXT,
    timestamp TIMESTAMP
);
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
