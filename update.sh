#!/usr/bin/env bash
# ============================================================
# OpenClaw Token-Optimierung – Update-Skript (v2.0)
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
#   --dry-run              Zeigt geplante Änderungen, ohne sie zu schreiben
#   --no-restart           Dienst nach dem Update nicht neu starten
#   --rollback             Letztes Update rückgängig machen
#   --rollback <timestamp> Bestimmten Snapshot wiederherstellen
#   --list-rollbacks       Alle verfügbaren Snapshots auflisten
# ============================================================
set -euo pipefail

# ── Argumente ─────────────────────────────────────────────────────────────────
DRY_RUN=false
NO_RESTART=false
MODE="update"           # update | rollback | list-rollbacks
ROLLBACK_TS=""          # leer = neuester Snapshot

for arg in "$@"; do
  case "$arg" in
    --dry-run)         DRY_RUN=true ;;
    --no-restart)      NO_RESTART=true ;;
    --list-rollbacks)  MODE="list-rollbacks" ;;
    --rollback)        MODE="rollback" ;;
    --rollback=*)      MODE="rollback"; ROLLBACK_TS="${arg#--rollback=}" ;;
    [0-9]*)            ROLLBACK_TS="$arg" ;;   # Timestamp direkt nach --rollback
    *) echo "Unbekannte Option: $arg"; exit 1 ;;
  esac
done

# ── Farben ────────────────────────────────────────────────────────────────────
GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; CYAN='\033[0;36m'; RESET='\033[0m'
ok()    { echo -e "${GREEN}  ✓${RESET} $*"; }
warn()  { echo -e "${YELLOW}  !${RESET} $*"; }
err()   { echo -e "${RED}  ✗${RESET} $*"; }
info()  { echo -e "${CYAN}  →${RESET} $*"; }

# ── Hilfsfunktionen ───────────────────────────────────────────────────────────

# Konfigurationspfad ermitteln (auch für Rollback benötigt)
find_config() {
  local candidates=(
    "$HOME/.openclaw/openclaw.json"
    "$HOME/.clawdbot/clawdbot.json"
  )
  for c in "${candidates[@]}"; do
    if [[ -f "$c" ]]; then echo "$c"; return; fi
  done
  # Beim Rollback: Verzeichnis aus dem Manifest nehmen
  echo ""
}

# Gateway neu starten
restart_service() {
  if $NO_RESTART; then
    warn "Gateway-Neustart übersprungen (--no-restart)."
    warn "Bitte manuell neu starten: openclaw gateway restart"
    return
  fi
  info "OpenClaw-Gateway neu starten..."
  if command -v openclaw &>/dev/null; then
    if openclaw gateway restart 2>/dev/null; then
      ok "Gateway neu gestartet (openclaw gateway restart)"
    else
      warn "Gateway-Neustart fehlgeschlagen – bitte manuell ausführen:"
      warn "  openclaw gateway restart"
    fi
  else
    warn "openclaw CLI nicht gefunden – bitte manuell neu starten:"
    warn "  openclaw gateway restart"
  fi
}

# ══════════════════════════════════════════════════════════════
#  MODUS: --list-rollbacks
# ══════════════════════════════════════════════════════════════
if [[ "$MODE" == "list-rollbacks" ]]; then
  CONFIG_PATH="$(find_config)"
  CONFIG_DIR="${CONFIG_PATH:+$(dirname "$CONFIG_PATH")}"
  ROLLBACK_BASE="${CONFIG_DIR:-$HOME/.openclaw}/.rollback"

  echo ""
  echo "════════════════════════════════════════════════════════════"
  echo " OpenClaw – verfügbare Rollback-Snapshots"
  echo "════════════════════════════════════════════════════════════"
  echo ""

  if [[ ! -d "$ROLLBACK_BASE" ]] || [[ -z "$(ls -A "$ROLLBACK_BASE" 2>/dev/null)" ]]; then
    warn "Keine Snapshots gefunden in: $ROLLBACK_BASE"
    echo ""
    exit 0
  fi

  i=1
  for dir in $(ls -r "$ROLLBACK_BASE"); do
    manifest="$ROLLBACK_BASE/$dir/manifest.json"
    if [[ ! -f "$manifest" ]]; then continue; fi
    ts_human=$(python3 -c "
import json, datetime
m = json.load(open('$manifest'))
dt = datetime.datetime.fromisoformat(m['timestamp'])
print(dt.strftime('%d.%m.%Y %H:%M:%S'))
" 2>/dev/null || echo "$dir")
    files=$(python3 -c "
import json
m = json.load(open('$manifest'))
lines = []
for f in m['files']:
    action = {'modified':'geändert','created':'neu erstellt'}.get(f['action'], f['action'])
    lines.append(f\"  {f['target'].split('/')[-1]} ({action})\")
print('\n'.join(lines))
" 2>/dev/null || echo "  (Details nicht lesbar)")

    marker=""
    if [[ $i -eq 1 ]]; then marker=" ${GREEN}← neuester${RESET}"; fi
    echo -e " ${CYAN}[$i]${RESET} Snapshot: ${YELLOW}$dir${RESET}${marker}"
    echo "     Datum:    $ts_human"
    echo "     Dateien:"
    echo "$files"
    echo ""
    echo "     Rückgängig machen mit:"
    echo "       ./oc-update.sh --rollback $dir"
    echo ""
    ((i++))
  done

  echo "════════════════════════════════════════════════════════════"
  echo ""
  exit 0
fi

# ══════════════════════════════════════════════════════════════
#  MODUS: --rollback
# ══════════════════════════════════════════════════════════════
if [[ "$MODE" == "rollback" ]]; then
  CONFIG_PATH="$(find_config)"
  CONFIG_DIR="${CONFIG_PATH:+$(dirname "$CONFIG_PATH")}"
  ROLLBACK_BASE="${CONFIG_DIR:-$HOME/.openclaw}/.rollback"

  echo ""
  echo "════════════════════════════════════════════════════════════"
  echo " OpenClaw – Rollback"
  if $DRY_RUN; then echo -e " ${YELLOW}[DRY-RUN]${RESET}"; fi
  echo "════════════════════════════════════════════════════════════"
  echo ""

  if [[ ! -d "$ROLLBACK_BASE" ]]; then
    err "Kein Rollback-Verzeichnis gefunden: $ROLLBACK_BASE"
    exit 1
  fi

  # Snapshot auswählen
  if [[ -z "$ROLLBACK_TS" ]]; then
    ROLLBACK_TS=$(ls -r "$ROLLBACK_BASE" 2>/dev/null | head -1)
    if [[ -z "$ROLLBACK_TS" ]]; then
      err "Keine Snapshots vorhanden."
      exit 1
    fi
    info "Neuesten Snapshot ausgewählt: $ROLLBACK_TS"
  fi

  SNAPSHOT_DIR="$ROLLBACK_BASE/$ROLLBACK_TS"
  MANIFEST="$SNAPSHOT_DIR/manifest.json"

  if [[ ! -f "$MANIFEST" ]]; then
    err "Snapshot nicht gefunden: $SNAPSHOT_DIR"
    err "Verfügbare Snapshots: ./oc-update.sh --list-rollbacks"
    exit 1
  fi

  ok "Snapshot gefunden: $ROLLBACK_TS"

  # Manifest einlesen und Dateien wiederherstellen
  python3 - "$MANIFEST" "$SNAPSHOT_DIR" "$DRY_RUN" <<'ROLLBACK_PY'
import json, shutil, sys, os

manifest_path = sys.argv[1]
snapshot_dir  = sys.argv[2]
dry_run       = sys.argv[3] == "true"

with open(manifest_path, "r") as f:
    manifest = json.load(f)

print(f"  Timestamp: {manifest['timestamp']}")
print("")

for entry in manifest["files"]:
    target  = entry["target"]
    action  = entry["action"]
    backup  = entry.get("backup")   # relativer Pfad im Snapshot, oder None

    if action == "modified":
        # Datei existierte vor dem Update → Original wiederherstellen
        src = os.path.join(snapshot_dir, backup)
        if not os.path.isfile(src):
            print(f"  ✗ Backup fehlt: {src}")
            sys.exit(1)
        if dry_run:
            print(f"  [DRY] Wiederherstellen: {target}")
        else:
            os.makedirs(os.path.dirname(target), exist_ok=True)
            shutil.copy2(src, target)
            print(f"  ✓ Wiederhergestellt: {target}")

    elif action == "created":
        # Datei wurde neu erstellt → löschen
        if dry_run:
            print(f"  [DRY] Löschen (war nicht vorhanden): {target}")
        else:
            if os.path.isfile(target):
                os.remove(target)
                print(f"  ✓ Gelöscht (war nicht vorhanden): {target}")
            else:
                print(f"  - Bereits nicht vorhanden: {target}")

print("")
if not dry_run:
    print("ROLLBACK_OK")
ROLLBACK_PY

  if ! $DRY_RUN; then
    restart_service
    echo ""
    echo "════════════════════════════════════════════════════════════"
    echo -e " ${GREEN}Rollback erfolgreich!${RESET}"
    echo " Snapshot $ROLLBACK_TS wurde wiederhergestellt."
    echo "════════════════════════════════════════════════════════════"
    echo ""
  else
    echo ""
    warn "DRY-RUN beendet. Zum echten Rollback ohne --dry-run ausführen:"
    echo "  ./oc-update.sh --rollback $ROLLBACK_TS"
    echo ""
  fi
  exit 0
fi

# ══════════════════════════════════════════════════════════════
#  MODUS: update (Standard)
# ══════════════════════════════════════════════════════════════
echo ""
echo "════════════════════════════════════════════════════════════"
echo " OpenClaw Token-Optimierung – Update (v2.0)"
if $DRY_RUN; then echo -e " ${YELLOW}[DRY-RUN – keine Dateien werden geschrieben]${RESET}"; fi
echo "════════════════════════════════════════════════════════════"
echo ""

# ── Abhängigkeiten prüfen ─────────────────────────────────────────────────────
if ! command -v python3 &>/dev/null; then
  err "python3 nicht gefunden. Installation: sudo apt-get install python3"
  exit 1
fi

# ── Konfigurationspfad ermitteln ──────────────────────────────────────────────
CONFIG_PATH="$(find_config)"
if [[ -z "$CONFIG_PATH" ]]; then
  err "Keine OpenClaw-Konfiguration gefunden."
  err "Gesucht in: ~/.openclaw/openclaw.json  ~/.clawdbot/clawdbot.json"
  exit 1
fi
ok "Konfiguration gefunden: $CONFIG_PATH"

CONFIG_DIR="$(dirname "$CONFIG_PATH")"
WORKSPACE_DIR="$CONFIG_DIR/workspace"
ROLLBACK_BASE="$CONFIG_DIR/.rollback"
TIMESTAMP="$(date +%Y%m%d%H%M%S)"
SNAPSHOT_DIR="$ROLLBACK_BASE/$TIMESTAMP"

# ── Rollback-Snapshot anlegen ─────────────────────────────────────────────────
# Vor jeder Änderung: Originalzustand aller betroffenen Dateien sichern.
# Das Manifest dokumentiert für jede Datei:
#   "modified" → Original-Backup liegt im Snapshot → wird bei Rollback wiederhergestellt
#   "created"  → Datei existierte vorher nicht     → wird bei Rollback gelöscht

AGENTS_TARGET="$WORKSPACE_DIR/AGENTS.md"
HEARTBEAT_TARGET="$WORKSPACE_DIR/HEARTBEAT.md"

build_manifest() {
  local config_existed=True   # Config muss existieren (oben geprüft)
  local agents_existed=False
  local heartbeat_existed=False

  [[ -f "$AGENTS_TARGET"    ]] && agents_existed=True
  [[ -f "$HEARTBEAT_TARGET" ]] && heartbeat_existed=True

  # Manifest-JSON bauen
  python3 - <<MANIFEST_PY
import json

entries = []

# Config wurde immer modifiziert
entries.append({
    "target": "$CONFIG_PATH",
    "action": "modified",
    "backup": "openclaw.json"
})

# AGENTS.md
if $agents_existed:
    entries.append({"target": "$AGENTS_TARGET", "action": "modified", "backup": "AGENTS.md"})
else:
    entries.append({"target": "$AGENTS_TARGET", "action": "created",  "backup": None})

# HEARTBEAT.md
if $heartbeat_existed:
    entries.append({"target": "$HEARTBEAT_TARGET", "action": "modified", "backup": "HEARTBEAT.md"})
else:
    entries.append({"target": "$HEARTBEAT_TARGET", "action": "created",  "backup": None})

import datetime
manifest = {
    "timestamp": datetime.datetime.now().isoformat(timespec="seconds"),
    "version":   "2.0",
    "files":     entries
}
print(json.dumps(manifest, indent=2, ensure_ascii=False))
MANIFEST_PY
}

if $DRY_RUN; then
  warn "DRY-RUN: Snapshot würde erstellt werden in: $SNAPSHOT_DIR"
else
  mkdir -p "$SNAPSHOT_DIR"

  # Config sichern
  cp "$CONFIG_PATH" "$SNAPSHOT_DIR/openclaw.json"

  # AGENTS.md sichern, falls vorhanden
  [[ -f "$AGENTS_TARGET"    ]] && cp "$AGENTS_TARGET"    "$SNAPSHOT_DIR/AGENTS.md"
  [[ -f "$HEARTBEAT_TARGET" ]] && cp "$HEARTBEAT_TARGET" "$SNAPSHOT_DIR/HEARTBEAT.md"

  # Manifest schreiben
  build_manifest > "$SNAPSHOT_DIR/manifest.json"

  ok "Rollback-Snapshot erstellt: $SNAPSHOT_DIR"
fi

# ── JSON-Patch (via Python3) ──────────────────────────────────────────────────
PATCH_JSON='{
  "agents": {
    "defaults": {
      "model": {
        "primary": "anthropic/claude-haiku-4-5",
        "fallbacks": [
          "anthropic/claude-sonnet-4-6",
          "openrouter/openrouter/auto"
        ]
      },
      "models": {
        "anthropic/claude-haiku-4-5":  { "alias": "haiku"  },
        "anthropic/claude-sonnet-4-6": { "alias": "sonnet" },
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
        "every": "6h",
        "model": "anthropic/claude-haiku-4-5",
        "includeReasoning": false,
        "ackMaxChars": 1000,
        "suppressToolErrorWarnings": true,
        "prompt": "Lies HEARTBEAT.md, falls vorhanden. Fuehre nur aus, was dort steht. Antworte mit NO_REPLY, wenn keine Aktion noetig."
      },
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

PYTHON_PATCH='
import json, re, sys

def strip_comments(text):
    lines = []
    for line in text.splitlines():
        stripped = re.sub(r"\s*//.*$", "", line)
        lines.append(stripped)
    text = "\n".join(lines)
    text = re.sub(r",(\s*[}\]])", r"\1", text)
    return text

def deep_merge(base, patch):
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

patch  = json.loads(patch_json)
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

info "Konfiguration patchen..."
RESULT=$(python3 - "$CONFIG_PATH" "$PATCH_JSON" "$DRY_RUN" <<< "$PYTHON_PATCH")

if $DRY_RUN; then
  echo ""
  echo "$RESULT"
  echo ""
  warn "DRY-RUN beendet. Zum echten Update ohne --dry-run ausführen."
  exit 0
fi

[[ "$RESULT" == "OK" ]] && ok "openclaw.json erfolgreich gepatcht" || { err "Fehler beim Patchen"; echo "$RESULT"; exit 1; }

# ── Workspace-Dateien schreiben ───────────────────────────────────────────────
mkdir -p "$WORKSPACE_DIR"
info "Workspace-Dateien aktualisieren..."

cat > "$AGENTS_TARGET" <<'AGENTS_EOF'
# AGENTS – Modell-Routing & Verhaltensregeln

## Modell-Auswahl (Token-Kostenoptimierung)

Nutze grundsätzlich das günstigste Modell, das für die jeweilige Aufgabe ausreicht.

| Aufgabe                                          | Modell            | Prefix | Befehl          |
|--------------------------------------------------|-------------------|--------|-----------------|
| Einfache Fragen, Suche, Dateioperationen         | Haiku 4.5         | `P1:`  | `/model haiku`  |
| Normale Konversation, Code, Erklärungen          | Sonnet 4.6        | `P2:`  | `/model sonnet` |
| Architekturentscheidungen, Sicherheitsanalyse    | Sonnet 4.6        | `P2:`  | `/model sonnet` |
| Komplexes Debugging, tiefes Reasoning, Strategie | Opus 4.6          | `P3:`  | `/model opus`   |

**Faustregel:** Das Standard-Modell ist **Haiku 4.5 (P1:)**. Beginne immer damit. Schreibt der User `P2:` am Anfang seiner Nachricht, nutze **Sonnet 4.6**. Schreibt der User `P3:`, nutze **Opus 4.6**. Mit `P1:` kehrst du zu **Haiku 4.5** zurück.

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
ok "AGENTS.md → $AGENTS_TARGET"

cat > "$HEARTBEAT_TARGET" <<'HEARTBEAT_EOF'
# HEARTBEAT – Minimale Aktionen

Dieser Heartbeat läuft alle 6 Stunden (08:00, 14:00, 20:00 Uhr) mit einem günstigen Modell (Haiku oder lokal).

## Aufgaben (nur wenn notwendig)

1. Prüfe, ob offene Erinnerungen in MEMORY.md vorhanden sind, die abgearbeitet werden sollen.
2. Wenn keine Aufgaben vorliegen: Antworte ausschließlich mit `NO_REPLY`.
3. Führe **keine** längeren Analysen oder Recherchen durch – das ist Aufgabe des Haupt-Agents.

## Wichtig

- Halte die Antwort unter 1000 Zeichen.
- Keine langen Erklärungen, keine Listen, kein Smalltalk.
- `NO_REPLY` = kein Token-Output = minimale Kosten.
HEARTBEAT_EOF
ok "HEARTBEAT.md → $HEARTBEAT_TARGET"

# ── Dienst neu starten ────────────────────────────────────────────────────────
restart_service

# ── Zusammenfassung ───────────────────────────────────────────────────────────
echo ""
echo "════════════════════════════════════════════════════════════"
echo -e " ${GREEN}Update erfolgreich!${RESET}"
echo ""
echo " Angewendete Optimierungen:"
echo "   • Model-Routing   Haiku 4.5 (Standard/P1:) · Sonnet 4.6 (P2:) · Opus 4.6 (P3:)"
echo "   • P1/P2/P3-Prefix Haiku 4.5 / Sonnet 4.6 / Opus 4.6 per Chat-Befehl"
echo "   • Heartbeat        Haiku, alle 6h (08–24 Uhr), max 1000 Zeichen Antwort"
echo "   • Context-Pruning  cache-ttl 1h → 40–60% weniger Tokens"
echo "   • Compaction       safeguard-Modus mit memoryFlush"
echo "   • Bootstrap        8.000 / 40.000 Zeichen Limit"
echo "   • Sicherheit       bind: loopback (Gateway nicht öffentlich)"
echo ""
echo " Rollback-Snapshot: $TIMESTAMP"
echo ""
echo -e " ${YELLOW}Update rückgängig machen:${RESET}"
echo "   ./oc-update.sh --rollback"
echo ""
echo " Alle Snapshots anzeigen:"
echo "   ./oc-update.sh --list-rollbacks"
echo ""
echo " Nützliche Chat-Befehle:"
echo "   /status          Modell & Kontext-Füllstand"
echo "   /usage tokens    Token-Zähler einblenden"
echo "   /model haiku     Auf Haiku 4.5 wechseln  (= P1: Standard)"
echo "   /model sonnet    Auf Sonnet 4.6 wechseln (= P2:)"
echo "   /model opus      Auf Opus 4.6 wechseln   (= P3:)"
echo "════════════════════════════════════════════════════════════"
echo ""
