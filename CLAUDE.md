# Flohmarkt NextGen Mobile App

Mobile Kassensoftware der MarketMate-Plattform, Android und iOS mit Flutter/Dart.
Desktop-Referenz: `../FlohmarktNextGenApp`. Diese bleibt im Parallelbetrieb.

<!-- OBSIDIAN-SECOND-BRAIN:START -->
## Obsidian Second Brain

**Projekt:** MarketMate / Flohmarkt NextGen Mobile App · **Person:** Christof

Bei Planung, Architektur, Status und dauerhaftem Wissen den Skill
`obsidian-second-brain` verwenden. Den physischen Vault mit dessen
`scripts/resolve_vault_context.py` auflösen; aktuell `D:/OneDrive/ObsidianBrain`.
Zuerst `Brain.md` und die passenden Regelmodule lesen, dann:

- `02 Projekte/MarketMate/Flohmarkt NextGen Mobile App/Flohmarkt NextGen Mobile App.md`
- `02 Projekte/MarketMate/Flohmarkt NextGen Mobile App/Projektkompass Mobile.md`
- Nur bei Bedarf die verlinkte Analyse und den Umsetzungsplan.

Große L3-Quellen nur gezielt über Subagenten laden: `Konzept Datenkommunikation.md`,
`Architektur-Referenz.md`, `Datenbank-Schema.md`, `Umsetzungsplan Anbindung FlohmarktNextGenApp.md`.
L1 → L2 → L3 einhalten. Dauerhafte Entscheidungen kanonisch im Vault festhalten;
keine Kopien langer Konzepte im Repo. AGENTS.md und CLAUDE.md identisch halten.
<!-- OBSIDIAN-SECOND-BRAIN:END -->

## Entwicklungsregeln

- Fachlogik in `lib/domain/`, SQLite in `lib/data/`, Eingabe und UI in `lib/ui/`.
- Geld ausschließlich als Integer-Cent. Kein double für Geldberechnungen.
- Markt, Kasse, Exportgeneration, Listing und akzeptierte Etikettenrevision binden.
- V2-Scans: MM1-Payload mit CRC32 und Luhn validieren; revisionslose Scans ablehnen.
- Verkäufernummer aus codeFull ist NICHT die marktbezogene Box/Stammnummer.
- Scan reserviert im lokalen Warenkorb; erst bestätigter, atomar gespeicherter
  Abschluss erzeugt Verkäufe. Fehlgeschlagene Speicherung darf keinen Erfolg melden.
- UUIDv7-Ereignisse und UTC-Zeitpunkte dauerhaft speichern. Storno als neues
  Ereignis mit Verweis auf Original; keine Löschung/Mutation des Verkaufs.
- Offline verhindert keine Doppelverkäufe zwischen Geräten. Konflikte später
  ausdrücklich auflösen; keinen garantierten globalen Bestand behaupten.
- Keine realen Kundendaten, Tokens oder Exporte in Git. Demo klar kennzeichnen.
- Kamera nur im Scanbildschirm, Berechtigungsfehler sichtbar und manuelle Eingabe
  weiter verfügbar. HID-Eingaben nur am vorgesehenen Feld, Abschluss per Enter.
- Kein produktiver Upload, Release oder Hardwareversprechen ohne entsprechende Prüfung.
- Prüfen: `dart format --output=none --set-exit-if-changed lib test`,
  `flutter analyze`, `flutter test`. Native Builds separat prüfen.

## GitNexus

Für Codeanalyse GitNexus verwenden; Repository explizit `FlohmarktNextGenMobileApp`.
Indexstände prüfen; aktuelle Quelldateien bleiben maßgeblich. Nach größeren
Änderungen sequenziell `gitnexus analyze --index-only` ausführen, mit
`GITNEXUS_STORAGE_ROOT=C:/Users/NoName/.gitnexus/indexes`.
Die lokal angepasste Installation NICHT aktualisieren; vorher
`C:/Users/NoName/.gitnexus/LOCAL-INSTALLATION.md` beachten.
Dart-Unterstützung der installierten Version überprüfen. Nicht erfasste Dart-
Symbole transparent benennen; Dateiknoten sind kein vollständiger Aufrufgraph.
Bei Ausfall begrenzt diagnostizieren und mit Quelltextanalyse/Tests fortfahren.

## Verbindliches Ziel: vollständiger Port

Seit dem Folgeauftrag vom 26.09.2026 ALLE Features aus FlohmarktNextGenApp auf
Android/iOS übertragen. Die frühere Demo-Beschränkung und der Ausschluss von
Verwaltung, Abrechnung, Konsolidierung oder Rücksortierung sind aufgehoben.
`docs/feature-parity.md` verfolgt jedes Desktop-Feature samt Quelle und Abnahme.
Bestehende PyQt-Dateien nur lesen; dortige parallele Änderungen nicht anfassen.
Mobile Betriebssystemgrenzen durch funktionale mobile Entsprechungen abdecken
(z. B. Dateiauswahl/Teilen, PDF/Systemdruck statt Windows-Spooler).
Erst dann als vollständig bezeichnen, wenn die Featurematrix und Prüfungen das
belegen. Offene Hardware-/Signierungsprüfungen getrennt von Implementierung nennen.
