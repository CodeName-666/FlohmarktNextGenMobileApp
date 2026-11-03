# Schnittstellenvertrag mit dem Backend (KAN-590)

Die App spricht mit dem MarketMate-Backend ausschließlich über die Endpunkte, die in
der gemeinsamen Spezifikation `openapi/marketmate.yaml` (Repository FlohmarktNextGen)
beschrieben sind. Ein Vertragstest hält App und Spezifikation zusammen.

## Was geprüft wird

`app/test/api_contract_test.dart` prüft mit `app/test/contract/openapi_contract.dart`:

- **Jede Anfrage der App** (`ApiClient`, `SyncService`) gegen Pfad, Query-Parameter,
  Anmeldung und Request-Schema der Spezifikation.
- **Jede Antwort, die die App liest**, gegen das Response-Schema des jeweiligen
  Statuscodes, einschließlich 401, 403, 409 und 423.
- **Echte Backend-Antworten**: `app/test/contract/fixtures/backend_exchanges.json`
  stammt aus dem Backend-Test `src/backend/tests/test_mobile_api_contract.py`. Der
  Markt-Export darin wird mit seiner echten Prüfsumme geparst; damit ist auch die
  kanonische JSON-Form zwischen Python und Dart abgeglichen.

Die Prüfung ist streng: Felder, die das Schema nicht beschreibt, gelten als Fehler,
und `null` ist nur erlaubt, wo das Schema es ausdrücklich zulässt.

Abgedeckte Endpunkte: `POST /auth/login`, `GET /auth/me`, `GET /markets`, `GET /markets/{marketId}/export`,
`POST /sales/batch`, `POST /markets/{marketId}/sales-summary`,
`POST /markets/{id}/sale-conflicts` und `POST /auth/logout-all`.

## Spezifikation aktualisieren

Die Spezifikation liegt als unveränderte Kopie unter
`app/test/contract/openapi/marketmate.yaml`; `source.json` hält Commit und
SHA-256 (über LF-Zeilenenden) fest.

Aktueller Vertrag: **2.0.0** (KAN-587). Die Hauptversion kennzeichnet die Umstellung
der Tagesumsätze auf das Serverjournal und negative Erstattungssummen. Der
HTTP-Basispfad bleibt `/api/v1`; `openapi: 3.1.0` bezeichnet das Spezifikationsformat.

1. Im Backend-Repository den gewünschten Stand auschecken (in der Regel `develop`).
2. Testdaten neu erzeugen:

   ```powershell
   cd src/backend
   $env:MOBILE_CONTRACT_FIXTURES = "<MobileApp>/app/test/contract/fixtures/backend_exchanges.json"
   python -m pytest tests/test_mobile_api_contract.py
   ```

3. Spezifikation kopieren und Herkunft eintragen:

   ```bash
   git -C <FlohmarktNextGen> show <commit>:openapi/marketmate.yaml > app/test/contract/openapi/marketmate.yaml
   tr -d '\r' < app/test/contract/openapi/marketmate.yaml | sha256sum
   ```

   Commit (40 Zeichen) und Prüfsumme in `app/test/contract/openapi/source.json` eintragen.

4. `flutter analyze` und `flutter test` ausführen. Schlägt der Vertragstest fehl,
   weicht entweder die App oder das Backend von der Spezifikation ab: in der App
   beheben oder, wenn das Backend bewusst so antwortet, die Spezifikation im Backend
   korrigieren und Schritt 1–3 wiederholen.

## Festgestellte Abweichungen (02.11.2026)

| Abweichung | Entscheidung |
|---|---|
| Export und `logout-all` fehlten in der Spezifikation. | Im Backend ergänzt (Exportversion 2.0, nicht mehr 1.2). |
| Die App sendete bei Verkäufen ohne Backend-Listing `listingId: null`; das Backend lehnt dann den ganzen Stapel mit 422 ab. | Wie in der Desktop-Kasse bleiben solche Verkäufe lokal und erscheinen in der Konfliktliste. |
| `POST /sales/batch` antwortet bei Konflikten mit 409 und vollständigen Einzelergebnissen; die App behandelte das als Fehler. | 409 wird als Ergebnis gelesen: Konflikte gehen in die Prüfung, die übrigen Verkäufe werden quittiert. |
| `POST /listings/status` wird für eingefrorene Märkte immer abgelehnt (423 vor, 409 `MARKET_SALES_STARTED` nach Verkaufsbeginn). | Der Schritt „Listing-Status senden“ entfällt in der App; der Server leitet den Verkauft-Status aus den Verkäufen ab. Die Spezifikation beschreibt beide 409-Antworten. |
| `schedule.setupStartsAt` und `SaleConflict.details` kommen als `null`. | In der Spezifikation als `null`-fähig beschrieben. |
| Der Export liefert nie 423; die Meldung „Markt nicht eingefroren“ beim Download greift nicht. | Bewusst unverändert: Ein nicht eingefrorener Markt hat Exportgeneration 0 und wird beim Download als „kein V2-Paket“ abgelehnt. |
| `GET /markets` ignoriert ein ungültiges Token und liefert die öffentliche Liste (kein 401). | Vor dem Online-Marktladen prüft die App die Sitzung über `GET /auth/me`. Dessen 401 löscht eine abgelaufene Anmeldung und fordert zur Neuanmeldung auf. Anschließend filtert die App `myRoles` auf `cashier` oder `organizer`. Offline-Kassieren benötigt diese Prüfung nicht. |
| Ein Konto nur mit Kassierer-Rolle konnte Export und Tagesumsatz nicht abrufen und auf eingefrorene Märkte keine Verkäufe hochladen (423). | Backend: eigenes Recht `market.cash_export`, Tagesumsatz für Kassierer, Verkaufs-Upload für Kassierer trotz Einfrieren (KAN-591). Die Testdaten stammen jetzt von einem reinen Kassierer-Konto. |

## Geld

Die App rechnet ausschließlich in ganzen Cent. Euro-Beträge (`priceSnapshot`) entstehen
nur an der API-Grenze beim Senden; beim Lesen ist `priceSnapshotCents` maßgeblich.
Der Tagesumsatz-Endpunkt berechnet nach dem Verkaufs-Upload die Summe aller Kassen
aus dem Serverjournal. Die weiterhin gesendeten lokalen Summen sind nur noch
Kompatibilitätsfelder. Erstattungen können an einem Tag zu einer negativen Antwortsumme führen.
