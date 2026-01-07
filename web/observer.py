#!/usr/bin/env python3
import os
import time
import json
import socket
import threading
import urllib.request
import math
from typing import Optional, Dict, Any, List
import sys
sys.stdout.reconfigure(line_buffering=True)
sys.stderr.reconfigure(line_buffering=True)

# =============================================================================
# Config (ENV)
# =============================================================================
FSD_HOST = os.environ.get("FSD_HOST", "127.0.0.1")
FSD_PORT = int(os.environ.get("FSD_PORT", "6809"))

PUSH_URL = os.environ.get("FSD_PUSH_URL", "http://127.0.0.1:8080/api/live_update")
PUSH_TOKEN = os.environ.get("FSD_PUSH_TOKEN", "my-super-secret-token")
PUSH_INTERVAL = float(os.environ.get("FSD_PUSH_INTERVAL", "1.0"))

# Wichtig: Login-Zeile muss exakt zu deinem FSD passen.
# Diese Zeile wird 1:1 gesendet (ohne zusätzliches Parsen).
LOGIN_LINE = os.environ.get("FSD_LOGIN_LINE", "").strip()

# Optional: Logging/Debug
DEBUG_RX = os.environ.get("FSD_DEBUG_RX", "1").strip() not in ("0", "false", "False", "")
SOCK_TIMEOUT_SEC = int(os.environ.get("FSD_SOCK_TIMEOUT", "30"))

# =============================================================================
# PBH Decoder (Swift-kompatible Semantik)
# =============================================================================
PITCH_MULT = 256.0 / 90.0
BANK_MULT  = 512.0 / 180.0
HDG_MULT   = 1024.0 / 360.0

def sign_extend_10bit(x: int) -> int:
    x &= 0x3FF
    return x - 0x400 if (x & 0x200) else x

def unpack_pbh(pbh_u32: int) -> Dict[str, Any]:
    pbh = pbh_u32 & 0xFFFFFFFF

    unused    = (pbh >> 0) & 0x1
    onground  = (pbh >> 1) & 0x1
    hdg_raw   = (pbh >> 2) & 0x3FF
    bank_raw  = sign_extend_10bit((pbh >> 12) & 0x3FF)
    pitch_raw = sign_extend_10bit((pbh >> 22) & 0x3FF)

    # Swift uses qFloor on pitch/bank
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

# =============================================================================
# Parsing
# =============================================================================
def parse_position_line(line: str) -> Optional[Dict[str, Any]]:
    """
    Erwartetes Format (aus deinen Dumps):
      @CALLSIGN:SQUAWK:TYPE:LAT:LON:ALT:GS:PBH:VS
    """
    if "@" not in line:
        return None

    line = line[line.find("@"):].strip()
    if not line.startswith("@"):
        return None

    parts = line[1:].split(":")
    if len(parts) < 9:
        return None

    callsign = parts[0].strip()
    squawk = parts[1].strip()
    ctype = parts[2].strip()

    try:
        lat = float(parts[3])
        lon = float(parts[4])
        alt = int(float(parts[5]))
        gs  = int(float(parts[6]))
        pbh_raw = int(float(parts[7]))
        vs  = int(float(parts[8]))
    except ValueError:
        return None

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

        # PBH Decode
        "pbh_u32": decoded["pbh_u32"],
        "hdg_deg": round(decoded["heading_deg"], 2),
        "hdg_deg_round": decoded["heading_deg_rounded"],
        "pitch_deg": decoded["pitch_deg"],
        "bank_deg": decoded["bank_deg"],
        "on_ground": decoded["on_ground"],

        "ts": int(time.time())
    }

# =============================================================================
# HTTP Push
# =============================================================================
def http_post_json(url: str, token: str, payload: dict) -> int:
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
    with urllib.request.urlopen(req, timeout=3) as resp:
        return resp.status

# =============================================================================
# Debug Helpers
# =============================================================================
def _hexdump_prefix(b: bytes, max_len: int = 96) -> str:
    bb = b[:max_len]
    return " ".join(f"{x:02x}" for x in bb) + (" ..." if len(b) > max_len else "")

def log_rx_chunk(chunk: bytes):
    if not DEBUG_RX:
        return
    try:
        text = chunk.decode("utf-8", errors="replace")
    except Exception:
        text = "<decode failed>"
    print(f"[observer] RX bytes len={len(chunk)} repr={chunk!r}")
    print(f"[observer] RX text: {text}")
    print(f"[observer] RX hex:  {_hexdump_prefix(chunk)}")

# =============================================================================
# Observer
# =============================================================================
class LiveObserver:
    def __init__(self):
        self.clients: Dict[str, Dict[str, Any]] = {}
        self.lock = threading.Lock()
        self.last_push = 0.0

    def update_client(self, obj: Dict[str, Any]):
        with self.lock:
            self.clients[obj["callsign"]] = obj

    def snapshot(self) -> List[Dict[str, Any]]:
        with self.lock:
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

    def _send_login(self, sock: socket.socket):
        # Wichtig: FSD erwartet meistens CRLF
        if LOGIN_LINE:
            line = LOGIN_LINE.rstrip("\r\n") + "\r\n"
            sock.sendall(line.encode("utf-8", errors="ignore"))
            print(f"[observer] sent login: {LOGIN_LINE}")
        else:
            print("[observer] WARNING: FSD_LOGIN_LINE empty -> no login sent")

    def run(self):
        threading.Thread(target=self.push_loop, daemon=True).start()

        backoff = 1
        while True:
            sock: Optional[socket.socket] = None
            try:
                print(f"[observer] connecting to {FSD_HOST}:{FSD_PORT} ...")
                sock = socket.create_connection((FSD_HOST, FSD_PORT), timeout=8)
                sock.settimeout(SOCK_TIMEOUT_SEC)

                # Login sofort senden
                self._send_login(sock)

                print("[observer] tcp connected, waiting for server feed...")

                buf = b""
                while True:
                    chunk = sock.recv(4096)
                    if not chunk:
                        raise ConnectionError("socket closed by server")

                    log_rx_chunk(chunk)

                    buf += chunk

                    # robust gegen \r, \r\n, \n
                    # wir splitten auf \n nachdem wir \r -> \n normalisiert haben
                    norm = buf.replace(b"\r", b"\n")

                    while b"\n" in norm:
                        raw_line, rest = norm.split(b"\n", 1)

                        # rest ist bereits normalisiert; übernehmen
                        buf = rest
                        norm = buf

                        s = raw_line.decode("utf-8", errors="ignore").strip()
                        if not s:
                            continue

                        # alles loggen (entscheidend fürs Login-Problem)
                        print(f"[observer] RX line: {s}")

                        # Positionsdaten
                        if "@" in s:
                            obj = parse_position_line(s)
                            if obj:
                                self.update_client(obj)

            except socket.timeout:
                print(f"[observer] disconnected: RX timeout after {SOCK_TIMEOUT_SEC}s. retry in {backoff}s")
                time.sleep(backoff)
                backoff = min(backoff * 2, 30)

            except Exception as e:
                print(f"[observer] disconnected: {e}. retry in {backoff}s")
                time.sleep(backoff)
                backoff = min(backoff * 2, 30)

            finally:
                try:
                    if sock:
                        sock.close()
                except Exception:
                    pass

if __name__ == "__main__":
    LiveObserver().run()
