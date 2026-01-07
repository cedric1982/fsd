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

DEBUG_RX = os.environ.get("FSD_DEBUG_RX", "1").strip() not in ("0", "false", "False", "")
SOCK_TIMEOUT_SEC = int(os.environ.get("FSD_SOCK_TIMEOUT", "30"))

# ---- Login defaults (passend zu deinem FSD-Server: #AA / #AP) ----
FSD_LOGIN_MODE = os.environ.get("FSD_LOGIN_MODE", "AA").strip().upper()  # "AA" oder "AP"
FSD_CALLSIGN = os.environ.get("FSD_CALLSIGN", "OBS1").strip()
FSD_REALNAME = os.environ.get("FSD_REALNAME", "Observer").strip()

# CID/PWD können leer sein, um erst mal Syntax zu testen; Server kann dann Auth ablehnen.
FSD_CID = os.environ.get("FSD_CID", "").strip()
FSD_PASSWORD = os.environ.get("FSD_PASSWORD", "").strip()

# Level/Revision müssen zu deinem Server passen. In deinem Code ist Revision typischerweise 9.
FSD_LEVEL = os.environ.get("FSD_LEVEL", "0").strip()
FSD_REVISION = os.environ.get("FSD_REVISION", "9").strip()

# Optional: SimType für #AP (wenn benötigt)
FSD_SIMTYPE = os.environ.get("FSD_SIMTYPE", "0").strip()

# Optional: Wenn gesetzt, wird das 1:1 gesendet (wie früher). Hat Priorität.
LOGIN_LINE = os.environ.get("FSD_LOGIN_LINE", "").strip()

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

    pitch_deg = math.floor(pitch_raw / -PITCH_MULT)
    bank_deg  = math.floor(bank_raw  / -BANK_MULT)
    heading_deg = hdg_raw / HDG_MULT

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
    Erwartetes Format:
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

    def _build_login_line(self) -> str:
        # Priorität: explizite FSD_LOGIN_LINE (1:1 senden)
        if LOGIN_LINE:
            return LOGIN_LINE.rstrip("\r\n")

        # Default: Login passend zu deinem FSD-Server (#AA oder #AP)
        if FSD_LOGIN_MODE == "AA":
            # Erwartet mindestens 7 Felder nach dem Kommando:
            # #AA + callsign : <unused> : realname : cid : pwd : level : revision
            return f"#AA{FSD_CALLSIGN}::{FSD_REALNAME}:{FSD_CID}:{FSD_PASSWORD}:{FSD_LEVEL}:{FSD_REVISION}"

        if FSD_LOGIN_MODE == "AP":
            # Erwartet mindestens 8 Felder:
            # #AP + callsign : <unused> : cid : pwd : level : revision : simtype : realname
            return f"#AP{FSD_CALLSIGN}::{FSD_CID}:{FSD_PASSWORD}:{FSD_LEVEL}:{FSD_REVISION}:{FSD_SIMTYPE}:{FSD_REALNAME}"

        # Fallback: bewusst klarer Fehler
        raise ValueError("FSD_LOGIN_MODE must be 'AA' or 'AP' (or set FSD_LOGIN_LINE explicitly)")

    def _send_login(self, sock: socket.socket):
        line = self._build_login_line()
        wire = (line + "\r\n").encode("utf-8", errors="ignore")
        sock.sendall(wire)
        print(f"[observer] sent login: {line}")

    def run(self):
        threading.Thread(target=self.push_loop, daemon=True).start()

        backoff = 1
        while True:
            sock: Optional[socket.socket] = None
            try:
                print(f"[observer] connecting to {FSD_HOST}:{FSD_PORT} ...")
                sock = socket.create_connection((FSD_HOST, FSD_PORT), timeout=8)

                # dauerhaft verbunden bleiben: recv blockiert unbegrenzt
                sock.settimeout(None)

                self._send_login(sock)
                print("[observer] tcp connected, waiting for server feed...")

                # nach erfolgreichem Connect Backoff zurücksetzen
                backoff = 1

                buf = b""
                while True:
                    chunk = sock.recv(4096)
                    if not chunk:
                        raise ConnectionError("socket closed by server")

                    log_rx_chunk(chunk)

                    buf += chunk
                    buf = buf.replace(b"\r\n", b"\n").replace(b"\r", b"\n")

                    while b"\n" in buf:
                        raw_line, buf = buf.split(b"\n", 1)
                        s = raw_line.decode("utf-8", errors="ignore").strip()
                        if not s:
                            continue

                        print(f"[observer] RX line: {s}")

                        if "@" in s:
                            obj = parse_position_line(s)
                            if obj:
                                self.update_client(obj)

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
