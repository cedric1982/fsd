from flask import Flask, render_template, request, redirect, url_for, jsonify
from flask_socketio import SocketIO, emit
import psutil
import time
import os
import sqlite3
import json, os, time, threading

# === Konfiguration (relocatable) ===
from pathlib import Path

# app.py liegt in <base>/web/app.py  -> BASE_DIR ist <base>
BASE_DIR = Path(__file__).resolve().parent.parent

UNIX_DIR = BASE_DIR / "unix"
LOG_DIR = BASE_DIR / "logs"

FSD_PATH = UNIX_DIR / "fsd"
WHAZZUP_PATH = UNIX_DIR / "whazzup.txt"
DB_PATH = UNIX_DIR / "cert.sqlitedb3"

STATUS_FILE = LOG_DIR / "status.json"
last_mtime = 0

# Sicherstellen, dass Logs-Verzeichnis existiert
LOG_DIR.mkdir(parents=True, exist_ok=True)
last_mtime = 0

# -------------------------------------------------------------------
# Dashboard (wird nur einmal geladen – danach WebSocket live updates)
# -------------------------------------------------------------------
@app.route("/")
def index():
    return render_template("index.html")


# -------------------------------------------------------------------
# Datei-Watcher (überwacht status.json auf Änderungen)
# -------------------------------------------------------------------
def watch_status_file():
    global last_mtime
    while True:
        if STATUS_FILE.exists():
            mtime = STATUS_FILE.stat().st_mtime
            if mtime != last_mtime:
                last_mtime = mtime
                try:
                    with open(STATUS_FILE, "r") as f:
                        data = json.load(f)
                        socketio.emit("status_update", data)
                except Exception as e:
                    print("⚠️ Fehler beim Lesen von status.json:", e)
        time.sleep(2)


# -------------------------------------------------------------------
# SocketIO-Events
# -------------------------------------------------------------------
@socketio.on("connect")
def handle_connect():
    print("✅ WebSocket verbunden:", request.sid)
    if STATUS_FILE.exists():
        try:
            with open(STATUS_FILE, "r") as f:
                data = json.load(f)
                emit("status_update", data)
        except:
            pass






# === FSD-Prozessprüfung ===
def get_fsd_process():
    for proc in psutil.process_iter(['pid', 'name', 'cmdline']):
        try:
            if 'fsd' in proc.info['name'].lower():
                return proc
            if proc.info['cmdline'] and any('fsd' in cmd.lower() for cmd in proc.info['cmdline']):
                return proc
        except (psutil.NoSuchProcess, psutil.AccessDenied):
            continue
    return None


# === Whazzup.txt Parser ===
def parse_whazzup_clients():
    clients = []

    if not os.path.exists(WHAZZUP_PATH):
        print(f"⚠️ Datei nicht gefunden: {WHAZZUP_PATH}")
        return clients

    try:
        with open(WHAZZUP_PATH, "r", encoding="utf-8", errors="ignore") as f:
            lines = f.readlines()

        in_clients = False
        for line in lines:
            line = line.strip()
            if not line:
                continue

            if line.startswith("!CLIENTS"):
                in_clients = True
                continue
            elif line.startswith("!SERVERS"):
                break

            if in_clients and not line.startswith(";"):
                parts = line.split(":")

                if len(parts) < 8:
                    continue

                callsign = parts[0]
                cid = parts[1]
                realname = parts[2]

                if parts[3].upper() in ["PILOT", "ATC"]:
                    client_type = parts[3]
                    lat = parts[5]
                    lon = parts[6]
                    alt = parts[7] if len(parts) > 7 else "0"
                else:
                    client_type = "UNKNOWN"
                    lat = parts[4]
                    lon = parts[5]
                    alt = parts[6] if len(parts) > 6 else "0"

                clients.append({
                    "callsign": callsign,
                    "cid": cid,
                    "realname": realname,
                    "type": client_type,
                    "lat": lat,
                    "lon": lon,
                    "alt": alt
                })

        print(f"✅ {len(clients)} Clients erfolgreich geparst.")
        return clients

    except Exception as e:
        print(f"❌ Fehler beim Parsen von {WHAZZUP_PATH}: {e}")
        return clients


# === API ===
@app.route("/")

@app.route("/api/status")
def api_status():
    proc = get_fsd_process()

    if proc:
        try:
            pid = proc.pid
            create_time = proc.create_time()
            uptime_sec = time.time() - create_time
            uptime_min = int(uptime_sec // 60)
            status = "running"
        except Exception as e:
            status = f"error: {e}"
            pid = None
            uptime_min = 0
    else:
        status = "stopped"
        pid = None
        uptime_min = 0

    return jsonify({
        "status": status,
        "pid": pid,
        "uptime": f"{uptime_min} min"
    })


@app.route("/api/clients")
def api_clients():
    clients = parse_whazzup_clients()
    return jsonify(clients)

# --- Benutzer anzeigen ---
@app.route("/users")
def users():
    conn = sqlite3.connect(str(DB_PATH))
    c = conn.cursor()
    c.execute("CREATE TABLE IF NOT EXISTS cert (callsign TEXT PRIMARY KEY NOT NULL, password TEXT NOT NULL, level INT NOT NULL)")
    c.execute("SELECT * FROM cert")
    users = c.fetchall()
    conn.close()
    return render_template("users.html", users=users)

# --- Benutzer hinzufügen ---
@app.route("/add_user", methods=["POST"])
def add_user():
    callsign = request.form["callsign"].strip().upper()
    password = request.form["password"].strip()
    level = int(request.form["level"])

    conn = sqlite3.connect(str(DB_PATH))
    c = conn.cursor()
    c.execute("INSERT OR REPLACE INTO cert (callsign, password, level) VALUES (?, ?, ?)", (callsign, password, level))
    conn.commit()
    conn.close()
    return redirect(url_for("users"))

# --- Benutzer löschen ---
@app.route("/delete_user/<callsign>")
def delete_user(callsign):
    conn = sqlite3.connect(str(DB_PATH))
    c = conn.cursor()
    c.execute("DELETE FROM cert WHERE callsign = ?", (callsign,))
    conn.commit()
    conn.close()
    return redirect(url_for("users"))


# -------------------------------------------------------------------
# Start des Servers + Hintergrund-Thread
# -------------------------------------------------------------------
if __name__ == "__main__":
    watcher_thread = threading.Thread(target=watch_status_file, daemon=True)
    watcher_thread.start()
    print("🚀 Flask-SocketIO Server läuft auf Port 8080")
    socketio.run(app, host="0.0.0.0", port=8080, debug=False)
