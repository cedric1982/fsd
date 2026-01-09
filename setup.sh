#!/usr/bin/env bash
set -euo pipefail

# ===============================================================
#  FSD INSTALLER - Single File
#  - Default: start Textual TUI (orange) + password modal
#  - Then re-invoke this same script in CORE mode
# ===============================================================

SCRIPT_PATH="$(readlink -f "$0")"
BASE_DIR="$(dirname "$SCRIPT_PATH")"

export BASE_DIR
export FSD_SCRIPT_PATH="$SCRIPT_PATH"
export FSD_BASE_DIR="$BASE_DIR"

MODE="${FSD_MODE:-tui}"   # "tui" or "core"

# -------------------------------
# CORE INSTALLER (deine Logik)
# -------------------------------
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
  echo -e "${YELLOW}🚀 Starte FSD-Server Installation...${NC}"
  echo -e "${YELLOW}   BASE_DIR: $BASE_DIR${NC}"
  echo -e "${YELLOW}=============================================${NC}\n"

  # Optional: sudo früh validieren, damit später keine "hängenden" Prompts kommen
  sudo -v

  # 1. System vorbereiten
  echo -e "${GREEN}🔧 Aktualisiere System...${NC}"
  sudo apt update -y
  sudo apt upgrade -y

  echo -e "${GREEN}🧱 Installiere benötigte Systempakete...${NC}"
  sudo apt install -y \
    build-essential cmake sqlite3 libsqlite3-dev \
    python3 python3-venv python3-pip \
    git nano curl unzip libjsoncpp-dev

  # 2. Verzeichnisse anlegen
  echo -e "${GREEN}📁 Erstelle benötigte Verzeichnisse...${NC}"
  mkdir -p "$LOG_DIR" "$WEB_DIR" "$UNIX_DIR"

  # 3. Virtuelle Umgebung erstellen
  echo -e "${GREEN}🐍 Erstelle Python venv unter: $VENV_DIR${NC}"
  rm -rf "$VENV_DIR" 2>/dev/null || true
  python3 -m venv "$VENV_DIR"

  if [ ! -d "$VENV_DIR" ]; then
    echo -e "${RED}❌ Virtuelle Umgebung konnte nicht erstellt werden!${NC}"
    exit 1
  fi

  # Aktivieren
  # shellcheck disable=SC1090
  source "$VENV_DIR/bin/activate"

  # 4. Python-Pakete installieren
  echo -e "${GREEN}📚 Installiere Flask, psutil & flask-cors...${NC}"
  pip install --upgrade pip
  pip install flask psutil flask-cors flask-socketio eventlet werkzeug

  # 5. FSD kompilieren (CMake)
  echo -e "${GREEN}🧩 Kompiliere FSD Server mit SQLite-Unterstützung...${NC}"
  cd "$BASE_DIR"

  rm -rf "$BASE_DIR/build" 2>/dev/null || true
  mkdir -p "$BASE_DIR/build"
  cd "$BASE_DIR/build"

  cmake ..
  make -j"$(nproc)"

  # Prüfen, ob fsd erfolgreich kompiliert wurde und in unix kopieren
  if [ -f "$BASE_DIR/build/fsd" ]; then
    echo -e "${GREEN}✅ FSD erfolgreich kompiliert, kopiere nach unix/...${NC}"
    cp "$BASE_DIR/build/fsd" "$UNIX_DIR/fsd"
    chmod +x "$UNIX_DIR/fsd"
  else
    echo -e "${RED}❌ Fehler: fsd wurde nicht im build-Ordner gefunden!${NC}"
    exit 1
  fi

  rm -rf "$BASE_DIR/build"
  echo -e "${GREEN}✅ FSD Server erfolgreich gebaut.${NC}"

  # 6. SQLite-Datenbank für Benutzer erstellen
  echo -e "${GREEN}🗃️ Erstelle SQLite-Datenbank für Benutzer (cert.sqlitedb3)...${NC}"
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
  echo -e "${GREEN}✅ Datenbank erstellt und Benutzer hinzugefügt: $DB_PATH${NC}"

  # 7. Logs anlegen
  echo -e "${GREEN}🧾 Lege Logfiles an...${NC}"
  mkdir -p "$LOG_DIR"
  touch "$LOG_DIR/debug.log" "$LOG_DIR/fsd_output.log"

  # 8. Skripte ausführbar machen
  if [ -f "$BASE_DIR/fsd_manager.sh" ]; then
    chmod +x "$BASE_DIR/fsd_manager.sh"
    echo -e "${GREEN}✅ fsd_manager.sh ist ausführbar.${NC}"
  else
    echo -e "${YELLOW}⚠️ fsd_manager.sh nicht gefunden!${NC}"
  fi

  if [ -f "$WEB_DIR/app.py" ]; then
    chmod +x "$WEB_DIR/app.py"
    echo -e "${GREEN}✅ app.py ist ausführbar.${NC}"
  else
    echo -e "${YELLOW}⚠️ app.py nicht gefunden!${NC}"
  fi

  # 9. Ownership/Berechtigungen
  echo -e "${GREEN}🔑 Setze Berechtigungen...${NC}"
  sudo chown -R "$USER:$USER" "$BASE_DIR"
  sudo chmod -R 755 "$BASE_DIR"

  # 10. Admin Passwort (per TUI-Modal oder Fallback)
  echo -e "\n${YELLOW}🔐 Admin-Passwort für Benutzerverwaltung setzen${NC}"

  if [[ -n "${FSD_ADMIN_PW:-}" && -n "${FSD_ADMIN_PW2:-}" ]]; then
    ADMIN_PW="$FSD_ADMIN_PW"
    ADMIN_PW2="$FSD_ADMIN_PW2"
  else
    read -s -p "Admin-Passwort: " ADMIN_PW; echo
    read -s -p "Admin-Passwort wiederholen: " ADMIN_PW2; echo
  fi

  if [ "$ADMIN_PW" != "$ADMIN_PW2" ]; then
    echo -e "${RED}❌ Passwörter stimmen nicht überein.${NC}"
    exit 1
  fi

  AUTH_FILE="$BASE_DIR/web/admin_auth.json"

  python3 - <<PY
import json
from werkzeug.security import generate_password_hash
pw = """$ADMIN_PW"""
data = {"admin_password_hash": generate_password_hash(pw)}
with open("$AUTH_FILE","w") as f:
    json.dump(data, f)
print("✅ Admin-Hash geschrieben nach: $AUTH_FILE")
PY

  chmod 600 "$AUTH_FILE"
  chown "$USER:$USER" "$AUTH_FILE"

  # 11. Fertig
  echo -e "\n${GREEN}🎉 Installation abgeschlossen!${NC}"
  echo -e "---------------------------------------------"
  echo -e "📦 FSD kompiliert mit SQLite-Unterstützung"
  echo -e "🐍 Flask Umgebung installiert: $VENV_DIR"
  echo -e "🗃️  Benutzer-Datenbank: $DB_PATH"
  echo -e "🧭 Manager starten mit:"
  echo -e "👉  bash \"$BASE_DIR/fsd_manager.sh\""
  echo -e "---------------------------------------------"
  echo -e "${YELLOW}Zum Starten:${NC}"
  echo -e "👉  source \"$VENV_DIR/bin/activate\""
  echo -e "👉  bash \"$BASE_DIR/fsd_manager.sh\""
  echo -e "---------------------------------------------"
}

# CORE mode: run the real installer
if [[ "$MODE" == "core" ]]; then
  core_install
  exit 0
fi

# -------------------------------
# TUI bootstrap (nur 1 Datei insgesamt)
# -------------------------------
sudo apt update -y
sudo apt install -y python3 python3-venv python3-pip

TMP_DIR="$(mktemp -d)"
cleanup() { rm -rf "$TMP_DIR" || true; }
trap cleanup EXIT

TUI_VENV="$TMP_DIR/.tui_venv"
python3 -m venv "$TUI_VENV"
# shellcheck disable=SC1090
source "$TUI_VENV/bin/activate"
pip install --upgrade pip >/dev/null
pip install -U textual rich >/dev/null

TUI_APP="$TMP_DIR/tui_runner.py"

cat > "$TUI_APP" <<'PY'
import os
import subprocess
import threading

from textual.app import App, ComposeResult
from textual.containers import Horizontal, Vertical
from textual.widgets import Header, Footer, Input, ListView, ListItem, Label, Static, RichLog, Button
from textual.screen import ModalScreen

STEPS = [
    "System vorbereiten",
    "Pakete installieren",
    "Python venv + Pakete",
    "Build (CMake/Make)",
    "DB + Rechte",
    "Admin Passwort",
    "Fertig",
]

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
            self.app.exit(return_code=1)
            return
        pw1 = self.query_one("#pw1", Input).value
        pw2 = self.query_one("#pw2", Input).value
        if not pw1 or pw1 != pw2:
            self.query_one("#modal_title", Static).update("Passwörter stimmen nicht überein.")
            return
        self.dismiss((pw1, pw2))

class DetailBox(Static):
    pass

class InstallerTUI(App):
    CSS = """
    Screen { background: #0b1b1f; color: #d7e3e7; }
    $accent: #ff8c1a;

    Input { border: tall $accent; background: #061317; color: #d7e3e7; }

    #layout { height: 1fr; }

    #left { width: 30%; min-width: 26; border: tall $accent; background: #061317; }
    #right { width: 70%; }

    #details { height: 7; border: tall $accent; background: #061317; padding: 1 2; }
    #logs { border: tall $accent; background: #061317; padding: 1 2; }

    ListView { background: #061317; }
    ListItem.-highlight { background: $accent; color: #081316; }

    Footer { background: #061317; }

    PasswordModal { align: center middle; }
    PasswordModal > * { width: 70; border: tall $accent; background: #061317; padding: 1 2; }
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
        with Horizontal(id="layout"):
            with Vertical(id="left"):
                yield Label("Steps", id="left_title")
                yield ListView(*[ListItem(Label(s)) for s in STEPS], id="step_list")
            with Vertical(id="right"):
                yield DetailBox(id="details")
                yield RichLog(highlight=True, markup=True, id="logs")
        yield Footer()

    async def on_mount(self) -> None:
        self.query_one("#step_list", ListView).index = 0
        self._render_details(0)

        log = self.query_one("#logs", RichLog)
        log.write("[b]Installer Logs[/b]")
        log.write("Passwort wird abgefragt...")

        pw1, pw2 = await self.push_screen_wait(PasswordModal())

        log.write("[orange1]Starte Installation...[/orange1]")

        t = threading.Thread(target=self._run_installer, args=(pw1, pw2), daemon=True)
        t.start()

    def _render_details(self, idx: int) -> None:
        box = self.query_one("#details", DetailBox)
        box.update(
            "[b]Details[/b]\n"
            f"Step: {STEPS[idx]}\n"
            "Status: [green]running[/green]\n"
            f"Script: {os.environ.get('FSD_SCRIPT_PATH','(unknown)')}"
        )

    def _run_installer(self, pw1: str, pw2: str) -> None:
        log = self.query_one("#logs", RichLog)

        env = os.environ.copy()
        env["FSD_MODE"] = "core"
        env["FSD_ADMIN_PW"] = pw1
        env["FSD_ADMIN_PW2"] = pw2

        script = env["FSD_SCRIPT_PATH"]
        base_dir = env["FSD_BASE_DIR"]

        proc = subprocess.Popen(
            [script],
            cwd=base_dir,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            bufsize=1,
            env=env,
        )

        for line in proc.stdout:
            self.call_from_thread(log.write, line.rstrip("\n"))

        rc = proc.wait()
        if rc == 0:
            self.call_from_thread(log.write, "[green]Installation abgeschlossen.[/green]")
        else:
            self.call_from_thread(log.write, f"[red]Installation fehlgeschlagen (Exit {rc}).[/red]")

    def action_focus_search(self) -> None:
        self.query_one("#search", Input).focus()

if __name__ == "__main__":
    InstallerTUI().run()
PY

python3 "$TUI_APP"
