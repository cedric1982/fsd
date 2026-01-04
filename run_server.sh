#!/bin/bash
echo "🧠 Starte Flask Webserver für FSD..."

cd "$(dirname "$0")"
source venv/bin/activate

nohup python3 web/app.py > logs/webserver.log 2>&1 &

echo "🌐 Webinterface läuft auf: http://localhost:8080"
