#!/usr/bin/env python3
import os
import time
import json
import socket
import threading
import urllib.request
import urllib.error

FSD_HOST = os.environ.get("FSD_HOST", "127.0.0.1")
FSD_PORT = int(os.environ.get("FSD_PORT", "6809"))

# Flask läuft bei dir intern auf 8080
PUSH_URL = os.environ.get("FSD_PUSH_URL", "http://127.0.0.1:8080/api/live_update")

# Shared Secret, damit nicht jeder im LAN deine Live-API spammen kann
PUSH_TOKEN = os.environ.get("FSD_PUSH_TOKEN", "CHANGE_ME")

# Sende-Intervall (Sekunden)
PUSH_INTERVAL = float(os.environ.get("FSD_PUSH_INTERVAL", "1.0"))

# Wenn dein FSD ein Login erwartet, kann man hier eine Zeile konfigurieren (optional)
# Beispiel (falls nötig): "X:OBSERVER:7000000:SERVER:0:0\r\n"
LOGIN_LINE = os.environ.get("FSD_LOGIN_LINE", "").strip()

def parse_position_line(line: str):
    """
    Erwartetes Format (aus deinem tcpdump ableitbar):
      @CALLSIGN:CID:TYPE:LAT:LON:ALT:GS:HDG:VS

    Wir sind robust: falls irgendwo im Text ein '@' vorkommt, schneiden wir davor ab.
    """
    if "@" not in line:
        return None
    line = line[line.find("@"):]  # ab dem '@'
    line = line.strip()

    if not line.startswith("@"):
        return None

    parts = line[1:].split(":")
    if len(parts) < 9:
        return None

    callsign = parts[0].strip()
    cid = parts[1].strip()
    ctype = parts[2].strip()

    try:
        lat = float(parts[3])
        lon = float(parts[4])
        alt = int(float(parts[5]))
        gs = int(float(parts[6]))
        hdg_raw = int(float(parts[7]))
        vs = int(float(parts[8]))
    except ValueError:
        return None

    # In FSD sieht heading oft skaliert aus (bei dir z.B. 405169860)
    # Daher zusätzlich eine "best guess" Umrechnung:
    hdg_deg = None
    if hdg_raw > 360:
        hdg_deg = round(hdg_raw / 1_000_000.0, 2)
    else:
        hdg_deg = float(hdg_raw)

    return {
        "callsign": callsign,
        "cid": cid,
        "type": ctype,
        "lat": lat,
        "lon": lon,
        "alt": alt,
        "gs": gs,
        "hdg_raw": hdg_raw,
        "hdg_deg": hdg_deg,
        "vs": vs,
        "ts": int(time.time())
    }

def http_post_json(url: str, token: str, payload: dict):
    data = json.dumps(payload).encode("utf-8")
    req = urllib.request.Request(
        url=url,
        data=data,
        method="POST",
        headers={
            "Content-Type": "application/json",
            "X-FSD-Token": token
        }
    )
    with urllib.request.urlopen(req, timeout=2) as resp:
        return resp.status

class LiveObserver:
    def __init__(self):
        self.clients = {}
        self.lock = threading.Lock()
        self.last_push = 0.0

    def update_client(self, obj):
        with self.lock:
            self.clients[obj["callsign"]] = obj

    def snapshot(self):
        with self.lock:
            # als Liste rausgeben (praktischer fürs Frontend)
            return list(self.clients.values())

    def push_loop(self):
        while True:
            now = time.time()
            if (now - self.last_push) >= PUSH_INTERVAL:
                payload = {"clients": self.snapshot(), "ts": int(now)}
                try:
                    http_post_json(PUSH_URL, PUSH_TOKEN, payload)
                except Exception as e:
                print(f"[observer] push failed: {e}")
                self.last_push = now
            time.sleep(0.05)

    def run(self):
        # Push-Thread starten
        threading.Thread(target=self.push_loop, daemon=True).start()

        backoff = 1
        while True:
            try:
                print(f"[observer] connecting to {FSD_HOST}:{FSD_PORT} ...")
                sock = socket.create_connection((FSD_HOST, FSD_PORT), timeout=5)
                sock.settimeout(10)

                if LOGIN_LINE:
                    # optionaler Login
                    sock.sendall((LOGIN_LINE + "\r\n").encode("utf-8", errors="ignore"))

                print("[observer] connected.")
                backoff = 1

                buf = b""
                while True:
                    chunk = sock.recv(4096)
                    if not chunk:
                        raise ConnectionError("socket closed")

                    buf += chunk
                    # zeilenweise verarbeiten (FSD nutzt meist \r\n)
                    while b"\n" in buf:
                        line, buf = buf.split(b"\n", 1)
                        s = line.decode("utf-8", errors="ignore").strip()
                        if not s:
                            continue
                        if "@" in s:
                            obj = parse_position_line(s)
                            if obj:
                                self.update_client(obj)

            except Exception as e:
                print(f"[observer] disconnected: {e}. retry in {backoff}s")
                time.sleep(backoff)
                backoff = min(backoff * 2, 30)

if __name__ == "__main__":
    LiveObserver().run()
