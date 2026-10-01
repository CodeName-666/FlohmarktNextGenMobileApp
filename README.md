# Flohmarkt NextGen Mobile App

Flutter/Dart-Port der MarketMate-Kassensoftware für Android und iOS.
**Funktionsport implementiert; vollständige Geräte-/Produktionsabnahme noch offen.**
Die PyQt-Referenz bleibt unverändert im Parallelbetrieb.

## Umfang

Der aktuelle Arbeitsstand enthält lokale Markt-/Kassenbibliothek, V1/V2-Import,
SQLite-Kassenbetrieb, Kamera und HID, manuelle Verkäufer-/Artikeleingabe,
Rückgaben, dynamisch parkbare Vorgänge, Belege, Artikel-/Kundensuche, Marktinformation,
Abrechnung, Statistik, Rücksortierung, PDF/Systemdruck und Dateiexporte.
Login, drei Uploadstufen, dauerhafte Outbox, Konfliktbearbeitung und Protokollarchiv
sind als eigene Module implementiert und werden gegen synthetische Verträge geprüft.

Die [Funktionsmatrix](docs/feature-parity.md) umfasst 85 Desktop-Funktionen.
Sie unterscheidet den ursprünglichen Demo-Ausgangsstand von der laufenden Abnahme.
Dateiexistenz und erfolgreiche Einzeltests bedeuten keine Produktionsfreigabe.

## Starten

Werkzeugstand: **Flutter 3.44.9 / Dart 3.12.2**. `app/pubspec.lock` fixiert Abhängigkeiten.
Die SDKs liegen außerhalb des Repos unter `C:/Users/NoName/Development/SDKs/`.
Alternativ `FLUTTER_ROOT` und `ANDROID_HOME` auf eigene SDK-Verzeichnisse setzen.
Nach einer SDK-Umstellung offene Terminals und IDEs neu starten. In der IDE `app/` öffnen.
Gradle verwendet höchstens zwei Worker und einen 2-GB-Heap; Kotlin kompiliert im
Gradle-Prozess, damit parallele 8-GB-Compiler den Rechner nicht auslagern müssen.

```powershell
./scripts/dev.ps1 get
& "$env:USERPROFILE/Development/SDKs/flutter/bin/flutter.bat" devices
./scripts/dev.ps1 run -Device <android-device-id>
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
**Parken & neuer Vorgang** legt einen weiteren unabhängigen Entwurf an.
Die Parkliste nimmt beliebig viele Vorgänge auf; Öffnen bestätigt keine Zahlung.
Die Nummer bezeichnet einen Kassiervorgang, keine personenbezogene Kundenakte.
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
./scripts/dev.ps1 check
./scripts/dev.ps1 android
```

Die Tests prüfen unter anderem SQLite-Rollback, Migration, Neustart, Rückgabe,
Exportbindung, Importkonflikte, Revisionsprüfung, API-Verträge, ACK-Verhalten,
Verkäuferidentität, Gebührenrundung, Rücksortierung, Suche und Bedienung.
Gebühren verwenden rationale Integer-Cents und half-even; Statistik summiert
bereits gerundete Verkäufergebühren. Die bewussten Unterschiede zum Desktop
stehen in der Funktionsmatrix und im Second Brain.

Native Geräte, USB-/Bluetooth-Scanner, Kameraberechtigungen und physische Drucker
sind gesondert gemäß [Hardware-Abnahme](docs/hardware-abnahme.md) zu prüfen.
Historischer Ausgangsstand am 26.09.2026: 106 Tests erfolgreich, `flutter analyze` ohne Befund,
Formatprüfung erfolgreich und Android-Debug-APK gebaut.
Damals: `build/app/outputs/flutter-apk/app-debug.apk`. Neue lokale APKs: `build/android/`.
Die Hauptseiten wurden bei 390×844 und 320×568 mit 1,5-facher Schrift gerendert.
iOS benötigt weiterhin einen Mac/Xcode-Build und die Geräteabnahme.
Aktuelle Prüfbelege und Bildansichten: [Prüfbericht](docs/verification.md).
Die GitHub-Actions-Pipeline ist vorbereitet, noch nicht remote ausgeführt.
Es wurden keine echten Marktverkäufe hochgeladen und kein Release veröffentlicht.

## Struktur und Builds

```text
app/                  Flutter-Projekt (pubspec, lib, test, assets)
  android/            Native Android-Quellen / Gradle-Konfiguration
  ios/                Native iOS-Quellen / Xcode-Projekt
  build/              Ignorierte Flutter-Zwischendateien
build/android/        Gesammelte APK/AAB und Prüfsummen (ignoriert)
build/ios/            Gesammelte iOS-Kompilierartefakte (ignoriert)
scripts/              Entwicklung und Artefaktverarbeitung
.github/workflows/    Prüfungen und Master-Builds
docs/                 Bedienung, Featurematrix, Abnahme und Release-Anleitung
```

Flutter-Befehle auf Linux/macOS und in IDEs im Verzeichnis `app/` ausführen.
Unter Windows übernimmt `scripts/dev.ps1` diesen Arbeitsverzeichniswechsel.
Die Artefaktskripte verwenden Python 3.11 oder neuer (lokal vorhanden: Python 3.13).
Native Quellordner bleiben innerhalb des Flutter-Projekts. SDKs, Signaturschlüssel,
Buildausgaben und lokale Datenbanken gehören nicht in Git.

Die Pipeline baut bei Push auf `master`. Ohne eingerichtete Release-Signierung
liefert sie ausdrücklich gekennzeichnete Prüfartefakte. Eine signierte Android-APK
und die spätere AAB/Store-Verteilung sind in [Release und Bereitstellung](docs/release.md)
beschrieben; iOS benötigt macOS/Xcode sowie für eine verteilbare IPA Apple-Signing.
Produktive Veröffentlichung ist gesondert geschützt und wird hier nicht ausgelöst.

## Struktur und Projektwissen

- `app/lib/domain/`: Identitäten, Barcode/Geld, Suche, Abrechnung und Rücksortierung.
- `app/lib/data/`: SQLite, Bibliothek, Marktparser und Importprüfung.
- `app/lib/services/`: API/Sync, Desktop-Archive, Berichte und Diagnose.
- `app/lib/ui/`: mobile Arbeitsabläufe und native Datei-/Druckadapter.

Kanonische Planung im Obsidian Second Brain:
`D:/OneDrive/ObsidianBrain/02 Projekte/MarketMate/Flohmarkt NextGen Mobile App/`.
Einstieg `Flohmarkt NextGen Mobile App.md`; Projektregeln [AGENTS.md](AGENTS.md).
GitNexus mit der vorhandenen angepassten Installation verwenden, nicht aktualisieren:

```powershell
$env:GITNEXUS_STORAGE_ROOT = 'C:/Users/NoName/.gitnexus/indexes'
gitnexus analyze --index-only
```
