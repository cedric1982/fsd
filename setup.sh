#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# Single-file Installer:
# - Default: starts TUI (Textual) + asks admin password via modal
# - Then re-invokes itself in CORE mode to run the actual install
# ============================================================

SCRIPT_PATH="$(readlink -f "$0")"
BASE_DIR="$(dirname "$SCRIPT_PATH")"

MODE="${FSD_MODE:-tui}"   # "tui" or "core"
export BASE_DIR

# ---------- CORE INSTALLER (your real installation logic) ----------
core_install() {
  # Optional: keep your colors if you have them
  YELLOW="\033[1;33m"; RED="\033[1;31m"; GREEN="\033[1;32m"; NC="\033[0m"

  echo -e "${YELLOW}==> Core installer started${NC}"
  cd "$BASE_DIR"

  # ---- Example: minimal structure. Replace with YOUR existing steps. ----
  # IMPORTANT: keep sudo usage as needed. If you want sudo validated early:
  # sudo -v

  # 1) update/upgrade
  sudo apt update -y
  sudo apt upgrade -y

  # 2) install packages (example)
  sudo apt install -y build-essential cmake sqlite3 libsqlite3-dev python3 python3-venv python3-pip git nano curl unzip libjsoncpp-dev

  # 3) directories, builds, etc...
  mkdir -p "$BASE_DIR/logs" "$BASE_DIR/web" "$BASE_DIR/unix"

  # ---------------------------------------------------------------------
  # 10) Admin password - MUST come from ENV when running under TUI
  # ---------------------------------------------------------------------
  echo -e "\n${YELLOW}🔐 Admin-Passwort für Benutzerverwaltung setzen${NC}"

  if [[ -n "${FSD_ADMIN_PW:-}" && -n "${FSD_ADMIN_PW2:-}" ]]; then
    ADMIN_PW="$FSD_ADMIN_PW"
    ADMIN_PW2="$FSD_ADMIN_PW2"
  else
    # Fallback, falls jemand core direkt startet
    read -s -p "Admin-Passwort: " ADMIN_PW; echo
    read -s -p "Admin-Passwort wiederholen: " ADMIN_PW2; echo
  fi

  if [[ "$ADMIN_PW" != "$ADMIN_PW2" ]]; then
    echo -e "${RED}❌ Passwörter stimmen nicht überein.${NC}"
    exit 1
  fi

  # Beispiel: Hash schreiben (anpassen auf dein Projekt)
  # python venv etc. ggf. wie in deinem bisherigen Script
  # ---------------------------------------------------------------------
  # source "$BASE_DIR/venv/bin/activate"
  # python3 - <<PY
  # import json
  # from werkzeug.security import generate_password_hash
  # pw = """$ADMIN_PW"""
  # data = {'admin_password_hash': generate_password_hash(pw)}
  # with open('$BASE_DIR/web/admin_auth.json','w') as f:
  #     json.dump(data, f)
  # print('admin_auth.json written')
  # PY
  # chmod 600 "$BASE_DIR/web/admin_auth.json"
  # ---------------------------------------------------------------------

  echo -e "${GREEN}✅ Core installer finished successfully${NC}"
}

# If invoked in CORE mode, run installer and exit.
if [[ "$MODE" == "core" ]]; then
  core_install
  exit 0
fi

# ---------- TUI BOOTSTRAP ----------
# We will install only the minimal packages needed to render the TUI.
# Then create a temporary venv and run a temporary Python TUI from heredoc.

sudo apt update -y
sudo apt install -y python3 python3-venv python3-pip

TMP_DIR="$(mktemp -d)"
cleanup() {
  rm -rf "$TMP_DIR" || true
}
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
    "System aktualisieren",
    "Pakete installieren",
    "Verzeichnisse/Build/Setup",
    "Admin Passwort setzen",
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

    #left {
        width: 30%;
        min-width: 26;
        border: tall $accent;
        background: #061317;
    }

    #right { width: 70%; }

    #details {
        height: 7;
        border: tall $accent;
        background: #061317;
        padding: 1 2;
    }

    #logs {
        border: tall $accent;
        background: #061317;
        padding: 1 2;
    }

    ListView { background: #061317; }
    ListItem.-highlight { background: $accent; color: #081316; }

    Footer { background: #061317; }

    PasswordModal { align: center middle; }
    PasswordModal > * {
        width: 70;
        border: tall $accent;
        background: #061317;
        padding: 1 2;
    }
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

        result = await self.push_screen_wait(PasswordModal())
        pw1, pw2 = result

        log.write("[orange1]Starte Installer...[/orange1]")

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
    os.environ.setdefault("FSD_SCRIPT_PATH", "")
    os.environ.setdefault("FSD_BASE_DIR", "")
    InstallerTUI().run()
PY

export FSD_SCRIPT_PATH="$SCRIPT_PATH"
export FSD_BASE_DIR="$BASE_DIR"

python3 "$TUI_APP"
