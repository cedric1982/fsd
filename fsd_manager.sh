#!/bin/bash
# ==========================================================================
# FSD Manager – Steuert Webserver + FSD Server gleichzeitig
# ==========================================================================

# Automatisch aktuelles Verzeichnis erkennen
BASE_DIR="$(cd "$(dirname "$0")" && pwd)"
FSD_PATH="$BASE_DIR/unix/fsd"
WEB_PATH="$BASE_DIR/web/app.py"
LOG_DIR="$BASE_DIR/logs"
DEBUG_LOG="$LOG_DIR/debug.log"
FSD_LOG="$LOG_DIR/fsd_output.log"

# Farben
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # keine Farbe

# Wechsle ins Hauptverzeichnis
cd "$BASE_DIR" || { echo "❌ Konnte nicht in $BASE_DIR wechseln"; exit 1; }

# Stelle sicher, dass logs/ existiert
mkdir -p "$LOG_DIR"

# Falls Logdateien nicht existieren, lege sie an und initialisiere sie
if [ ! -f "$DEBUG_LOG" ]; then
    echo "[INFO] Flask Debug Log erstellt am $(date)" > "$DEBUG_LOG"
fi
if [ ! -f "$FSD_LOG" ]; then
    echo "[INFO] FSD Output Log erstellt am $(date)" > "$FSD_LOG"
fi


# ------------------------------------------------------------------------------
# Funktion: prüft, ob Prozess läuft
# ------------------------------------------------------------------------------
is_running() {
    pgrep -f "$1" > /dev/null 2>&1
    return $?
}

# ------------------------------------------------------------------------------
# Funktion: Webserver starten
# ------------------------------------------------------------------------------
start_webserver() {
    if is_running "app.py"; then
        echo -e "${YELLOW}⚙️ Flask Webserver läuft bereits.${NC}"
    else
        echo -e "${GREEN}🚀 Starte Flask Webserver...${NC}"
        source venv/bin/activate
        nohup python3 "$WEB_PATH" > "$DEBUG_LOG" 2>&1 &
        sleep 2
    fi
}

# ------------------------------------------------------------------------------
# Funktion: FSD starten
# ------------------------------------------------------------------------------
start_fsd() {
    if is_running "$FSD_PATH"; then
        echo -e "${YELLOW}🛫 FSD-Server läuft bereits.${NC}"
    else
        echo -e "${GREEN}✈️  Starte FSD-Server...${NC}"
        cd "$BASE_DIR/unix" || { echo "❌ Konnte nicht ins Unix-Verzeichnis wechseln"; return; }
        nohup sudo ./fsd > "$FSD_LOG" 2>&1 &
        sleep 2
    fi
}

# ------------------------------------------------------------------------------
# Funktion: Logs live anzeigen
# ------------------------------------------------------------------------------
show_logs() {
    echo -e "${GREEN}📡 Starte Log-Viewer (Strg + C zum Beenden)...${NC}"
    echo -e "${YELLOW}---------------- FLASK DEBUG -----------------${NC}"
    tail -f "$DEBUG_LOG" &
    PID1=$!

    echo -e "${YELLOW}---------------- FSD SERVER ------------------${NC}"
    tail -f "$FSD_LOG" &
    PID2=$!

    # Warten, bis Nutzer abbricht
    trap "echo -e '\n🛑 Stoppe Prozesse...'; kill $PID1 $PID2" SIGINT
    wait
}

# ------------------------------------------------------------------------------
# Funktion: Prozesse stoppen
# ------------------------------------------------------------------------------
stop_all() {
    echo -e "${YELLOW}🧹 Beende alle laufenden Prozesse...${NC}"
    pkill -f app.py
    sudo pkill -f "$FSD_PATH"
}

# ------------------------------------------------------------------------------
# Hauptmenü
# ------------------------------------------------------------------------------
clear
echo -e "${GREEN}"
echo "=============================================="
echo "     FSD SERVER MANAGEMENT CONSOLE"
echo "=============================================="
echo -e "${NC}"
echo "1️⃣  Start Webserver + FSD"
echo "2️⃣  Nur Logs anzeigen"
echo "3️⃣  Stoppe alle Prozesse"
echo "4️⃣  Beenden"
echo ""
read -p "👉 Auswahl: " choice

case $choice in
    1)
        start_webserver
        start_fsd
        show_logs
        ;;
    2)
        show_logs
        ;;
    3)
        stop_all
        ;;
    4)
        echo "👋 Beende Manager."
        ;;
    *)
        echo "❌ Ungültige Auswahl."
        ;;
esac
