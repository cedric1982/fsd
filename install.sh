#!/bin/bash
set -euo pipefail

# ===============================================================
#  FSD INSTALLATIONSSCRIPT (automatisch mit Python venv)
#  Relocatable: BASE_DIR wird aus Script-Pfad abgeleitet
# ===============================================================

# ----------------------------------------------------------
# BASE_DIR automatisch aus dem Speicherort dieses Scripts
# ----------------------------------------------------------
SCRIPT_PATH="$(readlink -f "$0")"
BASE_DIR="$(dirname "$SCRIPT_PATH")"

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

# -------------------------------
# 1. System vorbereiten
# -------------------------------
echo -e "${GREEN}🔧 Aktualisiere System...${NC}"
sudo apt update -y
sudo apt upgrade -y

echo -e "${GREEN}🧱 Installiere benötigte Systempakete...${NC}"
sudo apt install -y \
  build-essential cmake sqlite3 libsqlite3-dev \
  python3 python3-venv python3-pip \
  git nano curl unzip libjsoncpp-dev

# -------------------------------
# 2. Verzeichnisse anlegen
# -------------------------------
echo -e "${GREEN}📁 Erstelle benötigte Verzeichnisse...${NC}"
mkdir -p "$LOG_DIR" "$WEB_DIR" "$UNIX_DIR"

# -------------------------------
# 3. Virtuelle Umgebung erstellen
# -------------------------------
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

# -------------------------------
# 4. Python-Pakete installieren
# -------------------------------
echo -e "${GREEN}📚 Installiere Flask, psutil & flask-cors...${NC}"
pip install --upgrade pip
pip install flask psutil flask-cors flask-socketio eventlet

# -------------------------------
# 5. FSD kompilieren (CMake)
# -------------------------------
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

# -------------------------------
# 6. SQLite-Datenbank für Benutzer erstellen (einmal, definiert)
# -------------------------------
echo -e "${GREEN}🗃️ Erstelle SQLite-Datenbank für Benutzer (cert.sqlitedb3)...${NC}"

# Wenn du die DB NICHT jedes Mal neu erstellen willst, kommentiere die nächste Zeile aus:
rm -f "$DB_PATH"

sqlite3 "$DB_PATH" <<'SQL'
CREATE TABLE IF NOT EXISTS cert (
    cid TEXT PRIMARY KEY NOT NULL,
    password TEXT NOT NULL,
    level INT NOT NULL
);

INSERT OR REPLACE INTO cert (cid, password, level)
VALUES ('1000001', 'admin123', 5);

INSERT OR REPLACE INTO cert (cid, password, level)
VALUES ('1000002', 'test123', 1);
SQL

chmod 644 "$DB_PATH"
echo -e "${GREEN}✅ Datenbank erstellt und Benutzer hinzugefügt: $DB_PATH${NC}"

# -------------------------------
# 7. Logs anlegen
# -------------------------------
echo -e "${GREEN}🧾 Lege Logfiles an...${NC}"
mkdir -p "$LOG_DIR"
touch "$LOG_DIR/debug.log" "$LOG_DIR/fsd_output.log"

# -------------------------------
# 8. Skripte ausführbar machen
# -------------------------------
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

# -------------------------------
# 9. Ownership/Berechtigungen (vorsichtig)
# -------------------------------
echo -e "${GREEN}🔑 Setze Berechtigungen...${NC}"
sudo chown -R "$USER:$USER" "$BASE_DIR"
sudo chmod -R 755 "$BASE_DIR"

# -------------------------------
# 10. Fertig
# -------------------------------
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
