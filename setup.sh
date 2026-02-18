#!/usr/bin/env bash
# ============================================================
# OpenClaw VPS Setup – Token-optimiert
# Getestet auf Ubuntu 22.04 / Debian 12
# ============================================================
set -euo pipefail

OPENCLAW_DIR="$HOME/.openclaw"
WORKSPACE_DIR="$HOME/.openclaw/workspace"
CONFIG_SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/openclaw.json"
WORKSPACE_SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/workspace"

echo "==> OpenClaw VPS Setup startet..."

# ── 1. Node.js (>= 20) ────────────────────────────────────────────────────────
if ! command -v node &>/dev/null || [[ "$(node -v | cut -d. -f1 | tr -d 'v')" -lt 20 ]]; then
  echo "--> Node.js 22 LTS installieren..."
  curl -fsSL https://deb.nodesource.com/setup_22.x | sudo -E bash -
  sudo apt-get install -y nodejs
fi
echo "    Node.js: $(node --version)"

# ── 2. OpenClaw installieren / aktualisieren ──────────────────────────────────
echo "--> OpenClaw global installieren / aktualisieren..."
npm install -g @openclaw/openclaw

echo "    OpenClaw: $(openclaw --version 2>/dev/null || echo 'installiert')"

# ── 3. Verzeichnisse anlegen ──────────────────────────────────────────────────
mkdir -p "$OPENCLAW_DIR" "$WORKSPACE_DIR"

# ── 4. Konfiguration kopieren (nicht überschreiben, wenn vorhanden) ───────────
if [[ -f "$CONFIG_SRC" ]]; then
  if [[ -f "$OPENCLAW_DIR/openclaw.json" ]]; then
    echo "--> Bestehende openclaw.json gefunden – Backup erstellen..."
    cp "$OPENCLAW_DIR/openclaw.json" "$OPENCLAW_DIR/openclaw.json.bak.$(date +%Y%m%d%H%M%S)"
  fi
  echo "--> Optimierte Konfiguration kopieren..."
  cp "$CONFIG_SRC" "$OPENCLAW_DIR/openclaw.json"
fi

# ── 5. Workspace-Dateien (AGENTS.md, HEARTBEAT.md) kopieren ──────────────────
if [[ -d "$WORKSPACE_SRC" ]]; then
  echo "--> Workspace-Dateien kopieren..."
  cp -n "$WORKSPACE_SRC/"*.md "$WORKSPACE_DIR/" 2>/dev/null || true
fi

# ── 6. Konfiguration validieren ───────────────────────────────────────────────
echo "--> Konfiguration prüfen (openclaw doctor)..."
openclaw doctor || echo "    Warnung: 'openclaw doctor' meldet Probleme – bitte prüfen."

# ── 7. Systemd-Service einrichten (optional) ──────────────────────────────────
if command -v systemctl &>/dev/null; then
  SERVICE_FILE="/etc/systemd/system/openclaw.service"
  if [[ ! -f "$SERVICE_FILE" ]]; then
    echo "--> Systemd-Service anlegen..."
    sudo tee "$SERVICE_FILE" > /dev/null <<EOF
[Unit]
Description=OpenClaw Gateway
After=network.target

[Service]
Type=simple
User=$USER
WorkingDirectory=$HOME
ExecStart=$(which openclaw) start
Restart=on-failure
RestartSec=10
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF
    sudo systemctl daemon-reload
    sudo systemctl enable openclaw
    echo "    Service aktiviert. Starten mit: sudo systemctl start openclaw"
  else
    echo "    Systemd-Service bereits vorhanden."
  fi
fi

echo ""
echo "============================================================"
echo " Setup abgeschlossen!"
echo ""
echo " Naechste Schritte:"
echo "   1. API-Schluessel eintragen:"
echo "      openclaw config set anthropic.apiKey sk-ant-..."
echo "   2. Gateway starten:"
echo "      sudo systemctl start openclaw"
echo "      -- oder manuell: openclaw start"
echo "   3. Status pruefen:"
echo "      openclaw status --usage"
echo ""
echo " Token-Kosten im Blick behalten:"
echo "   Im Chat: /status  /usage tokens  /usage cost"
echo "============================================================"
