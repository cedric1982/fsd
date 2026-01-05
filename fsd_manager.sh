#!/bin/bash
# ==========================================================
# ✦ FSD Manager - Startet Webserver (Flask) und FSD Server ✦
# ==========================================================

BASE_DIR="/home/cedric1982/fsd"
FSD_PATH="$BASE_DIR/unix/fsd"
WEB_PATH="$BASE_DIR/web/app.py"
LOG_DIR="$BASE_DIR/logs"
DEBUG_LOG="$LOG_DIR/debug.log"
FSD_LOG="$LOG_DIR/fsd_output.log"

# Farben
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# Logs-Verzeichnis sicherstellen
mkdir -p "$LOG_DIR"
touch "$DEBUG_LOG" "$FSD_LOG"

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
    if is_running "app.py"; then
        print_output "${YELLOW}⚠️ Flask-Webserver läuft bereits.${NC}"
    else
        cd "$BASE_DIR/web" || exit
        source "$BASE_DIR/venv/bin/activate"
        nohup python "$WEB_PATH" >> "$DEBUG_LOG" 2>&1 &
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
        nohup ./fsd >> "$FSD_LOG" 2>&1 &
        sleep 2
        print_output "${GREEN}✅ FSD Server gestartet (PID: $(pgrep -f fsd | head -n1))${NC}"
    fi
}

show_logs() {
    clear
    echo -e "${YELLOW}📜 Log-Viewer (STRG + C zum Beenden)...${NC}"
    tail -f "$DEBUG_LOG" "$FSD_LOG"
}

stop_all() {
    print_output "${YELLOW}⏹ Stoppe alle laufenden Prozesse...${NC}"
    sudo pkill -f "python3" > /dev/null 2>&1
    sudo pkill -f "app.py" > /dev/null 2>&1
    sudo pkill -f "./fsd" > /dev/null 2>&1
    sleep 1

    if pgrep -f "python3" > /dev/null || pgrep -f "./fsd" > /dev/null; then
        print_output "${RED}❌ Einige Prozesse laufen noch!${NC}\n$(ps ax | grep -E 'python3|fsd' | grep -v grep)"
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
