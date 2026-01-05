import eventlet
eventlet.monkey_patch()
from flask import Flask, render_template, request, redirect, url_for, jsonify
from flask_socketio import SocketIO, emit
import psutil
import time
import os
import sqlite3
import json
import threading
from pathlib import Path

# --------------------------------------------------------
# KONFIG
# -------------------------------------------------------

# app.py liegt in <base>/web/app.py  -> BASE_DIR ist <base>
BASE_DIR = Path(__file__).resolve().parent.parent

UNIX_DIR = BASE_DIR / "unix"
LOG_DIR = BASE_DIR / "logs"

FSD_PATH = UNIX_DIR / "fsd"
WHAZZUP_PATH = UNIX_DIR / "whazzup.txt"
DB_PATH = UNIX_DIR / "cert.sqlitedb3"
STATUS_FILE = LOG_DIR / "status.json"

LOG_DIR.mkdir(parents=True, exist_ok=True)
last_mtime = 0


app = Flask(__name__)
socketio = SocketIO(app, cors_allowed_origins="*")

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
    emit("fsd_status", get_fsd_status_payload())
    if STATUS_FILE.exists():
        try:
            with open(STATUS_FILE, "r") as f:
                data = json.load(f)
                emit("status_update", data)
        except:
            pass






# === FSD-Prozessprüfung ===
def get_fsd_process():
    target = os.path.realpath(str(FSD_PATH))

    for proc in psutil.process_iter(['pid', 'exe', 'cmdline']):
        try:
            exe = proc.info.get('exe')
            cmd = proc.info.get('cmdline')

            # 1) sauberster Fall: exe-Pfad stimmt exakt
            if exe and os.path.realpath(exe) == target:
                return proc

            # 2) Fallback: erstes cmdline-Argument ist das Binary
            if cmd and len(cmd) > 0 and os.path.realpath(cmd[0]) == target:
                return proc

        except (psutil.NoSuchProcess, psutil.AccessDenied):
            continue
        except Exception:
            continue

    return None


def get_fsd_status_payload():
    proc = get_fsd_process()
    if not proc:
        return {"status": "stopped", "pid": None, "uptime_sec": 0}

    try:
        pid = proc.pid
        uptime_sec = int(time.time() - proc.create_time())
        return {"status": "running", "pid": pid, "uptime_sec": uptime_sec}
    except Exception as e:
        return {"status": f"error: {e}", "pid": None, "uptime_sec": 0}


def status_broadcaster():
    # Sendet kontinuierlich Live-Status an alle verbundenen Clients
    while True:
        socketio.emit("fsd_status", get_fsd_status_payload())
        socketio.sleep(1)  # eventlet-/gevent-freundlich




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
@app.route("/api/status")
def api_status():
    proc = get_fsd_process()

    if proc:
        try:
            pid = proc.pid
            uptime_sec = int(time.time() - proc.create_time())
            return jsonify({
                "status": "running",
                "pid": pid,
                "uptime_sec": uptime_sec
            })
        except Exception as e:
            return jsonify({
                "status": f"error: {e}",
                "pid": None,
                "uptime_sec": 0
            })
    else:
        return jsonify({
            "status": "stopped",
            "pid": None,
            "uptime_sec": 0
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
    c.execute("CREATE TABLE IF NOT EXISTS cert (cid TEXT PRIMARY KEY NOT NULL, callsign TEXT PRIMARY KEY NOT NULL, password TEXT NOT NULL, level INT NOT NULL)")
    c.execute("SELECT * FROM cert")
    users = c.fetchall()
    conn.close()
    return render_template("users.html", users=users)

# --- Benutzer hinzufügen ---
@app.route("/add_user", methods=["POST"])
def add_user():
    cid = request.form["cid"].strip()
    callsign = request.form["callsign"].strip().upper()
    password = request.form["password"].strip()
    level = int(request.form["level"])

    conn = sqlite3.connect(str(DB_PATH))
    c = conn.cursor()
    c.execute("INSERT OR REPLACE INTO cert (cid, callsign, password, level) VALUES (?, ?, ?)", (cid, callsign, password, level))
    conn.commit()
    conn.close()
    return redirect(url_for("users"))

# --- Benutzer löschen ---
@app.route("/delete_user/<cid>")
def delete_user(callsign):
    conn = sqlite3.connect(str(DB_PATH))
    c = conn.cursor()
    c.execute("DELETE FROM cert WHERE cid = ?", (callsign,))
    conn.commit()
    conn.close()
    return redirect(url_for("users"))


# -------------------------------------------------------------------
# Start des Servers + Hintergrund-Thread
# -------------------------------------------------------------------
if __name__ == "__main__":
    socketio.start_background_task(watch_status_file)
    socketio.start_background_task(status_broadcaster)

    print("🚀 Flask-SocketIO Server läuft auf Port 8080")
    socketio.run(app, host="0.0.0.0", port=8080, debug=False)
