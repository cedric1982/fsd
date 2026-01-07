#!/usr/bin/env python3
import os
import time
import json
import socket
import threading
import urllib.request
import urllib.error
import math

FSD_HOST = os.environ.get("FSD_HOST", "127.0.0.1")
FSD_PORT = int(os.environ.get("FSD_PORT", "6809"))

# Flask läuft bei dir intern auf 8080
PUSH_URL = os.environ.get("FSD_PUSH_URL", "http://127.0.0.1:8080/api/live_update")

# Shared Secret, damit nicht jeder im LAN deine Live-API spammen kann
PUSH_TOKEN = os.environ.get("FSD_PUSH_TOKEN", "my-super-secret-token")

# Sende-Intervall (Sekunden)
PUSH_INTERVAL = float(os.environ.get("FSD_PUSH_INTERVAL", "1.0"))

# Wenn dein FSD ein Login erwartet, kann man hier eine Zeile konfigurieren (optional)
# Beispiel (falls nötig): "X:OBSERVER:7000000:SERVER:0:0\r\n"
LOGIN_LINE = os.environ.get("FSD_LOGIN_LINE", "").strip()


# -------------------------------------------------------------------
# PBH Decoder
# Swift-kompatibel: swift::core::fsd::unpackPBH semantics
# -------------------------------------------------------------------
PITCH_MULT = 256.0 / 90.0
BANK_MULT  = 512.0 / 180.0
HDG_MULT   = 1024.0 / 360.0

def sign_extend_10bit(x: int) -> int:
    """Convert 10-bit two's complement integer to Python int."""
    x &= 0x3FF
    return x - 0x400 if (x & 0x200) else x

def unpack_pbh(pbh_u32: int) -> dict:
    """
    Decode Swift PBH uint32 into (pitch_deg, bank_deg, heading_deg, on_ground)
    following swift::core::fsd::unpackPBH semantics.
    """
    pbh = pbh_u32 & 0xFFFFFFFF

    unused    = (pbh >> 0) & 0x1
    onground  = (pbh >> 1) & 0x1
    hdg_raw   = (pbh >> 2) & 0x3FF
    bank_raw  = sign_extend_10bit((pbh >> 12) & 0x3FF)
    pitch_raw = sign_extend_10bit((pbh >> 22) & 0x3FF)

    # Swift uses qFloor on the division results for pitch/bank
    pitch_deg = math.floor(pitch_raw / -PITCH_MULT)
    bank_deg  = math.floor(bank_raw  / -BANK_MULT)
    heading_deg = hdg_raw / HDG_MULT  # == hdg_raw * 360 / 1024

    return {
        "pbh_u32": pbh,
        "unused": unused,
        "on_ground": bool(onground),
        "hdg_raw": hdg_raw,
        "bank_raw": bank_raw,
        "pitch_raw": pitch_raw,
        "heading_deg": heading_deg,
        "heading_deg_rounded": int(round(heading_deg)) % 360,
        "pitch_deg": pitch_deg,
        "bank_deg": bank_deg,
    }


def parse_position_line(line: str):
    """
    Erwartetes Format (aus deinem tcpdump ableitbar):
      @CALLSIGN:SQUAWK:TYPE:LAT:LON:ALT:GS:PBH

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
    squak = parts[1].strip()
    ctype = parts[2].strip()

    try:
        lat = float(parts[3])
        lon = float(parts[4])
        alt = int(float(parts[5]))
        gs = int(float(parts[6]))
        pbh_raw = int(float(parts[7]))
        vs = int(float(parts[8]))
    except ValueError:
        return None

   # PBH decodirern
    decoded = unpack_pbh(pbh_raw)

    return {
        "callsign": callsign,
        "squawk": squawk,
        "type": ctype,
        "lat": lat,
        "lon": lon,
        "alt": alt,
        "gs": gs,
        "vs": vs,

        # decodirern
        "pbh_u32": decoded["pbh_u32"],
        "hdg_deg": round(decoded["heading_deg"], 2),
        "hdg_deg_round": decoded["heading_deg_rounded"],
        "pitch_deg": decoded["pitch_deg"],
        "bank_deg": decoded["bank_deg"],
        "on_ground": decoded["on_ground"],

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
