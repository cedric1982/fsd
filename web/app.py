from flask import Flask, render_template, jsonify
import psutil
import subprocess
import time
import os

app = Flask(__name__)

# Feste Pfade (bitte anpassen, falls du andere nutzt)
FSD_PATH = "/fsd/unix/fsd"
WHAZZUP_PATH = "/fsd/unix/whazzup.txt"
CONF_PATH = "/fsd/unix/fsd.conf"


def get_fsd_process():
    """Prüft, ob der FSD-Prozess aktiv ist."""
    for proc in psutil.process_iter(['pid', 'name', 'cmdline']):
        try:
            if 'fsd' in proc.info['name'] or (
                proc.info['cmdline'] and FSD_PATH in " ".join(proc.info['cmdline'])
            ):
                return proc
        except (psutil.NoSuchProcess, psutil.AccessDenied):
            continue
    return None


def parse_whazzup_clients():
    """Parst die !CLIENTS-Sektion aus whazzup.txt und gibt Debug-Infos aus"""
    clients = []
    if not os.path.exists(WHAZZUP_PATH):
        print("❌ whazzup.txt wurde nicht gefunden unter:", WHAZZUP_PATH)
        return clients

    with open(WHAZZUP_PATH, 'r', encoding='utf-8', errors='ignore') as f:
        lines = f.readlines()

    in_clients = False
    print("📡 Starte Parsing von whazzup.txt...")
    for line in lines:
        line = line.strip()
        if not line:
            continue

        # Starte Clients-Sektion
        if line.startswith("!CLIENTS:"):
            in_clients = True
            print("➡️  !CLIENTS-Sektion erkannt")
            continue

        # Beende Clients-Sektion bei neuer Kategorie
        if in_clients and line.startswith("!"):
            print("⛔ Ende der Clients-Sektion erreicht.")
            break

        # Wenn innerhalb der Clients-Sektion
        if in_clients:
            parts = line.split(":")
            if len(parts) < 8:
                print("⚠️  Überspringe unvollständige Zeile:", line)
                continue

            callsign = parts[0]
            client_type = parts[4] if len(parts) > 4 else "?"
            lat = parts[5] if len(parts) > 5 else "?"
            lon = parts[6] if len(parts) > 6 else "?"
            alt = parts[7] if len(parts) > 7 else "?"

            clients.append({
                "callsign": callsign,
                "type": client_type,
                "lat": lat,
                "lon": lon,
                "alt": alt
            })
            print(f"✅ Client erkannt: {callsign}, Typ: {client_type}, Pos: ({lat}, {lon})")

    print(f"🔍 Insgesamt {len(clients)} Clients gefunden.")
    return clients



@app.route("/")
def index():
    return render_template("index.html")


@app.route("/api/status")
def api_status():
    proc = get_fsd_process()
    if proc:
        uptime = time.time() - proc.create_time()
        return jsonify({
            "status": "running",
            "pid": proc.pid,
            "uptime": f"{int(uptime // 60)} min"
        })
    else:
        return jsonify({"status": "stopped"})


@app.route("/api/clients")
def api_clients():
    return jsonify(parse_whazzup_clients())


@app.route("/api/restart", methods=["POST"])
def api_restart():
    proc = get_fsd_process()
    if proc:
        proc.terminate()
        proc.wait(timeout=5)
    subprocess.Popen([FSD_PATH])
    return jsonify({"message": "✅ Server wurde neu gestartet."})


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8080)
