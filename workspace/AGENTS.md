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
