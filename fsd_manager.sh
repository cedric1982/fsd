#!/bin/bash
# ==========================================================
# FSD Manager - Startet Webserver (Flask) und FSD Server
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
NC='\033[0m' # Keine Farbe

# Logs-Verzeichnis sicherstellen
mkdir -p "$LOG_DIR"
touch "$DEBUG_LOG" "$FSD_LOG"

# ==========================================================
# Prüfen, ob Prozess läuft
# ==========================================================
is_running() {
    pgrep -f "$1" > /dev/null 2>&1
    return $?
}

# ==========================================================
# Flask Webserver starten
# ==========================================================
start_webserver() {
    if is_running "app.py"; then
        echo -e "${YELLOW}⚠️ Flask-Webserver läuft bereits.${NC}"
    else
        echo -e "${GREEN}🚀 Starte Flask Webserver (mit virtueller Umgebung)...${NC}"
        cd "$BASE_DIR/web" || exit

        # Virtuelle Umgebung aktivieren
        source "$BASE_DIR/venv/bin/activate"

        # Flask im Hintergrund starten
        nohup python "$WEB_PATH" >> "$DEBUG_LOG" 2>&1 &

        sleep 2
    fi
}


# ==========================================================
# FSD Server starten
# ==========================================================
start_fsd_server() {
    if is_running "$FSD_PATH"; then
        echo -e "${YELLOW}⚠️ FSD-Server läuft bereits.${NC}"
    else
        echo -e "${GREEN}🛫 Starte FSD Server...${NC}"
        cd "$BASE_DIR/unix" || exit
        nohup ./fsd >> "$FSD_LOG" 2>&1 &
        sleep 2
    fi
}

# ==========================================================
# Logs anzeigen
# ==========================================================
show_logs() {
    echo -e "${YELLOW}📜 Starte Log-Viewer (STRG + C zum Beenden)...${NC}"
    tail -f "$DEBUG_LOG" "$FSD_LOG"
}

# ==========================================================
# Alle Prozesse stoppen
# ==========================================================
stop_all() {
    echo -e "\n${YELLOW}⏹ Stoppe alle laufenden Prozesse...${NC}"

    sudo pkill -f "python3" > /dev/null 2>&1
    sudo pkill -f "app.py" > /dev/null 2>&1
    sudo pkill -f "./fsd" > /dev/null 2>&1
    sudo pkill -f "tail -f" > /dev/null 2>&1
    sleep 1

    if pgrep -f "python3" > /dev/null || pgrep -f "./fsd" > /dev/null; then
        echo -e "${RED}❌ Einige Prozesse laufen noch!${NC}"
        ps ax | grep -E "python3|fsd" | grep -v grep
    else
        echo -e "${GREEN}✅ Alle Prozesse erfolgreich beendet.${NC}"
    fi

    echo -e "\nDrücke [ENTER], um zum Menü zurückzukehren..."
    read
}

# ==========================================================
# Menü anzeigen
# ==========================================================
show_menu() {
    clear
    echo "==============================================="
    echo "        🧭 FSD SERVER MANAGEMENT CONSOLE        "
    echo "==============================================="
    echo "1️⃣  Starte Webserver + FSD"
    echo "2️⃣  Nur Logs anzeigen"
    echo "3️⃣  Stoppe alle Prozesse"
    echo "4️⃣  Beenden"
    echo "==============================================="
    echo -n "Auswahl: "
}

# ==========================================================
# Haupt-Loop
# ==========================================================
while true; do
    show_menu
    read -r choice

    case $choice in
        1)
            start_webserver
            start_fsd_server
            show_logs
            ;;
        2)
            show_logs
            ;;
        3)
            stop_all
            ;;
        4)
            echo -e "${YELLOW}👋 Beende FSD Manager...${NC}"
            exit 0
            ;;
        *)
            echo -e "${RED}Ungültige Auswahl!${NC}"
            ;;
    esac
done
