#!/usr/bin/env bash
set -euo pipefail

# ===============================================================
#  setup.sh - Single File Installer mit TUI (orange) + Modal-PW
#  - Start: ./setup.sh  -> TUI
#  - Intern: FSD_MODE=core -> führt den Core-Installer aus
# ===============================================================

SCRIPT_PATH="$(readlink -f "$0")"
BASE_DIR="$(dirname "$SCRIPT_PATH")"

export FSD_SCRIPT_PATH="$SCRIPT_PATH"
export FSD_BASE_DIR="$BASE_DIR"

# UTF-8 (hilft generell; Borders sind trotzdem ASCII)
export LANG="${LANG:-C.UTF-8}"
export LC_ALL="${LC_ALL:-C.UTF-8}"

MODE="${FSD_MODE:-tui}"   # tui | core

# Marker für TUI->Core Synchronisation
TUI_PW_MARKER="__FSD_TUI_REQUEST_ADMIN_PW__"

# ===============================================================
# CORE INSTALLER (deine Installation)
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

  # sudo früh validieren (sonst hängt es ggf. mitten im Lauf)
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
  rm -rf "$VENV_DIR" 2>/dev/null || true
  python3 -m venv "$VENV_DIR"
  # shellcheck disable=SC1090
  source "$VENV_DIR/bin/activate"

  echo -e "${GREEN}📚 Python Pakete installieren...${NC}"
  pip install --upgrade pip
  pip install flask psutil flask-cors flask-socketio eventlet werkzeug

  echo -e "${GREEN}🧩 FSD bauen (CMake)...${NC}"
  rm -rf "$BASE_DIR/build" 2>/dev/null || true
  mkdir -p "$BASE_DIR/build"
  cd "$BASE_DIR/build"
  cmake ..
  make -j"$(nproc)"

  if [[ ! -f "$BASE_DIR/build/fsd" ]]; then
    echo -e "${RED}❌ Fehler: fsd wurde nicht im build-Ordner gefunden!${NC}"
    exit 1
  fi

  cp "$BASE_DIR/build/fsd" "$UNIX_DIR/fsd"
  chmod +x "$UNIX_DIR/fsd"
  rm -rf "$BASE_DIR/build"
  echo -e "${GREEN}✅ Build abgeschlossen.${NC}"

  echo -e "${GREEN}🗃️ SQLite DB erstellen...${NC}"
  rm -f "$DB_PATH"
  sqlite3 "$DB_PATH" <<'SQL'
CREATE TABLE IF NOT EXISTS cert (
    cid TEXT PRIMARY KEY NOT NULL,
    password TEXT NOT NULL,
    level INT NOT NULL,
    twitch_name TEXT
);

INSERT OR REPLACE INTO cert (cid, password, level, twitch_name)
VALUES ('1000001', 'observer', 99, 'Observer');

INSERT OR REPLACE INTO cert (cid, password, level, twitch_name)
VALUES ('1000002', 'test123', 1, 'TestTwitch');
SQL
  chmod 644 "$DB_PATH"
  echo -e "${GREEN}✅ DB erstellt: $DB_PATH${NC}"

  echo -e "${GREEN}🧾 Logfiles anlegen...${NC}"
  touch "$LOG_DIR/debug.log" "$LOG_DIR/fsd_output.log"

  if [[ -f "$BASE_DIR/fsd_manager.sh" ]]; then
    chmod +x "$BASE_DIR/fsd_manager.sh"
    echo -e "${GREEN}✅ fsd_manager.sh ist ausführbar.${NC}"
  else
    echo -e "${YELLOW}⚠️ fsd_manager.sh nicht gefunden!${NC}"
  fi

  if [[ -f "$WEB_DIR/app.py" ]]; then
    chmod +x "$WEB_DIR/app.py"
    echo -e "${GREEN}✅ app.py ist ausführbar.${NC}"
  else
    echo -e "${YELLOW}⚠️ app.py nicht gefunden!${NC}"
  fi

  echo -e "${GREEN}🔑 Setze Berechtigungen...${NC}"
  sudo chown -R "$USER:$USER" "$BASE_DIR"
  sudo chmod -R 755 "$BASE_DIR"

  # -------------------------------------------------------------
  # Admin Passwort: erst an dieser Stelle anfordern (TUI Modal)
  # -------------------------------------------------------------
  echo -e "\n${YELLOW}🔐 Admin-Passwort für Benutzerverwaltung setzen${NC}"

  ADMIN_PW=""
  ADMIN_PW2=""

  # Wenn TUI aktiv ist, fordern wir Passwort via Marker an und lesen über stdin
  if [[ -n "${FSD_TUI:-}" ]] && [[ ! -t 0 ]]; then
    echo "$TUI_PW_MARKER"
    IFS= read -r ADMIN_PW
    IFS= read -r ADMIN_PW2
  else
    read -s -p "Admin-Passwort: " ADMIN_PW; echo
    read -s -p "Admin-Passwort wiederholen: " ADMIN_PW2; echo
  fi

  if [[ -z "$ADMIN_PW" || "$ADMIN_PW" != "$ADMIN_PW2" ]]; then
    echo -e "${RED}❌ Passwörter stimmen nicht überein.${NC}"
    exit 1
  fi

  AUTH_FILE="$WEB_DIR/admin_auth.json"
  python3 - <<PY
import json
from werkzeug.security import generate_password_hash
pw = """$ADMIN_PW"""
with open("$AUTH_FILE","w") as f:
    json.dump({"admin_password_hash": generate_password_hash(pw)}, f)
print("✅ Admin-Hash geschrieben nach: $AUTH_FILE")
PY
  chmod 600 "$AUTH_FILE"
  chown "$USER:$USER" "$AUTH_FILE"

  echo -e "\n${GREEN}🎉 Installation abgeschlossen!${NC}"
  echo -e "---------------------------------------------"
  echo -e "📦 FSD kompiliert: $UNIX_DIR/fsd"
  echo -e "🐍 venv: $VENV_DIR"
  echo -e "🗃️  DB: $DB_PATH"
  echo -e "👉 Start: source \"$VENV_DIR/bin/activate\" && bash \"$BASE_DIR/fsd_manager.sh\""
  echo -e "---------------------------------------------"
}

# ===============================================================
# CORE MODE
# ===============================================================
if [[ "$MODE" == "core" ]]; then
  core_install
  exit 0
fi

# ===============================================================
# TUI BOOTSTRAP (nur temporär, bleibt Single-File)
# ===============================================================
sudo apt update -y
sudo apt install -y python3 python3-venv python3-pip

TMP_DIR="$(mktemp -d)"
cleanup() { rm -rf "$TMP_DIR" || true; }
trap cleanup EXIT

python3 -m venv "$TMP_DIR/venv"
# shellcheck disable=SC1090
source "$TMP_DIR/venv/bin/activate"
pip install --upgrade pip >/dev/null
pip install -U textual rich >/dev/null

TUI_APP="$TMP_DIR/tui.py"

cat > "$TUI_APP" <<'PY'
import os
import subprocess
import threading

from textual.app import App, ComposeResult
from textual.containers import Horizontal, Vertical
from textual.widgets import Header, Footer, Input, ListView, ListItem, Label, Static, RichLog, Button
from textual.screen import ModalScreen

MARKER = "__FSD_TUI_REQUEST_ADMIN_PW__"

class PasswordModal(ModalScreen):
    def compose(self) -> ComposeResult:
        yield Static("Admin-Passwort setzen", id="modal_title")
        yield Input(password=True, placeholder="Admin-Passwort", id="pw1")
        yield Input(password=True, placeholder="Wiederholen", id="pw2")
        with Horizontal(id="modal_buttons"):
            yield Button("OK", id="ok", variant="primary")
            yield Button("Abbrechen", id="cancel")

    def on_button_pressed(self, event: Button.Pressed) -> None:
        if event.button.id == "cancel":
            self.dismiss(None)
            return

        pw1 = self.query_one("#pw1", Input).value
        pw2 = self.query_one("#pw2", Input).value
        if not pw1 or pw1 != pw2:
            self.query_one("#modal_title", Static).update("Passwörter stimmen nicht überein.")
            return

        self.dismiss((pw1, pw2))

class InstallerTUI(App):
    CSS = """
    Screen { background: #0b1b1f; color: #d7e3e7; }
    $accent: #ff8c1a;

    /* ASCII Borders: robust in VirtualBox/TTY */
    Input { border: ascii $accent; background: #061317; color: #d7e3e7; }
    #left { width: 30%; min-width: 26; border: ascii $accent; background: #061317; }
    #details { height: 7; border: ascii $accent; background: #061317; padding: 1 2; }
    #logs { border: ascii $accent; background: #061317; padding: 1 2; }
    Footer { background: #061317; }

    PasswordModal { align: center middle; }
    PasswordModal > * { width: 70; border: ascii $accent; background: #061317; padding: 1 2; }
    #modal_buttons { height: auto; align: center middle; padding-top: 1; }
    Button { margin: 0 1; }
    """

    BINDINGS = [
        ("q", "quit", "Quit"),
        ("/", "focus_search", "Search"),
    ]

    def compose(self) -> ComposeResult:
        yield Header(show_clock=True)
        yield Input(placeholder="Search (Ctrl+F or /)", id="search")
        with Horizontal():
            with Vertical(id="left"):
                yield Label("Setup", id="left_title")
                yield ListView(
                    ListItem(Label("Install")),
                    id="step_list"
                )
            with Vertical(id="right"):
                yield Static("[b]Details[/b]\nInstaller läuft…", id="details")
                yield RichLog(highlight=True, markup=True, id="logs")
        yield Footer()

    def on_mount(self) -> None:
        self.query_one("#step_list", ListView).index = 0
        log = self.query_one("#logs", RichLog)
        log.write("[b]Installer Logs[/b]")
        log.write("Starte Core-Installer…")
        self._start_core()

    def _start_core(self) -> None:
        env = os.environ.copy()
        env["FSD_MODE"] = "core"
        env["FSD_TUI"] = "1"

        script = env["FSD_SCRIPT_PATH"]
        base_dir = env["FSD_BASE_DIR"]

        self.proc = subprocess.Popen(
            [script],
            cwd=base_dir,
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            bufsize=1,
            env=env,
        )

        threading.Thread(target=self._reader, daemon=True).start()

    def _reader(self) -> None:
        log = self.query_one("#logs", RichLog)

        for line in self.proc.stdout:
            line = line.rstrip("\n")

            if line.strip() == MARKER:
                self.call_from_thread(self._request_pw)
                continue

            self.call_from_thread(log.write, line)

        rc = self.proc.wait()
        self.call_from_thread(
            log.write,
            "[green]Installation abgeschlossen.[/green]" if rc == 0 else f"[red]Installation fehlgeschlagen (Exit {rc}).[/red]"
        )

    def _request_pw(self) -> None:
        log = self.query_one("#logs", RichLog)
        log.write("[orange1]Admin-Passwort erforderlich…[/orange1]")
        self.push_screen(PasswordModal(), self._on_pw)

    def _on_pw(self, result) -> None:
        log = self.query_one("#logs", RichLog)

        if result is None:
            log.write("[red]Abgebrochen.[/red]")
            try:
                self.proc.terminate()
            except Exception:
                pass
            self.exit(1)
            return

        pw1, pw2 = result
        try:
            self.proc.stdin.write(pw1 + "\n")
            self.proc.stdin.write(pw2 + "\n")
            self.proc.stdin.flush()
            log.write("[green]Passwort übernommen.[/green]")
        except Exception as e:
            log.write(f"[red]Konnte Passwort nicht senden: {e}[/red]")
            self.exit(1)

    def action_focus_search(self) -> None:
        self.query_one("#search", Input).focus()

if __name__ == "__main__":
    InstallerTUI().run()
PY

python3 "$TUI_APP"
