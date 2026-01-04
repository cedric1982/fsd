from flask import Flask, render_template, jsonify
import os, psutil, time, logging

# Flask-Logs unterdrücken
log = logging.getLogger('werkzeug')
log.setLevel(logging.ERROR)
log.disabled = True

app = Flask(__name__)

# === Pfade ===
BASE_PATH = "/home/cedric1982/fsd"
WHAZZUP_PATH = os.path.join(BASE_PATH, "unix/whazzup.txt")
FSD_PATH = os.path.join(BASE_PATH, "unix/fsd")

# === FSD-Prozess finden ===
def get_fsd_process():
    for proc in psutil.process_iter(['pid', 'name', 'cmdline']):
        try:
            if 'fsd' in proc.info['name'] or (
                proc.info['cmdline'] and FSD_PATH in " ".join(proc.info['cmdline'])
            ):
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
            if line.startswith("!CLIENTS"):
                in_clients = True
                continue
            if line.startswith("!SERVERS"):
                break
            if in_clients and line and not line.startswith("!"):
                parts = line.split(":")
                if len(parts) >= 7:
                    clients.append({
                        "callsign": parts[0],
                        "cid": parts[1],
                        "name": parts[2],
                        "lat": parts[4],
                        "lon": parts[5],
                        "alt": parts[6]
                    })
        print(f"✅ Insgesamt {len(clients)} Clients gefunden.")
        return clients

    except Exception as e:
        print(f"❌ Fehler beim Parsen von whazzup.txt: {e}")
        return clients

# === API ===
@app.route("/")
def index():
    return render_template("index.html")

@app.route("/api/status")
def api_status():
    proc = get_fsd_process()
    status = {
        "running": bool(proc),
        "pid": proc.pid if proc else None,
        "uptime": int(time.time() - proc.create_time()) if proc else 0,
    }
    return jsonify(status)

@app.route("/api/clients")
def api_clients():
    return jsonify(parse_whazzup_clients())

# === Start ===
if __name__ == "__main__":
    print("🚀 Flask-Webserver läuft auf Port 8080 ...")
    app.run(host="0.0.0.0", port=8080)
