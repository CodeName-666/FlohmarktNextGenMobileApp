# Prüfung des vollständigen Funktionsports

## Umstrukturierung und Redesign · 02.10.2026

- Flutter 3.44.9 / Dart 3.12.2 aus `C:/Users/NoName/Development/SDKs/flutter`.
- Format: 61 Dateien ohne Abweichung; `flutter analyze`: keine Befunde.
- Gesamtsuite: 121 Tests bestanden. Anschließende HID-Absicherung gezielt geprüft:
  5 Scanner-Sicherheitstests bestanden, inklusive neuer Inaktivitätsregression.
- 13 App-Bereiche hell/dunkel bei 320 Pixeln und Schriftfaktor 1,8 geprüft.
- 10 Python-Tests für Artefaktsammlung, Prüfsummen und Veröffentlichungsvertrag
  bestanden; unvollständige Debug-APKs werden vor der Sammlung abgelehnt.
- Android-Debug-Build im Hauptordner mit frischem `app/build/` und C:-SDK
  erfolgreich (Gradle: 354,1 Sekunden); Artefaktsammlung samt Inhaltsprüfung erfolgreich.
- iOS-/Release-Runner, Signierung, reale Hardware und produktive Serverfreigabe offen.

Der erste Desktop-SDK-Migrationsbuild lieferte einen nativen Kompiliernachweis.
Ein danach verschobener Flutter-Buildcache erzeugte bei einem inkrementellen
Build ein Paket ohne Dart-Laufzeitassets trotz Exitcode 0; dieses Paket wird
nicht verteilt. Die Artefaktskripte prüfen die notwendigen Debug-Laufzeitdateien.
Lokale Windows-SDK-/Java-Warnungen werden getrennt von Fehlern dokumentiert.

Endgültiges Testartefakt im Hauptprojekt:
`build/android/MarketMateMobile_0.1.0+1_android-debug.apk`, 186.208.759 Bytes.
SHA256: `8f03421778ec0ce4dec6298eda3c80158efe23c48d337d895b922efafe1faad8`.
ZIP-Inhalt geprüft: AndroidManifest sowie nichtleere `kernel_blob.bin`,
`isolate_snapshot_data` und `vm_snapshot_data`. Der enthaltene Kernel enthält
auch die letzten Scanner-Inaktivitätsprüfungen und die dynamische Parkliste.
`aapt dump badging`: `de.marketmate.flohmarkt_mobile`, Version `0.1.0`, Build 1,
minSdk 24, targetSdk 36. Debug-Signierung; kein produktiver Updatekanal.

Visuelle Nachweise: `build/qa/home-{light,dark}-320.png`,
`build/qa/register-{light,dark}-320.png` und `build/qa/register-light-phone.png`.
Die Telefonaufnahme zeigt einen wiederaufgenommenen Demo-Vorgang vor der Prüfung
der Positionen; bis dahin sind Abschluss und Eingabe absichtlich gesperrt.

GitNexus: Dart-Symbole des bisherigen Index sind abfragbar. Der erneute sequenzielle
Aufruf `gitnexus analyze --index-only` mit dem vorgeschriebenen externen Storage-Root
kam nach rund zehn Minuten nicht über das Analyzer-Banner hinaus; gleichzeitig
meldete die lokale Integration eine von einem anderen GitNexus-Prozess belegte
Graph-Datenbank. Der eigene Indexierungslauf wurde per Interrupt beendet.
Die MCP-Abfrage mit explizitem Repository `FlohmarktNextGenMobileApp` funktioniert,
meldet aber den alten Index als hinter dem Implementierungscommit. Keine erfolgreiche
Neuindexierung behauptet; aktuelle Quellen und Tests sind maßgeblich. Installation
unverändert, keine fremden GitNexus-Prozesse beendet. Nach Freigabe der Datenbank
die Indexierung nachholen; der Graph ist ohnehin kein vollständiger Dart-Aufrufgraph.

### Lokale Übernahme

Implementierungscommit: `c6e417d332752f8eb5443aed35c508c38540ffcb`, Branch
`codex/mobile-structure-release`. `develop` im Hauptprojekt
`D:/Projekte/WebDevelopment/FlohmarktNextGenMobileApp` wurde lokal per Fast-forward
übernommen. Kein Remote-Push, produktiver Upload oder Store-Release.

Die vorherigen uncommitteten Arbeiten sind in der Implementierung enthalten und
zusätzlich als Stash `8cb6b9edcd8250757f1030e4cde894eca92e2a12` gesichert. Nicht
ungeprüft erneut anwenden. Alte SDK-Dateien und generierte Root-Verzeichnisse liegen
außerhalb des Projekts unter `D:/Projekte/Backups/` in
`FlohmarktNextGenMobileApp-tooling-20261002/` (einschließlich `remaining-source/`)
und `FlohmarktNextGenMobileApp-generated-20261002/`. Die SDK-Ablage ist eine
Dateisicherung, kein separat geprüfter, direkt startbarer SDK-Rollback.

Aktive SDKs: `C:/Users/NoName/Development/SDKs/flutter` und
`C:/Users/NoName/Development/SDKs/android-sdk`. Lokale IDE-Konfiguration nach `app/`
übernommen; neue Terminals/IDEs verwenden die aktualisierten Benutzerpfade.
Claude Code ist installiert, aber nicht angemeldet; daher wurde das Design mit
den verfügbaren Design-Skills und Codex-Subagenten umgesetzt und geprüft.

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
