#!/bin/bash
echo "🚀 Installation des FSD Webservers wird gestartet..."

# Prüfe Python
if ! command -v python3 &> /dev/null; then
    echo "❌ Python3 ist nicht installiert!"
    exit 1
fi

# Virtuelle Umgebung
python3 -m venv venv
source venv/bin/activate

# Flask + psutil installieren
pip install --upgrade pip
pip install flask psutil

# Ordnerstruktur
mkdir -p web/templates web/static
mkdir -p logs

# Erfolgsmeldung
echo "✅ Installation abgeschlossen!"
echo "Starte den Server mit: bash run_server.sh"
