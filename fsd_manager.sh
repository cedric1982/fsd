#!/bin/bash
# ==========================================================
# ✦ FSD Manager - Startet Webserver (Flask) und FSD Server ✦
# ==========================================================
# ----------------------------------------------------------
# BASE_DIR automatisch aus dem Speicherort dieses Scripts
# ----------------------------------------------------------
SCRIPT_PATH="$(readlink -f "$0")"
SCRIPT_DIR="$(dirname "$SCRIPT_PATH")"


# Wenn fsd_manager.sh im Projektroot liegt, ist BASE_DIR = SCRIPT_DIR
BASE_DIR="$SCRIPT_DIR"

# Optional: Falls du fsd_manager.sh in <base>/bin/ ablegst, nimm parent:
# BASE_DIR="$(dirname "$SCRIPT_DIR")"

# Pfade relativ zum BASE_DIR
FSD_PATH="$BASE_DIR/unix/fsd"
WEB_PATH="$BASE_DIR/web/app.py"
LOG_DIR="$BASE_DIR/logs"
WEB_LOG="$LOG_DIR/web_app.log"
OBSERVER_LOG="$LOG_DIR/observer.log"
FSD_LOG="$LOG_DIR/fsd_output.log"
VENV_ACTIVATE="$BASE_DIR/venv/bin/activate"
OBSERVER_PATH="$BASE_DIR/web/observer.py"
OBSERVER_LOG="$LOG_DIR/observer.log"

# Shared Token für Flask <-> Observer
export FSD_PUSH_TOKEN="my-super-secret-token"
export FSD_PUSH_URL="http://127.0.0.1:8080/api/live_update"
export FSD_HOST="127.0.0.1"
export FSD_PORT="6809"
export FSD_LOGIN_MODE="AA"
export FSD_CALLSIGN="BOT"
export FSD_REALNAME="Observer"
export FSD_LEVEL="1"
export FSD_REVISION="9"
export FSD_CID="999999"
export FSD_PASSWORD="bot"
export FSD_BOT_CID="999999"





# Farben
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# Logs-Verzeichnis sicherstellen
mkdir -p "$LOG_DIR"
touch "$WEB_LOG" "$FSD_LOG" "$OBSERVER_LOG"

# Position, ab der Ausgaben erscheinen
OUTPUT_LINE=11

# ==========================================================
# Hilfsfunktionen
# ==========================================================

# Prüft, ob Prozess läuft
is_running() {
    pgrep -f "$1" > /dev/null 2>&1
    return $?
}

# Cursorposition ändern
move_cursor() {
    tput cup "$1" 0
}

# Ausgabe im unteren Bereich
print_output() {
    move_cursor "$OUTPUT_LINE"
    tput ed  # löscht alten Text ab dieser Zeile
    echo -e "${YELLOW}---------------------------------------------${NC}"
    echo -e "$1"
    echo -e "${YELLOW}---------------------------------------------${NC}"
}

# Menü anzeigen
draw_menu() {
    clear
    echo -e "${YELLOW}==============================================="
    echo -e "         🧭 FSD SERVER MANAGEMENT CONSOLE       "
    echo -e "===============================================${NC}"
    echo -e "${GREEN} 1${NC}) Starte Webserver + FSD"
    echo -e "${GREEN} 2${NC}) Nur Logs anzeigen"
    echo -e "${GREEN} 3${NC}) Stoppe alle Prozesse"
    echo -e "${GREEN} 4${NC}) Beenden"
    echo -e "${YELLOW}-----------------------------------------------${NC}"
    echo -ne "Auswahl: "
}

# ==========================================================
# Aktionen
# ==========================================================

start_webserver() {
    print_output "${GREEN}🚀 Starte Flask Webserver (mit virtueller Umgebung)...${NC}"
    if is_running "$WEB_PATH"; then
        print_output "${YELLOW}⚠️ Flask-Webserver läuft bereits.${NC}"
    else
        cd "$BASE_DIR/web" || exit
        source "$VENV_ACTIVATE"
        echo "[fsd_manager] $(date -Is) starting web app" >> "$WEB_LOG"
        nohup python -u "$WEB_PATH" >> "$WEB_LOG" 2>&1 &
        sleep 2
        print_output "${GREEN}✅ Flask-Webserver gestartet (PID: $(pgrep -f app.py))${NC}"
    fi
}

start_fsd_server() {
    print_output "${GREEN}🛫 Starte FSD Server...${NC}"
    if is_running "$FSD_PATH"; then
        print_output "${YELLOW}⚠️ FSD-Server läuft bereits.${NC}"
    else
        cd "$BASE_DIR/unix" || exit
        nohup "$FSD_PATH" >> "$FSD_LOG" 2>&1 &
        sleep 2
        print_output "${GREEN}✅ FSD Server gestartet (PID: $(pgrep -f fsd | head -n1))${NC}"
    fi
}

start_observer() {
    print_output "${GREEN}📡 Starte Live-Observer (FSD Positions)...${NC}"
    if is_running "$OBSERVER_PATH"; then
        print_output "${YELLOW}⚠️ Observer läuft bereits.${NC}"
    else
        source "$VENV_ACTIVATE"
        echo "[fsd_manager] $(date -Is) starting observer" >> "$OBSERVER_LOG"
        echo "[fsd_manager] FSD_LOGIN_LINE=${FSD_LOGIN_LINE:-<empty>}" >> "$OBSERVER_LOG"
        nohup python -u "$OBSERVER_PATH" >> "$OBSERVER_LOG" 2>&1 &
        sleep 1
        print_output "${GREEN}✅ Observer gestartet (PID: $(pgrep -f observer.py | head -n1))${NC}"
    fi
}


show_logs() {
    clear
    echo -e "${YELLOW}📜 Log-Viewer (STRG + C zum Beenden)...${NC}"
    tail -f "$WEB_LOG" "$FSD_LOG" "$OBSERVER_LOG"

}

stop_all() {
    print_output "${YELLOW}⏹ Stoppe alle laufenden Prozesse...${NC}"

    # Web: nur app.py aus deinem BASE_DIR
    pkill -f "$WEB_PATH" > /dev/null 2>&1

    # FSD: nur deine Binary
    pkill -f "$FSD_PATH" > /dev/null 2>&1

    # Observer
    pkill -f "$OBSERVER_PATH" > /dev/null 2>&1

    sleep 1

    if pgrep -f "$WEB_PATH" > /dev/null || pgrep -f "$FSD_PATH" > /dev/null; then
        print_output "${RED}❌ Einige Prozesse laufen noch!${NC}\n$(ps ax | grep -E "$(basename "$WEB_PATH")|$(basename "$FSD_PATH")" | grep -v grep)"
    else
        print_output "${GREEN}✅ Alle Prozesse erfolgreich beendet.${NC}"
    fi

    echo -e "\nDrücke [ENTER], um zum Menü zurückzukehren..."
    read
}


# ==========================================================
# Hauptschleife
# ==========================================================

while true; do
    draw_menu
    read -r choice

    case $choice in
        1)
            start_webserver
            start_fsd_server
            start_observer
            ;;
        2)
            show_logs
            ;;
        3)
            stop_all
            ;;
        4)
            print_output "${YELLOW}👋 Beende FSD Manager...${NC}"
            exit 0
            ;;
        *)
            print_output "${RED}❌ Ungültige Auswahl!${NC}"
            ;;
    esac

    echo -e "\n${YELLOW}Drücke [ENTER], um zum Menü zurückzukehren...${NC}"
    read
done
