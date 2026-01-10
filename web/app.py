import eventlet
eventlet.monkey_patch()
from flask import Flask, render_template, request, redirect, url_for, jsonify, session
from functools import wraps
from werkzeug.security import check_password_hash
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

LIVE_CACHE_LOCK = threading.Lock()
LIVE_CACHE = {"clients": [], "ts": 0}


app = Flask(__name__)
# Session benötigt secret_key (bitte nicht leer lassen)
app.secret_key = os.environ.get("FSD_WEB_SECRET", "fgsdhfdstj56u5h4h3nrgh4h")

AUTH_FILE = BASE_DIR / "web" / "admin_auth.json"

app.config.update(
    SESSION_COOKIE_HTTPONLY=True,
    SESSION_COOKIE_SAMESITE="Lax",
    SESSION_COOKIE_SECURE=True,  # funktioniert bei HTTPS (Nginx)
)

def load_admin_hash():
    try:
        with open(AUTH_FILE, "r", encoding="utf-8") as f:
            return json.load(f).get("admin_password_hash")
    except Exception:
        return None

def require_admin(view):
    @wraps(view)
    def wrapped(*args, **kwargs):
        if not session.get("is_admin"):
            return render_template("auth_gate.html", next=request.path), 401
        return view(*args, **kwargs)
    return wrapped


socketio = SocketIO(app, cors_allowed_origins="*")


# ------------------
# Live Cache
# ------------------

LIVE_CACHE_LOCK = threading.Lock()
LIVE_CACHE = {
    "clients": [],
    "ts": 0,
    "bot": {"connected": False, "since": None},
}




# -------------------------------------------------------------------
# Dashboard (wird nur einmal geladen – danach WebSocket live updates)
# -------------------------------------------------------------------
@app.route("/")
def index():
    return render_template("index.html")



## @app.route("/auth", methods=["POST"])
## def auth():
##    data = request.get_json(silent=True) or {}
##    pw = (data.get("password") or "").strip()
##    next_url = (data.get("next") or "/users").strip()

##    stored_hash = load_admin_hash()
##    if not stored_hash:
##        return jsonify({"ok": False, "error": "Admin-Passwort nicht konfiguriert"}), 500

##    if not check_password_hash(stored_hash, pw):
##        return jsonify({"ok": False, "error": "Falsches Passwort"}), 401

##    session["is_admin"] = True
##    return jsonify({"ok": True, "next": next_url})

@app.route("/logout")
def logout():
    session.pop("is_admin", None)
    return redirect(url_for("index"))


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
            with LIVE_CACHE_LOCK:
                emit("live_clients", LIVE_CACHE)
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

    # Systemwerte (Host)
    try:
        cpu_pct = psutil.cpu_percent(interval=None)  # non-blocking; "letztes Intervall"
        vm = psutil.virtual_memory()
        ram_pct = vm.percent
        ram_used_mb = int(vm.used / (1024 * 1024))
        ram_total_mb = int(vm.total / (1024 * 1024))
    except Exception:
        cpu_pct = None
        ram_pct = None
        ram_used_mb = None
        ram_total_mb = None

    if not proc:
        return {
            "status": "stopped",
            "pid": None,
            "uptime_sec": 0,
            "cpu_percent": cpu_pct,
            "ram_percent": ram_pct,
            "ram_used_mb": ram_used_mb,
            "ram_total_mb": ram_total_mb,
        }

    try:
        pid = proc.pid
        uptime_sec = int(time.time() - proc.create_time())
        return {
            "status": "running",
            "pid": pid,
            "uptime_sec": uptime_sec,
            "cpu_percent": cpu_pct,
            "ram_percent": ram_pct,
            "ram_used_mb": ram_used_mb,
            "ram_total_mb": ram_total_mb,
        }
    except Exception as e:
        return {
            "status": f"error: {e}",
            "pid": None,
            "uptime_sec": 0,
            "cpu_percent": cpu_pct,
            "ram_percent": ram_pct,
            "ram_used_mb": ram_used_mb,
            "ram_total_mb": ram_total_mb,
        }


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


LIVE_PUSH_TOKEN = os.environ.get("FSD_PUSH_TOKEN", "my-super-secret-token")

@app.route("/api/live_update", methods=["POST"])
def api_live_update():
    token = request.headers.get("X-FSD-Token", "")
    if token != LIVE_PUSH_TOKEN:
        return jsonify({"ok": False, "error": "unauthorized"}), 401

    data = request.get_json(silent=True) or {}

    # Defaults, damit Frontend immer stabile Felder hat
    if "clients" not in data or not isinstance(data.get("clients"), list):
        data["clients"] = []
    if "ts" not in data:
        data["ts"] = int(time.time())
    if "bot" not in data or not isinstance(data.get("bot"), dict):
        data["bot"] = {"connected": False, "since": None}
    else:
        data["bot"].setdefault("connected", False)
        data["bot"].setdefault("since", None)

    # Cache aktualisieren
    with LIVE_CACHE_LOCK:
        LIVE_CACHE["clients"] = data["clients"]
        LIVE_CACHE["ts"] = data["ts"]
        LIVE_CACHE["bot"] = data["bot"]

    # Broadcast an alle Dashboards
    socketio.emit("live_clients", data)
    return jsonify({"ok": True})


# --- Karte hinzugefügt ---
@app.route("/map")
def map_view():
    return render_template("map.html")

# --- snapshot für karte ---
@app.route("/api/live_snapshot")
def api_live_snapshot():
    with LIVE_CACHE_LOCK:
        return jsonify(LIVE_CACHE)


# --- Benutzer anzeigen ---
@app.route("/users")
# @require_admin
def users():
    conn = sqlite3.connect(DB_PATH)
    c = conn.cursor()

    c.execute("""
        CREATE TABLE IF NOT EXISTS cert (
            cid TEXT PRIMARY KEY NOT NULL,
            password TEXT NOT NULL,
            level INT NOT NULL,
            twitch_name TEXT
        )
    """)

    c.execute("SELECT cid, password, level, twitch_name FROM cert ORDER BY CAST(cid AS INTEGER)")
    users = c.fetchall()

    c.execute("SELECT MAX(CAST(cid AS INTEGER)) FROM cert")
    max_cid = c.fetchone()[0]
    BASE_CID = 1000001
    next_cid = max(BASE_CID, (max_cid or 0) + 1)
    c.execute("SELECT cid, password, level, twitch_name FROM cert WHERE CAST(cid AS INTEGER) != 1 ORDER BY CAST(cid AS INTEGER)")

    conn.close()

    return render_template(
        "users.html",
        users=users,
        next_cid=next_cid
    )


# --- Benutzer hinzufügen ---
@app.route("/add_user", methods=["POST"])
# @require_admin
def add_user():
    cid = request.form.get("cid", "").strip()
    password = request.form.get("password", "").strip()
    levelraw = request.form.get("level", "1").strip()
    twitch_name = request.form.get("twitch_name", "").strip()

    if not cid or not password:
        return "Missing cid or password", 400

    try:
        level = int(levelraw)
    except ValueError:
        return "Invalid level", 400

    conn = sqlite3.connect(str(DB_PATH))
    c = conn.cursor()
    c.execute(
        "INSERT OR REPLACE INTO cert (cid, password, level, twitch_name) VALUES (?, ?, ?, ?)",
        (cid, password, level, twitch_name)
    )
    conn.commit()
    conn.close()

    return redirect(url_for("users"))


# --- Benutzer löschen ---
@app.route("/delete_user/<cid>")
# @require_admin
def delete_user(cid):
    conn = sqlite3.connect(DB_PATH)
    c = conn.cursor()
    c.execute("DELETE FROM cert WHERE cid = ?", (cid,))
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
