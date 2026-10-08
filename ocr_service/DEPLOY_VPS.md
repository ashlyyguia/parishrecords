# Updating the CV grid service on the VPS

The VPS (`187.53.141.101:8000`) must run the **current** `ocr_service/` code.
An out-of-date copy is still "reachable", but it refuses most real register
photos. Measured on the sample photos in `attachments/`:

| Grid service | Baptismal (59) | Marriage (8) |
|---|---|---|
| VPS before this update | 7 | 0 |
| Current code (2.1.0) | 58 | 8 |

## 1. Copy the package to the VPS

From the project folder on your computer (PowerShell or Git Bash):

```bash
scp ocr_service/dist/ocr_service_2.1.0.zip root@187.53.141.101:/tmp/
```

## 2. Install it over the existing copy

SSH in (`ssh root@187.53.141.101`), then find where the service runs from:

```bash
ps -eo pid,args | grep -i "uvicorn app.main" | grep -v grep
sudo ls -l /proc/<PID>/cwd        # <PID> from the line above: this is the service folder
```

Replace the code in that folder (keep its `.env` with `OCR_SERVICE_KEY`):

```bash
cd <service folder>
cp -r app app.bak-$(date +%Y%m%d)          # backup of the old code
unzip -o /tmp/ocr_service_2.1.0.zip -d .   # overwrites app/ and requirements.txt
.venv/bin/pip install -r requirements.txt  # or the venv/python the service uses
```

## 3. Restart it

Use whichever way it was started:

- **systemd:** `sudo systemctl restart <service name>` (see `systemctl list-units | grep -i -E "ocr|uvicorn|grid"`)
- **pm2:** `pm2 restart <name>` (see `pm2 ls`)
- **screen/tmux or nohup:** stop the old process (`kill <PID>`) and start it again:
  `nohup .venv/bin/uvicorn app.main:app --host 0.0.0.0 --port 8000 > ocr.log 2>&1 &`

## 4. Check it

```bash
curl http://187.53.141.101:8000/health
```

It must show `"version":"2.1.0"` and `"registers":["baptismal","marriage"]`.
The backend also checks this at startup: the Railway deploy log shows
`🧩 [cv-grid] ... (version 2.1.0)` when it is current, and an
`OUT OF DATE` warning when it is not.
