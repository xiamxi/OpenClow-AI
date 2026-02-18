# OpenClaw VPS – Token-optimierte Konfiguration

Dieses Repository enthält eine vorkonfigurierte, token-kostenoptimierte OpenClaw-Installation für VPS-Betrieb.

**Erwartete Einsparung: 60–77 % der Tokenkosten** gegenüber einer Standard-Installation.

---

## Schnellstart

### OpenClaw bereits installiert → Update-Skript

Das Skript:
- erkennt automatisch den Konfigurationspfad (`~/.openclaw/` oder `~/.clawdbot/`)
- legt vor jeder Änderung einen vollständigen Rollback-Snapshot an
- patcht **nur** die Optimierungs-Schlüssel (API-Keys, Kanäle, eigene Agenten bleiben erhalten)
- aktualisiert `AGENTS.md` und `HEARTBEAT.md` im Workspace
- startet den Dienst neu (sofern systemd aktiv)

#### Option A – Download via curl (wenn Repo auf GitHub veröffentlicht)

Die Raw-URL hängt vom Branch-Namen ab. Schema:

```
https://raw.githubusercontent.com/<user>/<repo>/<branch>/update.sh
```

Beispiel für dieses Repo:

```bash
curl -fsSL https://raw.githubusercontent.com/xiamxi/OpenClow-AI/claude/optimize-openclaw-vps-UUdKV/update.sh \
     -o oc-update.sh
chmod +x oc-update.sh
./oc-update.sh
```

#### Option B – Direkt auf den VPS kopieren (empfohlen bei privatem Repo)

Vom lokalen Rechner aus:

```bash
scp update.sh user@<vps-ip>:~/oc-update.sh
```

Dann auf dem VPS:

```bash
chmod +x oc-update.sh
./oc-update.sh
```

#### Option C – Via git clone

```bash
git clone https://github.com/xiamxi/OpenClow-AI.git
cd OpenClow-AI
git checkout claude/optimize-openclaw-vps-UUdKV
chmod +x update.sh
./update.sh
```

---

### Alle verfügbaren Befehle

| Befehl | Funktion |
|---|---|
| `./oc-update.sh` | Update anwenden |
| `./oc-update.sh --dry-run` | Vorschau – keine Änderungen |
| `./oc-update.sh --no-restart` | Update ohne Dienst-Neustart |
| `./oc-update.sh --rollback` | Letztes Update rückgängig machen |
| `./oc-update.sh --rollback 20260218143000` | Bestimmten Snapshot wiederherstellen |
| `./oc-update.sh --list-rollbacks` | Alle Snapshots mit Datum anzeigen |
| `./oc-update.sh --rollback --dry-run` | Rollback-Vorschau ohne Änderungen |

---

### Neue Installation → Setup-Skript

```bash
git clone <dieses-repo>
cd OpenClow-AI
chmod +x setup.sh
./setup.sh
openclaw config set anthropic.apiKey sk-ant-...
sudo systemctl start openclaw
```

---

## Optimierungen im Überblick

### 1. Modell-Routing (spart 50–70 %)

Nicht jede Aufgabe braucht Opus. Die Konfiguration setzt Sonnet als Standard und Haiku als Fallback:

| Situation              | Modell  | Kosten/1M Tokens (ca.) |
|------------------------|---------|------------------------|
| Standard               | Sonnet  | ~$3                    |
| Einfache Aufgaben      | Haiku   | ~$0.25                 |
| Komplexes Reasoning    | Opus    | ~$15                   |

Im Chat wechseln: `/model haiku` oder `/model sonnet`

### 2. Context-Pruning (spart 40–60 %)

```json
"contextPruning": { "mode": "cache-ttl", "ttl": "1h" }
```

Sessions werden nach 1 Stunde Inaktivität gestutzt. Der Kontext wächst nicht unbegrenzt an.
**Manuell zurücksetzen** nach abgeschlossenen Aufgaben: `/reset`

### 3. Heartbeat optimiert (spart bis zu 100 % der Heartbeat-Kosten)

Heartbeats laufen mit Haiku statt Sonnet/Opus und antworten meist mit `NO_REPLY`.
Alternativ: lokales Ollama-Modell → 0 Tokenkosten.

```json
"heartbeat": {
  "every": "55m",
  "model": "anthropic/claude-haiku-4-5",
  "ackMaxChars": 200
}
```

Der 55-Minuten-Rhythmus hält den Cache warm (Cache-TTL meist 1h) und verhindert teure Re-Caching-Kosten.

### 4. Kleinere Bilder (spart 10–30 % bei visuellen Aufgaben)

```json
"imageMaxDimensionPx": 800
```

Bilder werden vor dem API-Call auf 800px skaliert. Für OCR-intensive Aufgaben auf 1200 erhöhen.

### 5. Kompakter Bootstrap (spart 5–15 % pro Call)

```json
"bootstrapMaxChars": 8000,
"bootstrapTotalMaxChars": 40000
```

Der System-Prompt wird auf das Nötigste begrenzt. Standard-Werte sind 20.000 / 150.000 Zeichen.

### 6. Compaction im Safeguard-Modus

```json
"compaction": { "mode": "safeguard" }
```

Fasst lange Historien zusammen, bevor das Kontextfenster voll läuft, und speichert wichtige Infos in `MEMORY.md`.

---

## Nützliche Chat-Befehle

| Befehl              | Funktion                                              |
|---------------------|-------------------------------------------------------|
| `/status`           | Modell, Kontext-Füllstand, Kosten der letzten Antwort |
| `/usage tokens`     | Token-Zähler unter jede Antwort einblenden            |
| `/usage cost`       | Lokale Kostenzusammenfassung aus Session-Logs         |
| `/context list`     | Aufschlüsselung des System-Prompts nach Dateien       |
| `/context detail`   | Detaillierte Token-Aufschlüsselung                    |
| `/reset`            | Session zurücksetzen (Kontext leeren)                 |
| `/model haiku`      | Auf Haiku wechseln                                    |
| `/model sonnet`     | Auf Sonnet wechseln                                   |

---

## Sicherheit (VPS)

```json
"gateway": { "bind": "loopback" }
```

Das Gateway lauscht **nur auf 127.0.0.1**. Für Remote-Zugriff: SSH-Tunnel oder Tailscale verwenden – **niemals** `bind: "0.0.0.0"` ohne zusätzliche Absicherung.

---

## Lokales Ollama als kostenloser Heartbeat (optional)

Ollama installieren:
```bash
curl -fsSL https://ollama.ai/install.sh | sh
ollama pull llama3.2:3b
```

In `openclaw.json` den Heartbeat-Block auf Option B umstellen (siehe Kommentar in der Datei).

---

## Referenzen

- [Token Use and Costs – OpenClaw Docs](https://docs.openclaw.ai/reference/token-use)
- [Configuration Reference – OpenClaw Docs](https://docs.openclaw.ai/gateway/configuration-reference)
- [Why is OpenClaw so token-intensive? – Apiyi](https://help.apiyi.com/en/openclaw-token-cost-optimization-guide-en.html)
- [Cut OpenClaw Costs by 95% – Daily Dose of DS](https://blog.dailydoseofds.com/p/cut-openclaw-costs-by-95)
- [Smart Model Routing Guide – Zen van Riel](https://zenvanriel.nl/ai-engineer-blog/openclaw-api-cost-optimization-guide/)
- [OpenClaw Token-Costs 77% Reduction – ClawHosters](https://clawhosters.com/blog/posts/openclaw-token-costs-optimization)
- [Run OpenClaw 24/7 Without Breaking the Bank – perelweb](https://perelweb.be/blog/openclaw-token-management-smart-model-manager/)
