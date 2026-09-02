@echo off
REM Start the CV grid service the baptismal-OCR pipeline depends on.
REM Double-click this, or run it, and keep the window open while scanning.
REM The backend falls back to (inaccurate) word-clustering when this is down.

setlocal
cd /d "%~dp0.."

if not exist ".venv310\Scripts\python.exe" (
  echo error: no venv at ocr_service\.venv310 -- create it first:
  echo   python -m venv .venv310 ^&^& .venv310\Scripts\python -m pip install -r requirements.txt
  exit /b 1
)

if "%OCR_SERVICE_KEY%"=="" set OCR_SERVICE_KEY=dev-key
if "%PORT%"=="" set PORT=8000

echo Starting CV grid service on http://127.0.0.1:%PORT% (key: %OCR_SERVICE_KEY%)
echo Keep this window open while scanning. Ctrl+C to stop.
".venv310\Scripts\python.exe" -m uvicorn app.main:app --host 127.0.0.1 --port %PORT%
