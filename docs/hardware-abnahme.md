# Hardware-Abnahme vor dem Pilot

Status: offen. Keine Scanner-/Smartphone-Kombination ist bisher freigegeben.
Softwareprüfung 26.09.2026: Android-Debug-APK lokal gebaut, 106 automatisierte
Tests erfolgreich, Analyse/Formatierung fehlerfrei. `adb devices` meldet kein
angeschlossenes Gerät. iOS-Build und Signierung sind auf diesem Windows-Host
nicht geprüft. Diese Nachweise ersetzen keine der folgenden Geräteprüfungen.
Kanonische Architektur/Planung: Obsidian → MarketMate → Flohmarkt NextGen Mobile App.
Diese Checkliste gehört zur ausführbaren Software und hält konkrete Prüfresultate fest.

| Kombination | OS / Scanner-Firmware / Adapter | Ergebnis |
|---|---|---|
| Android + USB-HID | Noch nicht benannt | Nicht geprüft |
| Android + Kamera | Noch nicht benannt | Nicht geprüft |
| iPhone + Kamera | Noch nicht benannt | Nicht geprüft |
| iPhone + HID | Noch nicht benannt | Nicht geprüft |

Pro Kombination dokumentieren: Modell, OS-Version, Scanner-Modus, Tastaturlayout,
USB-/Lightning-/Bluetooth-Adapter, Stromversorgung und Datum. HID bedeutet
Tastatureingabe in das Scan-Feld; die App ist kein serieller USB-Treiber.

- [ ] Demopayload aus README als Code128 bzw. QR auf Papier und Display lesen.
- [ ] HID überträgt insbesondere `|` unverändert; Enter/CRLF löst genau einmal aus.
- [ ] Zwei verschiedene Artikel und denselben Artikel mehrfach hintereinander scannen.
- [ ] Nach manuellem Dialog, Zahlung, Belegansicht und Scanner-Reconnect Fokus prüfen.
- [ ] Kamerarechte verweigern/gewähren; Fallback manuell weiterhin möglich.
- [ ] Hintergrund/Vordergrund, Sperren/Entsperren und Kameraroute wiederholt wechseln.
- [ ] Ohne Netz und nach kaltem Start Kamera öffnen (Android-Modell gebündelt).
- [ ] App mit offenem Warenkorb beenden; Entwurf und Warnhinweis nach Neustart prüfen.
- [ ] App nach Zahlungsbestätigung beenden; genau ein Beleg nach Neustart.
- [ ] Storno, Neustart und Wiederverkauf: Original und Storno erhalten.
- [ ] USB-Hub gleichzeitig laden, Kabelwechsel und Langzeitscannen testen.
- [ ] Kleine Displays, Querformat und große Systemschrift prüfen.

Ein lokaler Demo-Test belegt keine produktive Backendintegration. Für den Pilot
zusätzlich echte Exportfixtures, Auth/Outbox/Upload, Konflikte, Datensicherung und
Rollen für Storno gemäß Second-Brain-Plan abnehmen.
