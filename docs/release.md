# Mobile Builds und Release-Vorbereitung

Die Flutter-Anwendung liegt in `app/`. Flutter und Gradle verwenden weiter
`app/build/` als temporären Arbeitsbereich. `scripts/collect_artifacts.py` kopiert
gezielt APK/AAB nach `build/android/` und archiviert iOS-App-Bundles nach
`build/ios/`; jedes Artefakt erhält SHA256 und Metadaten. Diese Verzeichnisse
werden nicht eingecheckt. Version und Buildnummer stammen aus `app/pubspec.yaml`.
Vor einem neuen veröffentlichten APK die Buildnummer erhöhen; bereits veröffentlichte
Versionsdateien nicht mit anderem Inhalt überschreiben.

## CI und herunterladbare Builds

`.github/workflows/flutter.yml` läuft auf Push nach `master`, auf Pull Requests
und manuell. Formatierung, Analyse, Flutter-Tests und Artefaktvertragstests sind
Voraussetzung für native Builds. `develop` löst keinen Push-Build aus.
Manuelle Ausführung auf anderen Branches erlaubt nur Vorbereitung, keine Signierung
oder Veröffentlichung. Nach erfolgreichem Lauf sind die ZIP-Artefakte im jeweiligen
GitHub-Actions-Lauf herunterladbar (Aufbewahrung 14 Tage).

| Artefakt | Verwendung |
| --- | --- |
| `MarketMateMobile_<version>+<build>_android-debug.apk` | Installierbarer Testbuild mit temporärem Debug-Schlüssel, kein produktiver Updatekanal |
| `MarketMateMobile_<version>+<build>_android-unsigned.apk` | Unsig­niertes Release-Ergebnis auf master, nicht installierbar |
| `MarketMateMobile_<version>+<build>_android-unsigned.aab` | Play-Vorbereitung ohne Signierung, nicht direkt installierbar |
| `MarketMateMobile_<version>+<build>.apk` | Optional: mit dauerhaftem App-Schlüssel signierter Direktdownload |
| `MarketMateMobile_<version>+<build>_android-upload-signed.aab` | Optional: mit getrenntem Play-Upload-Schlüssel signiertes Bundle |
| `MarketMateMobile_<version>+<build>_ios-simulator.app.tar.gz` | Simulator-App; auf einem passenden Mac-Simulator testen |
| `MarketMateMobile_<version>+<build>_ios-device-unsigned.app.tar.gz` | Unsig­niertes Geräte-Bundle auf master; kein installierbares IPA |

Der iOS-Job läuft auf `macos-15` und wählt ausdrücklich Xcode 26.3; Xcode- und
iPhoneOS-SDK-Version werden geprüft. Ein Windows-Build ersetzt diese Prüfung nicht.
Die Simulator-Architektur hängt vom Runner ab. Die TAR-Dateien bewahren App-Bundle-
Dateirechte und Symlinks. Weder Store-Upload noch GitHub Release werden automatisch
erstellt.

## Android-Signierung

`applicationId` bleibt `de.marketmate.flohmarkt_mobile`. Release-Builds verwenden
niemals den Debug-Schlüssel als Ersatz. Ohne Schlüssel entstehen unsignierte
Vorbereitungsartefakte; teilweise konfigurierte Signierung bricht mit Fehler ab.
Lokal kann die ignorierte `app/android/key.properties` mit `storeFile`,
`storePassword`, `keyAlias`, `keyPassword` verwendet werden. CI übergibt diese Werte
als Umgebungsvariablen und schreibt nur den Keystore temporär unter `RUNNER_TEMP`.

GitHub-Environment `mobile-signing` anlegen und auf `master` beschränken.
Repository-Variable `MOBILE_ANDROID_SIGNING_ENABLED=true` aktiviert den Signierjob.
`ANDROID_APP_CERT_SHA256` ist eine Variable mit dem erwarteten SHA256-Fingerabdruck
des dauerhaften App-Zertifikats; sie muss auch im Veröffentlichungsjob verfügbar sein.
`apksigner verify` prüft Signatur und Fingerabdruck vor Sammlung und erneut vor Upload.
Ein Android-Debug-Zertifikat wird abgelehnt.

| Secrets in `mobile-signing` | Bedeutung |
| --- | --- |
| `ANDROID_APP_KEYSTORE_BASE64` | Base64 des privaten App-Signing-Keystores |
| `ANDROID_APP_KEY_ALIAS` | Alias des App-Schlüssels |
| `ANDROID_APP_STORE_PASSWORD` | Keystore-Passwort |
| `ANDROID_APP_KEY_PASSWORD` | Schlüsselpasswort |
| `ANDROID_UPLOAD_KEYSTORE_BASE64` | Optional: separater Play-Upload-Keystore |
| `ANDROID_UPLOAD_KEY_ALIAS` | Optional: Upload-Alias |
| `ANDROID_UPLOAD_STORE_PASSWORD` | Optional: Upload-Keystore-Passwort |
| `ANDROID_UPLOAD_KEY_PASSWORD` | Optional: Upload-Schlüsselpasswort |

`MOBILE_ANDROID_UPLOAD_SIGNING_ENABLED=true` aktiviert zusätzlich den AAB-Build mit
dem separaten Upload-Schlüssel. Er veröffentlicht nichts im Play Store. Für Updates
zwischen Website-APK und Google Play müssen applicationId und App-Signatur identisch
bleiben. Vor der ersten Play-Veröffentlichung den eigenen App-Schlüssel passend in
Play App Signing aufnehmen; ein unabhängig von Google erzeugter App-Schlüssel würde
den direkten Updatepfad trennen. Der Upload-Schlüssel ist davon verschieden.
Schlüssel sichern und nicht in Git, Logs, CI-Artefakte oder öffentliche Downloads legen.

## Serververtrag für Android

Abgestimmter Vertrag mit dem Website-Projekt, getrennt vom Windows-Installer:

- Manifest: `/uploads/releases/mobile/android/latest.json`.
- APK: `/uploads/releases/mobile/android/MarketMateMobile_0.4.0+12.apk`.
- Prüfsumme: derselbe Dateiname mit `.sha256`.
- Staging: `/srv/marketmate/prod/releases-staging/mobile/android`.
- Eingeschränkter SSH-Befehl: `publish-mobile-android`.

Das Manifest enthält ausschließlich die erforderlichen Downloadfelder:

```json
{
  "version": "0.4.0+12",
  "apk": "MarketMateMobile_0.4.0+12.apk",
  "checksum": "MarketMateMobile_0.4.0+12.apk.sha256",
  "sha256": "<echter SHA256 der APK, 64 Hex-Zeichen>",
  "publishedAt": "2026-10-02T12:00:00Z"
}
```

`apk` und `checksum` sind reine Dateinamen. CI überträgt ausschließlich APK und
Prüfsumme per `scp -O`; der mobile Serverbefehl prüft und verteilt diese nach
Production und Preview und aktualisiert das Manifest zuletzt atomar. Das lokale
`latest.json` dient als prüfbarer Buildvertrag. Windows-Dateien und deren
`/uploads/releases/latest.json` bleiben unabhängig.

Der Serverjob bleibt standardmäßig ausgeschaltet. Erst nach separater Einrichtung
des mobilen Release-Benutzers/Schlüssels und des Dispatchers aus dem Website-Projekt
(`tools/deployment/release-ssh-command.sh`) diese Repository-Variablen setzen:

- `MOBILE_SERVER_CONTRACT_READY=true`: Serverinstallation und Contract geprüft.
- `MOBILE_SERVER_PUBLISH_ENABLED=true`: automatische Veröffentlichung auf master aktiviert.

Zusätzlich Environment `mobile-release` auf `master` beschränken und nach Bedarf
mit GitHub-Freigaberegeln schützen. Notwendige Secrets:

| Secret | Bedeutung |
| --- | --- |
| `MARKETMATE_VPS_HOST` | Bestehender, bestätigter VPS-Hostname/IP |
| `MARKETMATE_MOBILE_RELEASES_SSH_USER` | Separater eingeschränkter Mobile-Release-Benutzer |
| `MARKETMATE_MOBILE_RELEASES_SSH_KEY` | Separater privater Mobile-Release-Schlüssel |
| `MARKETMATE_MOBILE_RELEASES_KNOWN_HOSTS` | Vorab unabhängig bestätigter SSH-Hostkey im known_hosts-Format |

Der Desktop-Key wird nicht wiederverwendet. Strikte Hostkey-Prüfung bleibt aktiv.
Der Publishjob benötigt erfolgreichen signierten Android- und iOS-Build. Er prüft
lokale Prüfsummen und das APK-Zertifikat, veröffentlicht über den freigegebenen
Serverbefehl und vergleicht anschließend Manifest, Prüfsumme und APK-Bytes unter
`https://api.preview.market-mate.de/uploads/releases/mobile/android`.
Fehler bei dieser Prüfung lassen den Job fehlschlagen; ein bereits serverseitig
veröffentlichter Download wird dadurch nicht automatisch zurückgerollt.

## iOS-Signierung und Store-Schritte

Eine signierte IPA benötigt einen Mac, Apple Developer Team, registrierte Bundle-ID
`de.marketmate.flohmarktMobile`, gültiges Distribution-Zertifikat und passende
Provisioning Profiles. Das Projekt enthält dafür absichtlich keine erfundenen
Team-IDs oder Apple-Zugangsdaten. Auf dem eingerichteten Mac:

1. `app/ios/Runner.xcworkspace` in Xcode öffnen und Team/Signing prüfen.
2. Reales Gerät für Kamera, Berechtigungen, Offline-Verkauf, Drucken/Teilen testen.
3. Aus `app/` mit `flutter build ipa --release --export-options-plist=<geprüfte ExportOptions.plist>`
   ein signiertes Archiv/IPA erzeugen; Exportmethode passend zu TestFlight/App Store
   bzw. dem zulässigen Testkanal wählen.
4. Archiv und IPA aus `app/build/ios/` bei Bedarf nach `build/ios/` kopieren, prüfen
   und erst nach eigener Freigabe mit Apple-Werkzeugen hochladen.

Ein unsigniertes `.app` ist kein Website-Download für iPhone-Nutzer. Die Website
zeigt für iOS erst einen nutzbaren Link, wenn ein passender TestFlight-/App-Store-
Kanal tatsächlich freigegeben ist. PWA und native App sind getrennte Angebote.

## Noch notwendige externe Abnahmen

GitHub-Runner-Builds, reale Geräte, Wiederinstallation/Update mit dauerhaftem Schlüssel,
Serverinstallation und öffentliche Downloadprüfung sind separat nachzuweisen.
Play Console benötigt zusätzlich App-Eintrag, App-Signing-Konfiguration, Upload-Key,
Store-Metadaten/Datensicherheit und Freigabe. Apple benötigt Team, Profile,
Signierung und App-Store-Connect-Eintrag. Die Pipeline belegt keine Hardwareabnahme.

Stand 02.10.2026: Google verlangt seit 31.08.2026 für neue Apps und Updates
Android 16/API 36; der gepinnte Flutter-SDK-Quellstand setzt compileSdk/targetSdk auf 36 (minSdk 24).
Apple verlangt seit 28.04.2026 Xcode 26+ und iOS-26-SDK für Uploads.
Das Deployment Target ist davon getrennt (Projekt: iOS 13).

Quellen: [Flutter Android](https://docs.flutter.dev/deployment/android),
[Flutter iOS](https://docs.flutter.dev/deployment/ios),
[Google Play Ziel-API](https://developer.android.com/google/play/requirements/target-sdk),
[Apple Upload-Anforderungen](https://developer.apple.com/news/upcoming-requirements/),
[macOS-15-Runner](https://github.com/actions/runner-images/blob/main/images/macos/macos-15-Readme.md).
