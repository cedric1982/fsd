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

echo -e "${GREEN}🧱 Installiere benötigte Systempakete...${NC}"
sudo apt update -y
sudo apt install -y build-essential cmake python3 python3-venv python3-pip sqlite3 libsqlite3-dev git nano curl unzip


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
# 5. FSD Kompillieren mit SQL
# -------------------------------

echo -e "${GREEN}🧩 Kompiliere FSD Server mit SQLite-Unterstützung...${NC}"
cd "$BASE_DIR"
if [ ! -d "build" ]; then
    mkdir build
fi
cd build
cmake ..
make -j$(nproc)
echo -e "${GREEN}✅ FSD Server erfolgreich gebaut.${NC}"

# -------------------------------
# 6. FSD Kompillieren mit SQL
# -------------------------------

echo -e "${GREEN}🗃️ Erstelle SQLite-Datenbank für Benutzer (cert.sqlitedb3)...${NC}"
cd "$BASE_DIR/unix"
if [ ! -f "cert.sqlitedb3" ]; then
    sqlite3 cert.sqlitedb3 "CREATE TABLE IF NOT EXISTS cert(callsign TEXT PRIMARY KEY NOT NULL, password TEXT NOT NULL, level INT NOT NULL);"
    echo -e "${GREEN}✅ Datenbank erstellt.${NC}"
else
    echo -e "${YELLOW}⚠️ Datenbank existiert bereits – überspringe.${NC}"
fi

# ==========================================================
# SQLite-Datenbank für Benutzer erstellen
# ==========================================================

echo -e "\n${YELLOW}📦 Erstelle SQLite-Datenbank für Benutzer...${NC}"

DB_PATH="$BASE_DIR/unix/cert.sqlitedb3"

# Falls alte Datenbank existiert -> löschen
if [ -f "$DB_PATH" ]; then
    rm "$DB_PATH"
fi

# Neue Datenbank und Tabelle erstellen
sqlite3 "$DB_PATH" <<EOF
CREATE TABLE cert (
    callsign TEXT PRIMARY KEY NOT NULL,
    password TEXT NOT NULL,
    level INT NOT NULL
);

INSERT INTO cert (callsign, password, level) VALUES
('ADMIN01', 'admin123', 5),
('TEST01', 'test123', 1);
EOF

# Rechte setzen
chmod 644 "$DB_PATH"

echo -e "${GREEN}✅ SQLite-Datenbank erstellt unter:${NC} $DB_PATH"
echo -e "${YELLOW}→ Benutzer hinzugefügt: ADMIN01 / TEST01${NC}"


# -------------------------------
# 6. Beerechtigungen prüfen
# -------------------------------

echo -e "${GREEN}🔑 Setze Dateiberechtigungen...${NC}"
sudo chmod -R 755 "$BASE_DIR"
sudo chown -R $USER:$USER "$BASE_DIR"

mkdir -p "$LOG_DIR"
touch "$LOG_DIR/debug.log" "$LOG_DIR/fsd_output.log"


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
echo -e "📦 FSD kompiliert mit SQLite-Unterstützung"
echo -e "🐍 Flask Umgebung installiert"
echo -e "🗃️  Benutzer-Datenbank: $BASE_DIR/unix/cert.sqlitedb3"
echo -e "🧭 Manager starten mit:"
echo -e "👉  sudo bash $BASE_DIR/fsd_manager.sh"
echo -e "---------------------------------------------"
echo -e "${YELLOW}Zum Starten:${NC}"
echo -e "👉  source $VENV_DIR/bin/activate"
echo -e "👉  sudo bash $BASE_DIR/fsd_manager.sh"
echo -e "---------------------------------------------"
