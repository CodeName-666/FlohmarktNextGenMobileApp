# Anmeldung und Datensicherung auf dem Gerät (KAN-592)

## Angemeldet bleiben

- Nach dem Login speichert die App **nur das Sitzungs-Token** zusammen mit der
  API-Adresse, nie das Passwort (`lib/services/session_store.dart`).
- Ablage: `flutter_secure_storage`. iOS: Keychain mit
  `first_unlock_this_device` (an dieses Gerät gebunden, nicht synchronisiert, nicht
  im Backup). Android: Keystore-gestützter Speicher; App-Backups sind über
  `android:allowBackup="false"` ohnehin aus.
- Beim Öffnen der Synchronisation wird die gespeicherte Sitzung übernommen, wenn sie
  zur gespeicherten API-Adresse passt. Ein Serverwechsel verwendet kein altes Token.
- Das Backend-Token gilt 7 Tage. Antwortet der Server mit 401 (abgelaufen, widerrufen,
  „auf allen Geräten abgemeldet“), löscht die App die Sitzung und bittet um eine neue
  Anmeldung. **Kassieren offline braucht keine Anmeldung** und wird nie blockiert.
- „Abmelden“ ruft `POST /auth/logout`, „Auf allen Geräten abmelden“
  `POST /auth/logout-all`. Die Sitzung auf dem Gerät wird in jedem Fall gelöscht,
  auch ohne Netz.
- Diagnose-Export: `AppDiagnostics.redact` entfernt Bearer-Token sowie `token`- und
  `password`-Werte, auch aus Validierungsantworten des Backends (Test
  `test/session_test.dart`).

## Backup der Kassendatenbank (Entscheidung 02.11.2026)

Die Kassendatenbanken (Verkäufe, Belege, Protokolle; keine Kundendaten, keine
Zugangsdaten) liegen im Datenbankordner der App.

- **iOS:** Der gesamte Ordner wird beim Start als „nicht sichern“ markiert
  (`NSURLIsExcludedFromBackupKey`, Kanal `marketmate/storage` in
  `ios/Runner/AppDelegate.swift`). Verkäufe verlassen das Gerät nur über den Upload
  oder einen ausdrücklichen Export. Geht ein Gerät vor dem Upload verloren, sind seine
  Verkäufe verloren; deshalb regelmäßig synchronisieren bzw. Sicherungen exportieren.
- **Android:** App-Backups sind bereits ausgeschlossen.
- Schlägt das Markieren fehl, startet die Kasse trotzdem; der Fehler steht in der
  Diagnose.

## Prüfung auf echten Geräten (KAN-519)

Neustart mit erhaltener Anmeldung, Abmelden ohne Netz, Keychain-Verhalten nach
Geräte-Wiederherstellung und der Backup-Ausschluss (iOS: Einstellungen → iCloud →
Speicher verwalten) lassen sich nur am Gerät endgültig prüfen.
