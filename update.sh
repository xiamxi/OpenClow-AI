#!/usr/bin/env bash
# ============================================================
# OpenClaw Token-Optimierung – Update-Skript (v1.0)
#
# Dieses Skript patcht eine bereits installierte OpenClaw-
# Instanz mit token-sparenden Einstellungen.
# Es verändert NICHTS an API-Schlüsseln, Kanälen oder
# bestehenden Agenten-Definitionen.
#
# Download & Ausführen:
#   curl -fsSL <raw-url>/update.sh -o oc-update.sh
#   chmod +x oc-update.sh && ./oc-update.sh
#
# Optionen:
#   --dry-run    Zeigt geplante Änderungen, ohne sie zu schreiben
#   --no-restart Dienst nach dem Update nicht neu starten
# ============================================================
set -euo pipefail

# ── Argumente ─────────────────────────────────────────────────────────────────
DRY_RUN=false
NO_RESTART=false
for arg in "$@"; do
  case "$arg" in
    --dry-run)    DRY_RUN=true ;;
    --no-restart) NO_RESTART=true ;;
    *) echo "Unbekannte Option: $arg"; exit 1 ;;
  esac
done

# ── Farben ────────────────────────────────────────────────────────────────────
GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; RESET='\033[0m'
ok()   { echo -e "${GREEN}  ✓${RESET} $*"; }
warn() { echo -e "${YELLOW}  !${RESET} $*"; }
err()  { echo -e "${RED}  ✗${RESET} $*"; }

echo ""
echo "════════════════════════════════════════════════════════════"
echo " OpenClaw Token-Optimierung – Update"
if $DRY_RUN; then echo -e " ${YELLOW}[DRY-RUN – keine Dateien werden geschrieben]${RESET}"; fi
echo "════════════════════════════════════════════════════════════"
echo ""

# ── Abhängigkeiten prüfen ─────────────────────────────────────────────────────
if ! command -v python3 &>/dev/null; then
  err "python3 nicht gefunden. Installation: sudo apt-get install python3"
  exit 1
fi

# ── Konfigurationspfad ermitteln ──────────────────────────────────────────────
CONFIG_CANDIDATES=(
  "$HOME/.openclaw/openclaw.json"
  "$HOME/.clawdbot/clawdbot.json"
)
CONFIG_PATH=""
for c in "${CONFIG_CANDIDATES[@]}"; do
  if [[ -f "$c" ]]; then
    CONFIG_PATH="$c"
    break
  fi
done

if [[ -z "$CONFIG_PATH" ]]; then
  err "Keine OpenClaw-Konfiguration gefunden."
  err "Gesucht in: ${CONFIG_CANDIDATES[*]}"
  exit 1
fi
ok "Konfiguration gefunden: $CONFIG_PATH"

# Workspace-Verzeichnis (parallel zur Config)
CONFIG_DIR="$(dirname "$CONFIG_PATH")"
WORKSPACE_DIR="$CONFIG_DIR/workspace"

# ── Backup ───────────────────────────────────────────────────────────────────
BACKUP="$CONFIG_PATH.bak.$(date +%Y%m%d%H%M%S)"
if ! $DRY_RUN; then
  cp "$CONFIG_PATH" "$BACKUP"
  ok "Backup erstellt: $BACKUP"
else
  warn "DRY-RUN: Backup würde erstellt werden: $BACKUP"
fi

# ── JSON-Patch (via Python3) ──────────────────────────────────────────────────
# Der Patch merged nur Optimierungs-Schlüssel; alles andere (API-Keys,
# Kanäle, eigene Agenten) bleibt unangetastet.

PATCH_JSON='{
  "agents": {
    "defaults": {
      "model": {
        "primary": "anthropic/claude-sonnet-4-5",
        "fallbacks": [
          "anthropic/claude-haiku-4-5",
          "openrouter/openrouter/auto"
        ]
      },
      "models": {
        "anthropic/claude-haiku-4-5":  { "alias": "haiku"  },
        "anthropic/claude-sonnet-4-5": { "alias": "sonnet" },
        "anthropic/claude-opus-4-6":   { "alias": "opus"   }
      },
      "contextPruning": {
        "mode": "cache-ttl",
        "ttl": "1h"
      },
      "compaction": {
        "mode": "safeguard",
        "reserveTokensFloor": 24000,
        "memoryFlush": {
          "enabled": true,
          "softThresholdTokens": 6000,
          "systemPrompt": "Session naehert sich dem Limit. Wichtige Infos jetzt sichern.",
          "prompt": "Schreibe alle dauerhaften Notizen nach memory/YYYY-MM-DD.md; antworte mit NO_REPLY, wenn nichts zu speichern ist."
        }
      },
      "heartbeat": {
        "every": "55m",
        "model": "anthropic/claude-haiku-4-5",
        "includeReasoning": false,
        "ackMaxChars": 200,
        "suppressToolErrorWarnings": true,
        "prompt": "Lies HEARTBEAT.md, falls vorhanden. Fuehre nur aus, was dort steht. Antworte mit NO_REPLY, wenn keine Aktion noetig."
      },
      "imageMaxDimensionPx": 800,
      "bootstrapMaxChars": 8000,
      "bootstrapTotalMaxChars": 40000,
      "maxConcurrent": 2,
      "subagents": {
        "maxConcurrent": 4
      }
    }
  },
  "gateway": {
    "bind": "loopback"
  }
}'

PYTHON_SCRIPT='
import json, re, sys

def strip_comments(text):
    """Entfernt // Kommentare aus JSON-ähnlichem Text."""
    lines = []
    for line in text.splitlines():
        stripped = re.sub(r"\s*//.*$", "", line)
        lines.append(stripped)
    # Trailing commas vor } oder ] entfernen
    text = "\n".join(lines)
    text = re.sub(r",(\s*[}\]])", r"\1", text)
    return text

def deep_merge(base, patch):
    """Merged patch in base. Existierende Werte werden nur überschrieben,
    wenn der Patch-Key auf der gleichen Ebene definiert ist.
    Listen werden vollständig ersetzt (nicht erweitert)."""
    result = dict(base)
    for key, val in patch.items():
        if key in result and isinstance(result[key], dict) and isinstance(val, dict):
            result[key] = deep_merge(result[key], val)
        else:
            result[key] = val
    return result

config_path = sys.argv[1]
patch_json  = sys.argv[2]
dry_run     = sys.argv[3] == "true"

with open(config_path, "r", encoding="utf-8") as f:
    raw = f.read()

try:
    current = json.loads(raw)
except json.JSONDecodeError:
    current = json.loads(strip_comments(raw))

patch = json.loads(patch_json)
merged = deep_merge(current, patch)

output = json.dumps(merged, indent=2, ensure_ascii=False)

if dry_run:
    print("--- VORSCHAU DER NEUEN KONFIGURATION ---")
    print(output)
else:
    with open(config_path, "w", encoding="utf-8") as f:
        f.write(output + "\n")
    print("OK")
'

echo "--> Konfiguration patchen..."
RESULT=$(python3 - "$CONFIG_PATH" "$PATCH_JSON" "$DRY_RUN" <<< "$PYTHON_SCRIPT")

if $DRY_RUN; then
  echo ""
  echo "$RESULT"
  echo ""
  warn "DRY-RUN beendet. Zum echten Patchen ohne --dry-run ausführen."
  exit 0
fi

if [[ "$RESULT" == "OK" ]]; then
  ok "openclaw.json erfolgreich gepatcht"
else
  err "Fehler beim Patchen der Konfiguration"
  echo "$RESULT"
  exit 1
fi

# ── Workspace-Dateien schreiben ───────────────────────────────────────────────
mkdir -p "$WORKSPACE_DIR"
echo "--> Workspace-Dateien aktualisieren..."

# AGENTS.md
cat > "$WORKSPACE_DIR/AGENTS.md" <<'AGENTS_EOF'
# AGENTS – Modell-Routing & Verhaltensregeln

## Modell-Auswahl (Token-Kostenoptimierung)

Nutze grundsätzlich das günstigste Modell, das für die jeweilige Aufgabe ausreicht.

| Aufgabe                                          | Modell     | Befehl      |
|--------------------------------------------------|------------|-------------|
| Einfache Fragen, Suche, Dateioperationen         | Haiku      | `/model haiku`  |
| Normale Konversation, Code, Erklärungen          | Sonnet     | `/model sonnet` |
| Architekturentscheidungen, Sicherheitsanalyse    | Sonnet     | `/model sonnet` |
| Komplexes Debugging, tiefes Reasoning, Strategie | Opus       | `/model opus`   |

**Faustregel:** Beginne immer mit Haiku. Nur wenn die Antwort unzureichend ist, wechsle zu Sonnet, ansonsten kannst du dich auch an die Aufforderung des Users orientieren. Wenn der User am "P1:" dann bedeutet das nutze Haiku, bei "P2:" nutzt du dann Sonnet und bei "P3:" nutzt du Opus.

## Session-Management (Kontext-Kosten senken)

- Nach jeder abgeschlossenen Aufgabe den user fragen, ob ein `/reset` ausgeführt werden soll, um die Session zu bereinigen.
- Vor einer neuen, unabhängigen Aufgabe: neue Session starten (`/new`).
- Mit `/status` den aktuellen Kontext-Füllstand überwachen.
- Mit `/usage tokens` Token-Verbrauch pro Antwort einblenden.

## Kommunikationsstil

- Antworten präzise und kurz halten – unnötige Ausführlichkeit erhöht Output-Tokens.
- Keine langen Einleitungen oder Zusammenfassungen, wenn nicht ausdrücklich gewünscht.
- Bei Unsicherheit: kurz nachfragen, statt eine lange Antwort zu raten.

## Bilder & Dateien

- Bilder nur senden, wenn sie für die Aufgabe notwendig sind.
- Große Dateien in kleinere Chunks aufteilen, statt alles auf einmal zu übergeben.
AGENTS_EOF
ok "AGENTS.md → $WORKSPACE_DIR/AGENTS.md"

# HEARTBEAT.md
cat > "$WORKSPACE_DIR/HEARTBEAT.md" <<'HEARTBEAT_EOF'
# HEARTBEAT – Minimale Aktionen

Dieser Heartbeat läuft alle 55 Minuten mit einem günstigen Modell (Haiku oder lokal).

## Aufgaben (nur wenn notwendig)

1. Prüfe, ob offene Erinnerungen in MEMORY.md vorhanden sind, die abgearbeitet werden sollen.
2. Wenn keine Aufgaben vorliegen: Antworte ausschließlich mit `NO_REPLY`.
3. Führe **keine** längeren Analysen oder Recherchen durch – das ist Aufgabe des Haupt-Agents.

## Wichtig

- Halte die Antwort unter 200 Zeichen.
- Keine langen Erklärungen, keine Listen, kein Smalltalk.
- `NO_REPLY` = kein Token-Output = minimale Kosten.
HEARTBEAT_EOF
ok "HEARTBEAT.md → $WORKSPACE_DIR/HEARTBEAT.md"

# ── Dienst neu starten ────────────────────────────────────────────────────────
if ! $NO_RESTART; then
  echo "--> OpenClaw-Dienst neu starten..."
  if systemctl is-active --quiet openclaw 2>/dev/null; then
    sudo systemctl restart openclaw
    ok "Dienst 'openclaw' neu gestartet"
  elif systemctl is-active --quiet clawdbot 2>/dev/null; then
    sudo systemctl restart clawdbot
    ok "Dienst 'clawdbot' neu gestartet"
  else
    warn "Kein aktiver systemd-Dienst gefunden – bitte OpenClaw manuell neu starten."
    warn "  openclaw stop && openclaw start"
  fi
else
  warn "Dienst-Neustart übersprungen (--no-restart)."
  warn "Bitte manuell neu starten: openclaw stop && openclaw start"
fi

# ── Zusammenfassung ───────────────────────────────────────────────────────────
echo ""
echo "════════════════════════════════════════════════════════════"
echo -e " ${GREEN}Update erfolgreich!${RESET}"
echo ""
echo " Angewendete Optimierungen:"
echo "   • Model-Routing   Sonnet (Standard) → Haiku (Fallback)"
echo "   • P1/P2/P3-Prefix Haiku / Sonnet / Opus per Chat-Befehl"
echo "   • Heartbeat        Haiku, 55min, max 200 Zeichen Antwort"
echo "   • Context-Pruning  cache-ttl 1h → 40–60% weniger Tokens"
echo "   • Compaction       safeguard-Modus mit memoryFlush"
echo "   • Bilder           max 800px (weniger Vision-Tokens)"
echo "   • Bootstrap        8.000 / 40.000 Zeichen Limit"
echo "   • Sicherheit       bind: loopback (Gateway nicht öffentlich)"
echo ""
echo " Backup der alten Config: $BACKUP"
echo ""
echo " Nützliche Chat-Befehle nach dem Neustart:"
echo "   /status          Modell & Kontext-Füllstand"
echo "   /usage tokens    Token-Zähler einblenden"
echo "   /model haiku     Auf Haiku wechseln (= P1:)"
echo "   /model sonnet    Auf Sonnet wechseln (= P2:)"
echo "   /model opus      Auf Opus wechseln (= P3:)"
echo "════════════════════════════════════════════════════════════"
echo ""
