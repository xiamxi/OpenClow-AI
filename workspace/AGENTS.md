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
