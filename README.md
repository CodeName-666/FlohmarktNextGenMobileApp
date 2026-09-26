# Flohmarkt NextGen Mobile App

Erster Flutter-Kassenclient der MarketMate-Plattform für Android und iOS.
**Stand: lokale Demo-Kasse, kein produktiver Marktbetrieb.** PyQt bleibt parallel erhalten.

## Bereits umgesetzt

- Kameraeingabe und Codefeld für USB-/Bluetooth-HID mit Enter-Abschluss.
- Revisionspflichtige MM1-Etiketten mit CRC32 und Luhn; manuell Vollcode plus Revision.
- Warenkorb mit Duplikatsperre, Entfernen und Wiederherstellung nach Neustart.
- Barzahlung, Cent-genaue Summe/Rückgeld und atomarer SQLite-Abschluss.
- Persistente Belege, UUIDv7-Verkaufsereignisse und referenzierende Einzelstornos.
- Smartphone-Oberfläche auf Deutsch, sichtbarer Demomodus, zwei synthetische Artikel.

## Starten

Getestete Werkzeugversion: **Flutter 3.44.9 / Dart 3.12.2**. Abhängigkeiten sind in
`pubspec.lock` fixiert. Android benötigt zusätzlich Android SDK/JDK, iOS macOS/Xcode.

```powershell
# In dieser Arbeitsumgebung liegt das SDK projektlokal (nicht in Git):
& ./.tooling/flutter/bin/flutter.bat pub get
& ./.tooling/flutter/bin/flutter.bat devices
& ./.tooling/flutter/bin/flutter.bat run -d <android-device-id>
```

Auf einem anderen Rechner Flutter 3.44.9 installieren und `flutter` direkt verwenden.
Auf dem Mac: `flutter pub get`, dann `flutter run -d <ios-device-id>`; für ein echtes
Gerät das Signing-Team in Xcode setzen. Die App legt `marketmate_demo_v1.db` im
App-Datenverzeichnis an. Deinstallation/App-Daten löschen entfernt die Demobelege.

Im Scan-Feld zunächst Fokus setzen; Scanner als HID-Tastatur mit Enter-Suffix und
passendem Tastaturlayout konfigurieren. Insbesondere das Zeichen `|` muss stimmen.
Die App verarbeitet vollständig übergebene Scans nacheinander. Das bestätigt keine
Kompatibilität mit einem konkreten Scanner. Serielle USB-Geräte sind nicht angebunden.

## Demo ausprobieren

Unter **Demoartikel zum Ausprobieren** können die Artikel direkt aufgenommen werden.
Alternativ folgende Payloads eingeben oder als Code128/QR für Kameratests darstellen:

```text
MM1|092700104200054|1|6BCD8E44
MM1|092700104200062|1|7DF55D18
```

Kinderbuch: 2,50 €. Regenjacke: 6,50 €. Zusammen: 9,00 €; gegeben 10,00 € → 1,00 € Rückgeld.
Manuell den Vollcode `092700104200054` und Revision `1` verwenden. Verkäufer 42 ist
von der internen Box 7 getrennt. Erneuter Scan eines verkauften Artikels wird lokal
abgelehnt; über **Belege → Position stornieren** wird ein eigenes Stornoereignis erzeugt.
Danach ist ein Wiederverkauf möglich. Der ursprüngliche Beleg bleibt erhalten.

## Prüfen

```powershell
& ./.tooling/flutter/bin/dart.bat format --output=none --set-exit-if-changed lib test
& ./.tooling/flutter/bin/flutter.bat analyze
& ./.tooling/flutter/bin/flutter.bat test
```

Tests verwenden den gleichen SQLite-Vertrag per FFI. Sie prüfen unter anderem
Neustart, Storno/Wiederverkauf, Unterzahlung, konkurrierenden Abschluss, erzwungenen
Speicherfehler mit Rollback sowie den UI-Ablauf und schnelle HID-Eingaben.
GitHub Actions ist für Analyse/Tests, Android-Debug-APK und iOS-Simulator vorbereitet;
die Pipeline wurde noch nicht remote ausgeführt.

Native Builds wurden lokal **nicht** verifiziert: Android SDK fehlt, kein Mac/Xcode.
Kamera-/USB-Hardware ebenfalls nicht geprüft. Siehe [Hardware-Abnahme](docs/hardware-abnahme.md).

## Architektur und nächste Schritte

- `lib/domain/`: reine Dart-Fachtypen, Barcode- und Geldprüfung.
- `lib/data/`: transaktionale Speicherung und synthetischer Demokatalog.
- `lib/ui/`: Kasse, Kamera, manuelle Eingabe, Zahlung und Belege.

Produktiver Import/Export, Login, Markt-/Kassenwahl, Outbox/Backend-Sync,
Doppelverkaufskonflikte zwischen Geräten, Datensicherung, Rollen und Druck fehlen noch.
Lokale Verkäufe sind ausschließlich Demodaten und werden nicht hochgeladen.
Legacy-/V1-Barcodes werden im ersten Abschnitt nicht akzeptiert.

Kanonische Analyse, Funktionsmapping und Folgeplan liegen im Obsidian Second Brain:
`D:/OneDrive/ObsidianBrain/02 Projekte/MarketMate/Flohmarkt NextGen Mobile App/`.
Einstieg: `Flohmarkt NextGen Mobile App.md`. Projektregeln: [AGENTS.md](AGENTS.md).

GitNexus nutzt die vorhandene angepasste lokale Installation; nicht automatisch
updaten. Index auffrischen:

```powershell
$env:GITNEXUS_STORAGE_ROOT = 'C:/Users/NoName/.gitnexus/indexes'
gitnexus analyze --index-only
```
