#!/bin/bash
# ===============================================================
#  FSD INSTALLATIONSSCRIPT
#  Erstellt Umgebung, installiert Abhängigkeiten & richtet alles ein
# ===============================================================

BASE_DIR="/home/cedric1982/fsd"
LOG_DIR="$BASE_DIR/logs"
WEB_DIR="$BASE_DIR/web"
UNIX_DIR="$BASE_DIR/unix"

# Farben
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${YELLOW}=============================================${NC}"
echo -e "${YELLOW}🚀 Starte Installation des FSD-Servers...${NC}"
echo -e "${YELLOW}=============================================${NC}\n"

# -------------------------------
# System vorbereiten
# -------------------------------
echo -e "${GREEN}🔧 Aktualisiere Paketlisten...${NC}"
sudo apt update -y && sudo apt upgrade -y

echo -e "${GREEN}📦 Installiere benötigte Pakete...${NC}"
sudo apt install -y python3 python3-pip python3-venv git nano curl unzip

# -------------------------------
# Python-Abhängigkeiten
# -------------------------------
echo -e "${GREEN}🐍 Installiere Python-Module...${NC}"
pip3 install --upgrade pip
pip3 install flask psutil flask-cors

# -------------------------------
# Verzeichnisstruktur prüfen
# -------------------------------
echo -e "${GREEN}📁 Erstelle Verzeichnisstruktur...${NC}"
mkdir -p "$LOG_DIR" "$WEB_DIR" "$UNIX_DIR"

# -------------------------------
# Zugriffsrechte setzen
# -------------------------------
echo -e "${GREEN}🔑 Setze Berechtigungen...${NC}"
sudo chmod -R 755 "$BASE_DIR"
sudo chown -R $USER:$USER "$BASE_DIR"

# -------------------------------
# Skripte prüfen und ausführbar machen
# -------------------------------
if [ -f "$BASE_DIR/fsd_manager.sh" ]; then
    sudo chmod +x "$BASE_DIR/fsd_manager.sh"
    echo -e "${GREEN}✅ fsd_manager.sh ist ausführbar.${NC}"
else
    echo -e "${RED}⚠️  fsd_manager.sh nicht gefunden! Bitte Datei prüfen.${NC}"
fi

if [ -f "$WEB_DIR/app.py" ]; then
    sudo chmod +x "$WEB_DIR/app.py"
    echo -e "${GREEN}✅ app.py ist ausführbar.${NC}"
else
    echo -e "${RED}⚠️  app.py nicht gefunden! Bitte Datei prüfen.${NC}"
fi

# -------------------------------
# Logs vorbereiten
# -------------------------------
echo -e "${GREEN}🪵 Lege Log-Dateien an...${NC}"
touch "$LOG_DIR/debug.log"
touch "$LOG_DIR/fsd_output.log"

# -------------------------------
# Abschluss
# -------------------------------
echo -e "\n${GREEN}🎉 Installation abgeschlossen!${NC}"
echo -e "---------------------------------------------"
echo -e "📂 Basisverzeichnis: $BASE_DIR"
echo -e "🌐 Webserver-Datei: $WEB_DIR/app.py"
echo -e "🧭 Manager-Script:   $BASE_DIR/fsd_manager.sh"
echo -e "📜 Logs-Verzeichnis: $LOG_DIR"
echo -e "---------------------------------------------"
echo -e "${YELLOW}Zum Starten des Managers:${NC}"
echo -e "👉  sudo bash $BASE_DIR/fsd_manager.sh"
echo -e "---------------------------------------------"
