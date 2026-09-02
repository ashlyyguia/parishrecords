#!/usr/bin/env bash
#
# Start the CV grid service that the baptismal-OCR pipeline depends on.
#
# The Node backend is CV-first: it calls this service (OCR_SERVICE_URL) to
# detect the register's ruled grid and rectify the two pages, THEN runs OCR on
# those images. When this service is down the backend silently falls back to
# word-clustering on the raw photo, which mangles rotated / two-page / angled
# spreads. So this must be running alongside the backend for accurate scans.
#
# Usage (from anywhere):
#   ocr_service/scripts/start-ocr-service.sh            # port 8000, key dev-key
#   OCR_SERVICE_KEY=... PORT=8000 ocr_service/scripts/start-ocr-service.sh
#
# The key defaults to the value in backend/.env (dev-key) so the header the
# backend sends matches out of the box for local dev. Override for anything
# real.
set -euo pipefail

# Resolve ocr_service/ regardless of where the script is invoked from.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SERVICE_DIR="$(dirname "$SCRIPT_DIR")"
cd "$SERVICE_DIR"

# Windows venv puts the interpreter in Scripts/; POSIX puts it in bin/.
if [ -x ".venv310/Scripts/python.exe" ]; then
  PYTHON=".venv310/Scripts/python.exe"
elif [ -x ".venv310/bin/python" ]; then
  PYTHON=".venv310/bin/python"
else
  echo "error: no venv at ocr_service/.venv310 -- create it first:" >&2
  echo "  python -m venv .venv310 && .venv310/Scripts/python -m pip install -r requirements.txt" >&2
  exit 1
fi

export OCR_SERVICE_KEY="${OCR_SERVICE_KEY:-dev-key}"
PORT="${PORT:-8000}"

echo "Starting CV grid service on http://127.0.0.1:${PORT} (key: ${OCR_SERVICE_KEY})"
echo "Keep this window open while scanning. Ctrl+C to stop."
exec "$PYTHON" -m uvicorn app.main:app --host 127.0.0.1 --port "$PORT"
