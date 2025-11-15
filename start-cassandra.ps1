# Start Cassandra Database for Parish Record System
# Run this script as Administrator

Write-Host "Starting Cassandra Database..." -ForegroundColor Green

# Check if Docker is running
$dockerRunning = docker info 2>$null
if (-not $dockerRunning) {
    Write-Host "Starting Docker Desktop..." -ForegroundColor Yellow
    Start-Process "C:\Program Files\Docker\Docker\Docker Desktop.exe"
    Write-Host "Waiting for Docker to start..." -ForegroundColor Yellow
    Start-Sleep -Seconds 30
}

# Check if Cassandra container exists
$containerExists = docker ps -a --filter "name=cassandra-parish" --format "{{.Names}}"
if (-not $containerExists) {
    Write-Host "Creating new Cassandra container..." -ForegroundColor Yellow
    docker run --name cassandra-parish -p 9042:9042 -d cassandra:latest
    Write-Host "Waiting for Cassandra to initialize..." -ForegroundColor Yellow
    Start-Sleep -Seconds 60
} else {
    Write-Host "Starting existing Cassandra container..." -ForegroundColor Yellow
    docker start cassandra-parish
    Start-Sleep -Seconds 20
}

# Check if Cassandra is ready
Write-Host "Checking Cassandra connection..." -ForegroundColor Yellow
$maxAttempts = 10
$attempt = 0
do {
    $attempt++
    try {
        docker exec cassandra-parish cqlsh -e "DESCRIBE KEYSPACES;" | Out-Null
        Write-Host "✅ Cassandra is ready!" -ForegroundColor Green
        break
    } catch {
        Write-Host "Attempt $attempt/$maxAttempts - Waiting for Cassandra..." -ForegroundColor Yellow
        Start-Sleep -Seconds 10
    }
} while ($attempt -lt $maxAttempts)

if ($attempt -eq $maxAttempts) {
    Write-Host "❌ Failed to connect to Cassandra after $maxAttempts attempts" -ForegroundColor Red
    exit 1
}

Write-Host "🎉 Cassandra is running on localhost:9042" -ForegroundColor Green
Write-Host "Use 'docker exec -it cassandra-parish cqlsh' to access CQL shell" -ForegroundColor Cyan
