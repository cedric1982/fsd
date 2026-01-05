from flask import Flask, render_template, jsonify
import psutil
import time
import os

# === Konfiguration ===
FSD_PATH = "/home/cedric1982/fsd/unix/fsd"
WHAZZUP_PATH = "/home/cedric1982/fsd/unix/whazzup.txt"

app = Flask(__name__)

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
def index():
    return render_template("index.html")


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


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8080)
