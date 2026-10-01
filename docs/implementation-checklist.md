# Umstrukturierung und mobile Bedienung · 02.10.2026

Arbeitsauftrag: vorhandenen vollständigen Funktionsport erhalten, Flutter unter
`app/` bündeln, SDKs außerhalb des Repos betreiben, Android-/iOS-Artefakte auf
`master` bauen und eine sichere spätere Verteilung vorbereiten. PyQt bleibt
unveränderte Referenz. Die vorhandenen uncommitteten Arbeiten werden mitgenommen.

## Umsetzung und Abnahme

- [x] Bestand, Worktrees, SDKs, Pfadabhängigkeiten und Desktop-Publishvertrag prüfen.
- [x] Flutter-Quellen einschließlich nativer Projekte nach `app/` verschieben.
- [x] Externe SDKs auf C: prüfen, lokale Befehle und Dokumentation aktualisieren.
- [x] Master-CI, getrennte mobile Artefakte, Signierung und Serververtrag vorbereiten.
- [x] Unbegrenzt parkbare Vorgänge mit Migration und Reservierungsprüfung umsetzen.
- [x] Vorhandenes Redesign vereinheitlichen, alle Port-Funktionen erreichbar halten.
- [x] Nach zusammenhängender Umsetzung Format, Analyse, Tests und Android-Build prüfen.
- [x] Funktionsmatrix, Prüfbericht und kanonisches Projektwissen aktualisieren.

Flutter-interne Zwischendateien bleiben in `app/build/`, damit Plugins und Xcode
Standardpfade verwenden. `build/android/` und `build/ios/` enthalten gesammelte
Auslieferungs-/Prüfartefakte. Beide Buildbereiche sind ignoriert.

Besonders zu prüfen: Altentwürfe und Sicherungswiederherstellung, Reservierungen
über alle geparkten Vorgänge, fehlgeschlagene SQLite-Abschlüsse, kleine Displays
mit großer Schrift, versteckter Scannerfokus und Signierung vor Veröffentlichung.

Die dauerhafte Architekturentscheidung wird im Mobile-Projektkompass des
Obsidian-Vaults geführt; diese Liste ist nur die technische Abnahme im Repository.
