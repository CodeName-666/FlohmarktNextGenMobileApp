# Flohmarkt NextGen Mobile App

Flutter/Dart-Port der MarketMate-Kassensoftware für Android und iOS.
**Funktionsport implementiert; vollständige Geräte-/Produktionsabnahme noch offen.**
Die PyQt-Referenz bleibt unverändert im Parallelbetrieb.

## Umfang

Der aktuelle Arbeitsstand enthält lokale Markt-/Kassenbibliothek, V1/V2-Import,
SQLite-Kassenbetrieb, Kamera und HID, manuelle Verkäufer-/Artikeleingabe,
Rückgaben, getrennte Kundenkörbe, Belege, Artikel-/Kundensuche, Marktinformation,
Abrechnung, Statistik, Rücksortierung, PDF/Systemdruck und Dateiexporte.
Login, drei Uploadstufen, dauerhafte Outbox, Konfliktbearbeitung und Protokollarchiv
sind als eigene Module implementiert und werden gegen synthetische Verträge geprüft.

Die [Funktionsmatrix](docs/feature-parity.md) umfasst 85 Desktop-Funktionen.
Sie unterscheidet den ursprünglichen Demo-Ausgangsstand von der laufenden Abnahme.
Dateiexistenz und erfolgreiche Einzeltests bedeuten keine Produktionsfreigabe.

## Starten

Werkzeugstand: **Flutter 3.44.9 / Dart 3.12.2**. `pubspec.lock` fixiert Abhängigkeiten.
Die lokalen SDKs unter `.tooling/` sind nicht in Git enthalten.

```powershell
& ./.tooling/flutter/bin/flutter.bat pub get
& ./.tooling/flutter/bin/flutter.bat devices
& ./.tooling/flutter/bin/flutter.bat run -d <android-device-id>
```

Auf anderen Rechnern dieselbe Flutter-Version installieren. Android benötigt ein
Android SDK/JDK; iOS macOS/Xcode und für echte Geräte ein Signing-Team.
Unter **Märkte und Kassen** einen Export importieren, einen Demomarkt hinzufügen
oder über **Anmelden, Download und Synchronisation** einen Markt laden.
Kassennummer und Exportgeneration bleiben an die lokale Sitzung gebunden.
Weitere Kassen lassen sich innerhalb desselben Marktes anlegen.

Die Bibliothek und Kassendatenbanken liegen im privaten App-Datenverzeichnis.
Die frühere `marketmate_demo_v1.db` wird beim ersten Start übernommen.
Sicherungen über **Dateien und Sicherung** exportieren; Deinstallation oder
Löschen der App-Daten entfernt die lokale Datenbasis.

## Kassieren

HID-Scanner als Tastatur mit Enter-Suffix und passendem Tastaturlayout betreiben.
Das Zeichen `|` muss unverändert übertragen werden. Scan-Feld fokussieren;
die App verarbeitet vollständige Eingaben nacheinander. Es gibt keine pauschale
Freigabe für beliebige USB-Geräte; serielle oder proprietäre Scannerprotokolle
brauchen einen nachgewiesenen Geräteadapter.

V2 verlangt MM1 mit gültiger CRC32/Luhn und akzeptierter Etikettenrevision.
Manuell Verkäufernummer, Artikelnummer und sichtbare Revision eingeben.
Gleiche Kurznummern verschiedener Regionen müssen ausdrücklich zugeordnet werden.
V1 ist revisionslos und darf nicht als V2-Verkauf hochgeladen werden.

Scans speichern zunächst einen Entwurf. **Rückgabe vormerken** erzeugt eine
negative Position zum ursprünglichen Verkaufspreis; Entfernen verändert den
Originalverkauf nicht. Erst der bestätigte Abschluss erzeugt Ereignisse.
Ein geparkter Kundenkorb bleibt getrennt; Wechsel bestätigt keine Zahlung.
Ein nicht eingegebener Gegeben-Betrag bedeutet ausdrücklich keine Wechselgeldberechnung.

## Demo

Demomarkt in der Bibliothek hinzufügen und öffnen. Zwei synthetische Artikel:

```text
MM1|092700104200054|1|6BCD8E44
MM1|092700104200062|1|7DF55D18
```

Kinderbuch 2,50 Euro, Regenjacke 6,50 Euro. Verkäufer 42 ist von Box 7 getrennt.
Demo bleibt erkennbar; keine echten Kundendaten oder Zugangsdaten ins Repository legen.

## Prüfung und Grenzen

```powershell
& ./.tooling/flutter/bin/dart.bat format --output=none --set-exit-if-changed lib test
& ./.tooling/flutter/bin/flutter.bat analyze
& ./.tooling/flutter/bin/flutter.bat test
& ./.tooling/flutter/bin/flutter.bat build apk --debug
```

Die Tests prüfen unter anderem SQLite-Rollback, Migration, Neustart, Rückgabe,
Exportbindung, Importkonflikte, Revisionsprüfung, API-Verträge, ACK-Verhalten,
Verkäuferidentität, Gebührenrundung, Rücksortierung, Suche und Bedienung.
Gebühren verwenden rationale Integer-Cents und half-even; Statistik summiert
bereits gerundete Verkäufergebühren. Die bewussten Unterschiede zum Desktop
stehen in der Funktionsmatrix und im Second Brain.

Native Geräte, USB-/Bluetooth-Scanner, Kameraberechtigungen und physische Drucker
sind gesondert gemäß [Hardware-Abnahme](docs/hardware-abnahme.md) zu prüfen.
Lokal geprüft am 26.09.2026: 106 Tests erfolgreich, `flutter analyze` ohne Befund,
Formatprüfung erfolgreich und Android-Debug-APK gebaut.
APK: `build/app/outputs/flutter-apk/app-debug.apk` (lokales Build-Artefakt).
Die Hauptseiten wurden bei 390×844 und 320×568 mit 1,5-facher Schrift gerendert.
iOS benötigt weiterhin einen Mac/Xcode-Build und die Geräteabnahme.
Die GitHub-Actions-Pipeline ist vorbereitet, noch nicht remote ausgeführt.
Es wurden keine echten Marktverkäufe hochgeladen und kein Release veröffentlicht.

## Struktur und Projektwissen

- `lib/domain/`: Identitäten, Barcode/Geld, Suche, Abrechnung und Rücksortierung.
- `lib/data/`: SQLite, Bibliothek, Marktparser und Importprüfung.
- `lib/services/`: API/Sync, Desktop-Archive, Berichte und Diagnose.
- `lib/ui/`: mobile Arbeitsabläufe und native Datei-/Druckadapter.

Kanonische Planung im Obsidian Second Brain:
`D:/OneDrive/ObsidianBrain/02 Projekte/MarketMate/Flohmarkt NextGen Mobile App/`.
Einstieg `Flohmarkt NextGen Mobile App.md`; Projektregeln [AGENTS.md](AGENTS.md).
GitNexus mit der vorhandenen angepassten Installation verwenden, nicht aktualisieren:

```powershell
$env:GITNEXUS_STORAGE_ROOT = 'C:/Users/NoName/.gitnexus/indexes'
gitnexus analyze --index-only
```
