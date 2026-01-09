#!/usr/bin/env bash
set -euo pipefail

# ===============================================================
#  FSD SETUP - SINGLE FILE INSTALLER WITH TUI
# ===============================================================

SCRIPT_PATH="$(readlink -f "$0")"
BASE_DIR="$(dirname "$SCRIPT_PATH")"

export FSD_SCRIPT_PATH="$SCRIPT_PATH"
export FSD_BASE_DIR="$BASE_DIR"

MODE="${FSD_MODE:-tui}"   # tui | core

# ===============================================================
# CORE INSTALLER (deine eigentliche Installation)
# ===============================================================
core_install() {
  set -euo pipefail

  LOG_DIR="$BASE_DIR/logs"
  WEB_DIR="$BASE_DIR/web"
  UNIX_DIR="$BASE_DIR/unix"
  VENV_DIR="$BASE_DIR/venv"
  DB_PATH="$UNIX_DIR/cert.sqlitedb3"

  GREEN='\033[0;32m'
  YELLOW='\033[1;33m'
  RED='\033[0;31m'
  NC='\033[0m'

  echo -e "${YELLOW}=============================================${NC}"
  echo -e "${YELLOW}🚀 Starte FSD Installation${NC}"
  echo -e "${YELLOW}=============================================${NC}"

  sudo -v

  echo -e "${GREEN}🔧 System aktualisieren...${NC}"
  sudo apt update -y
  sudo apt upgrade -y

  echo -e "${GREEN}📦 Pakete installieren...${NC}"
  sudo apt install -y \
    build-essential cmake sqlite3 libsqlite3-dev \
    python3 python3-venv python3-pip \
    git nano curl unzip libjsoncpp-dev

  echo -e "${GREEN}📁 Verzeichnisse anlegen...${NC}"
  mkdir -p "$LOG_DIR" "$WEB_DIR" "$UNIX_DIR"

  echo -e "${GREEN}🐍 Python venv erstellen...${NC}"
  rm -rf "$VENV_DIR"
  python3 -m venv "$VENV_DIR"
  source "$VENV_DIR/bin/activate"

  echo -e "${GREEN}📚 Python Pakete installieren...${NC}"
  pip install --upgrade pip
  pip install flask psutil flask-cors flask-socketio eventlet werkzeug

  echo -e "${GREEN}🧩 FSD bauen (CMake)...${NC}"
  rm -rf "$BASE_DIR/build"
  mkdir "$BASE_DIR/build"
  cd "$BASE_DIR/build"
  cmake ..
  make -j"$(nproc)"

  if [[ ! -f fsd ]]; then
    echo -e "${RED}❌ Build fehlgeschlagen${NC}"
    exit 1
  fi

  cp fsd "$UNIX_DIR/fsd"
  chmod +x "$UNIX_DIR/fsd"
  rm -rf "$BASE_DIR/build"

  echo -e "${GREEN}🗃️ SQLite DB erstellen...${NC}"
  rm -f "$DB_PATH"
  sqlite3 "$DB_PATH" <<'SQL'
CREATE TABLE IF NOT EXISTS cert (
  cid TEXT PRIMARY KEY,
  password TEXT NOT NULL,
  level INT NOT NULL,
  twitch_name TEXT
);
INSERT OR REPLACE INTO cert VALUES ('1000001','observer',99,'Observer');
INSERT OR REPLACE INTO cert VALUES ('1000002','test123',1,'TestTwitch');
SQL
  chmod 644 "$DB_PATH"

  echo -e "${GREEN}🔐 Admin Passwort setzen...${NC}"

  if [[ -z "${FSD_ADMIN_PW:-}" ]]; then
    echo "❌ Kein Passwort übergeben"
    exit 1
  fi

  AUTH_FILE="$WEB_DIR/admin_auth.json"
  python3 - <<PY
import json
from werkzeug.security import generate_password_hash
pw = """$FSD_ADMIN_PW"""
with open("$AUTH_FILE","w") as f:
    json.dump({"admin_password_hash": generate_password_hash(pw)}, f)
print("Admin Hash geschrieben")
PY

  chmod 600 "$AUTH_FILE"
  chown "$USER:$USER" "$AUTH_FILE"

  echo -e "${GREEN}🎉 Installation abgeschlossen${NC}"
}

# ---------------------------------------------------------------
# CORE MODE
# ---------------------------------------------------------------
if [[ "$MODE" == "core" ]]; then
  core_install
  exit 0
fi

# ===============================================================
# TUI BOOTSTRAP (temporär)
# ===============================================================
sudo apt update -y
sudo apt install -y python3 python3-venv python3-pip

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

python3 -m venv "$TMP_DIR/venv"
source "$TMP_DIR/venv/bin/activate"
pip install --upgrade pip >/dev/null
pip install textual rich >/dev/null

cat > "$TMP_DIR/tui.py" <<'PY'
import os, subprocess, threading
from textual.app import App, ComposeResult
from textual.widgets import Header, Footer, Input, ListView, ListItem, Label, Static, RichLog, Button
from textual.containers import Horizontal, Vertical
from textual.screen import ModalScreen

class PasswordModal(ModalScreen):
    def compose(self):
        yield Static("Admin Passwort", id="title")
        yield Input(password=True, placeholder="Passwort", id="p1")
        yield Input(password=True, placeholder="Wiederholen", id="p2")
        with Horizontal():
            yield Button("OK", id="ok")
            yield Button("Abbrechen", id="cancel")

    def on_button_pressed(self, e):
        if e.button.id == "cancel":
            self.dismiss(None)
            return
        p1 = self.query_one("#p1").value
        p2 = self.query_one("#p2").value
        if not p1 or p1 != p2:
            self.query_one("#title").update("❌ Passwörter stimmen nicht")
            return
        self.dismiss(p1)

class Installer(App):
    CSS = """
    Screen { background:#0b1b1f; color:#d7e3e7; }
    $accent:#ff8c1a;
    #left { width:30%; border: tall $accent; }
    #right { width:70%; }
    RichLog { border: tall $accent; }
    """

    def compose(self):
        yield Header()
        with Horizontal():
            with Vertical(id="left"):
                yield Label("Setup")
                yield ListView(
                    ListItem(Label("Install")),
                )
            with Vertical(id="right"):
                yield RichLog(id="log")
        yield Footer()

    def on_mount(self):
        self.push_screen(PasswordModal(), self._got_pw)

    def _got_pw(self, pw):
        if not pw:
            self.exit(1)
        log = self.query_one("#log")
        log.write("Starte Installation…")

        def run():
            env = os.environ.copy()
            env["FSD_MODE"] = "core"
            env["FSD_ADMIN_PW"] = pw
            p = subprocess.Popen(
                [env["FSD_SCRIPT_PATH"]],
                cwd=env["FSD_BASE_DIR"],
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                text=True,
                env=env,
            )
            for l in p.stdout:
                self.call_from_thread(log.write, l.rstrip())
            self.call_from_thread(log.write, "Fertig.")

        threading.Thread(target=run, daemon=True).start()

Installer().run()
PY

python3 "$TMP_DIR/tui.py"
