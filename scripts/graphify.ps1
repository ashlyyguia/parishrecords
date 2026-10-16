# Rebuild the code map in graphify-out/ (open graphify-out\graph.html).
# Code only: runs locally, sends nothing to an LLM. What it may read is
# limited by .gitignore and .graphifyignore (no register photos, scans,
# OCR fixtures, or secrets).
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root
$py = Join-Path $root '.graphify-venv\Scripts\python.exe'
if (-not (Test-Path $py)) {
    python -m venv .graphify-venv
    & $py -m pip install -q graphifyy
}
$env:PYTHONIOENCODING = 'utf-8'
& $py -m graphify extract . --code-only
& $py -m graphify cluster-only . --no-label
Write-Host "Done. Open graphify-out\graph.html or read graphify-out\GRAPH_REPORT.md"
