# Prüfung des vollständigen Funktionsports

## Umstrukturierung und Redesign · 02.10.2026

- Flutter 3.44.9 / Dart 3.12.2 aus `C:/Users/NoName/Development/SDKs/flutter`.
- Format: 61 Dateien ohne Abweichung; `flutter analyze`: keine Befunde.
- Gesamtsuite: 121 Tests bestanden. Anschließende HID-Absicherung gezielt geprüft:
  5 Scanner-Sicherheitstests bestanden, inklusive neuer Inaktivitätsregression.
- 13 App-Bereiche hell/dunkel bei 320 Pixeln und Schriftfaktor 1,8 geprüft.
- Android-Debug-Build mit C:-SDK erfolgreich; endgültiges Paket nach Übernahme
  im Hauptordner frisch bauen und auf enthaltene Flutter-Laufzeitdateien prüfen.
- iOS-/Release-Runner, Signierung, reale Hardware und produktive Serverfreigabe offen.

Der erste Desktop-SDK-Migrationsbuild lieferte einen nativen Kompiliernachweis.
Ein danach verschobener Flutter-Buildcache erzeugte bei einem inkrementellen
Build ein Paket ohne Dart-Laufzeitassets trotz Exitcode 0; dieses Paket wird
nicht verteilt. Die Artefaktskripte prüfen die notwendigen Debug-Laufzeitdateien.
Lokale Windows-SDK-/Java-Warnungen werden getrennt von Fehlern dokumentiert.

## Historischer Prüfstand · 26.09.2026

Stand: 26.09.2026, lokale Arbeitskopie auf `codex/mobile-foundation`.
Referenzumfang und Einzelnachweise: [85-Punkte-Funktionsmatrix](feature-parity.md).

| Prüfung | Ergebnis |
|---|---|
| Dart-Formatprüfung `lib test` | 55 Dateien, keine Änderungen erforderlich |
| `flutter analyze` | Keine Befunde |
| `flutter test` | 106 Tests bestanden |
| Hauptseiten bei 390×844 und 320×568, Schriftfaktor 1,5 | Widget-Rendering erfolgreich; Statistik-Auswahl korrigiert |
| `flutter build apk --debug` | Erfolgreich, aktueller Quellstand |
| `git diff --check` | Erfolgreich |
| AGENTS.md / CLAUDE.md | Inhalt identisch |
| GitNexus-Neuindex und MCP-Abfrage | 101 Dateien, 1.157 Knoten, 2.834 Kanten, 96 Abläufe |
| Angeschlossene Android-Geräte | Keine laut `adb devices` |
| iOS-Build, Signierung, Hardware und Produktionsbackend | Nicht geprüft |

APK: `build/app/outputs/flutter-apk/app-debug.apk`, 214.481.116 Bytes.
SHA256: `F267DC8D71BA02DC970948D0F3EF5347E45E36B56292B2AEB61D776D28F447CB`.
Die Debug-APK ist ein lokales Testartefakt, kein signierter Store-Release.

Die Tests umfassen echte SQLite-Transaktionen mit injizierten Schreibfehlern,
Neustart/Migration, geschützte Marktwechsel, Entwurfsimport und -export,
Parallelkunden, bestätigte Verkäufe und Rückgaben, Duplikatkonflikte,
API-Antworten/Retry/Einzelbestätigungen, Verkäuferidentität, Centgebühren,
Rücksortierung, Berichte, Suchseiten, Einstellungen und Diagnose.
Netztests verwenden synthetische Serverantworten, keine echten Kundendaten.

Die Bildschirmprüfung verwendet Flutter-Widget-Rendering. Kamera, USB-HID,
Systemdruck und Dokumentprovider müssen zusätzlich auf benannten Mobilgeräten
geprüft werden. iOS benötigt Mac/Xcode. Die [Hardware-Abnahme](hardware-abnahme.md)
ist weiterhin offen; daher ist eine vollständige End-to-End-Freigabe nicht belegt.

Der erste Android-Build scheiterte an Kotlin-Inkrementalpfaden über verschiedene
Windows-Laufwerke. `kotlin.incremental=false` behebt diesen reproduzierten
Buildfehler; danach war der Build erfolgreich. Die angepasste GitNexus-Installation
wurde nicht aktualisiert. Die PyQt-Referenz wurde nicht verändert.

GitNexus erfasst auch Dart-Methoden; `importEventsAndDraft` ist per MCP auffindbar.
Die Analyse meldet begrenzte Ablaufverfolgung (u. a. 124 nicht verfolgte
Einstiegspunkte, 33 verworfene Abläufe, 10 Dart-Aufrufzuordnungen per Namensheuristik).
Der Index ist daher kein vollständiger Aufrufgraph und kein Ersatz für Tests.
