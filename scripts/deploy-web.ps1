# Build the Flutter web app with the production backend URL and deploy it to
# Firebase Hosting (holyparish). Refuses to deploy a build that still points
# at localhost.
#   powershell -ExecutionPolicy Bypass -File scripts\deploy-web.ps1
# Native tools (flutter, firebase) write warnings to stderr; check $LASTEXITCODE instead of stopping on them.
$ErrorActionPreference = 'Continue'
Set-Location (Split-Path $PSScriptRoot -Parent)

flutter build web --release --dart-define-from-file=dart_define.json
if ($LASTEXITCODE -ne 0) { throw 'flutter build web failed' }

$js = Get-Content build\web\main.dart.js -Raw
if ($js.Contains('localhost:3000') -or -not $js.Contains('parishrecords-production.up.railway.app')) {
  throw 'Build does not point at the Railway backend - check dart_define.json. Not deployed.'
}

firebase deploy --only hosting --project holyparish --non-interactive
if ($LASTEXITCODE -ne 0) { throw 'firebase deploy failed' }
Write-Output 'DEPLOY OK'
