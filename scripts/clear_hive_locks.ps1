# PowerShell script to clear Hive lock files
# Run this if you encounter Hive lock conflicts

Write-Host "🔧 Clearing Hive lock files..." -ForegroundColor Yellow

# Stop any running Flutter processes
Write-Host "⏹️ Stopping Flutter processes..." -ForegroundColor Cyan
try {
    Get-Process -Name "flutter" -ErrorAction SilentlyContinue | Stop-Process -Force
    Write-Host "✅ Flutter processes stopped" -ForegroundColor Green
} catch {
    Write-Host "ℹ️ No Flutter processes found" -ForegroundColor Blue
}

# Stop any running Parish Record processes
Write-Host "⏹️ Stopping Parish Record processes..." -ForegroundColor Cyan
try {
    Get-Process -Name "parishrecord" -ErrorAction SilentlyContinue | Stop-Process -Force
    Write-Host "✅ Parish Record processes stopped" -ForegroundColor Green
} catch {
    Write-Host "ℹ️ No Parish Record processes found" -ForegroundColor Blue
}

# Clear Hive lock files
Write-Host "🧹 Clearing Hive lock files..." -ForegroundColor Cyan
$lockFiles = Get-ChildItem -Path "$env:USERPROFILE\Documents" -Filter "*.lock" -ErrorAction SilentlyContinue
if ($lockFiles.Count -gt 0) {
    $lockFiles | Remove-Item -Force
    Write-Host "✅ Removed $($lockFiles.Count) lock files" -ForegroundColor Green
} else {
    Write-Host "ℹ️ No lock files found" -ForegroundColor Blue
}

# Clear Flutter build cache
Write-Host "🧹 Clearing Flutter build cache..." -ForegroundColor Cyan
Set-Location -Path (Split-Path -Parent $PSScriptRoot)
flutter clean | Out-Null
Write-Host "✅ Flutter cache cleared" -ForegroundColor Green

Write-Host "🎉 Hive lock cleanup completed!" -ForegroundColor Green
Write-Host "💡 You can now run 'flutter run' safely" -ForegroundColor Yellow
