#!/bin/bash
# ===============================================================
#  FSD INSTALLATIONSSCRIPT (automatisch mit Python venv)
# ===============================================================

BASE_DIR="/home/cedric1982/fsd"
LOG_DIR="$BASE_DIR/logs"
WEB_DIR="$BASE_DIR/web"
UNIX_DIR="$BASE_DIR/unix"
VENV_DIR="$BASE_DIR/venv"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${YELLOW}=============================================${NC}"
echo -e "${YELLOW}🚀 Starte FSD-Server Installation...${NC}"
echo -e "${YELLOW}=============================================${NC}\n"

# -------------------------------
# 1. System vorbereiten
# -------------------------------
echo -e "${GREEN}🔧 Aktualisiere System...${NC}"
sudo apt update -y && sudo apt upgrade -y

echo -e "${GREEN}📦 Installiere Python & pip...${NC}"
sudo apt install -y python3 python3-venv python3-pip

# -------------------------------
# 2. Virtuelle Umgebung erstellen
# -------------------------------
echo -e "${GREEN}🐍 Erstelle Python venv unter: $VENV_DIR${NC}"
sudo rm -rf "$VENV_DIR" 2>/dev/null
python3 -m venv "$VENV_DIR"

# Prüfen ob erfolgreich:
if [ ! -d "$VENV_DIR" ]; then
    echo -e "${RED}❌ Virtuelle Umgebung konnte nicht erstellt werden!${NC}"
    exit 1
fi

# Aktivieren
source "$VENV_DIR/bin/activate"

# -------------------------------
# 3. Python-Pakete installieren
# -------------------------------
echo -e "${GREEN}📚 Installiere Flask, psutil & flask-cors...${NC}"
pip install --upgrade pip
pip install flask psutil flask-cors

# -------------------------------
# 4. Verzeichnisse & Berechtigungen
# -------------------------------
echo -e "${GREEN}📁 Erstelle benötigte Verzeichnisse...${NC}"
mkdir -p "$LOG_DIR" "$WEB_DIR" "$UNIX_DIR"

echo -e "${GREEN}🔑 Setze Berechtigungen...${NC}"
sudo chmod -R 755 "$BASE_DIR"
sudo chown -R $USER:$USER "$BASE_DIR"

# -------------------------------
# 5. Logs anlegen
# -------------------------------
touch "$LOG_DIR/debug.log"
touch "$LOG_DIR/fsd_output.log"

# -------------------------------
# 6. Skripte ausführbar machen
# -------------------------------
if [ -f "$BASE_DIR/fsd_manager.sh" ]; then
    chmod +x "$BASE_DIR/fsd_manager.sh"
    echo -e "${GREEN}✅ fsd_manager.sh ist ausführbar.${NC}"
else
    echo -e "${RED}⚠️  fsd_manager.sh nicht gefunden!${NC}"
fi

if [ -f "$WEB_DIR/app.py" ]; then
    chmod +x "$WEB_DIR/app.py"
    echo -e "${GREEN}✅ app.py ist ausführbar.${NC}"
else
    echo -e "${RED}⚠️  app.py nicht gefunden!${NC}"
fi

# -------------------------------
# 7. Fertig
# -------------------------------
echo -e "\n${GREEN}🎉 Installation abgeschlossen!${NC}"
echo -e "---------------------------------------------"
echo -e "📂 Basisverzeichnis: $BASE_DIR"
echo -e "🌐 Webserver-Datei: $WEB_DIR/app.py"
echo -e "🧭 Manager-Script:   $BASE_DIR/fsd_manager.sh"
echo -e "📜 Logs-Verzeichnis: $LOG_DIR"
echo -e "🐍 Virtuelle Umgebung: $VENV_DIR"
echo -e "---------------------------------------------"
echo -e "${YELLOW}Zum Starten:${NC}"
echo -e "👉  source $VENV_DIR/bin/activate"
echo -e "👉  sudo bash $BASE_DIR/fsd_manager.sh"
echo -e "---------------------------------------------"
