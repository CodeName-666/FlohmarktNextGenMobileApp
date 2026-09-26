# Vollständiger mobiler Port

Auftrag: alle Features von FlohmarktNextGenApp auf Android/iOS übertragen.
Referenz-HEAD: `2d89184e1522a65ca425922d72b2292aca8f90f3`, einschließlich der
am 26.09.2026 vorhandenen lokalen Änderungen. Referenzdateien bleiben unverändert.
Feature-Abnahme: `feature-parity.md`. Architekturentscheidungen kanonisch im Vault.

## Umsetzung

1. Markt-/Kassenmodell, Mehrmarkt-Bibliothek und transaktionalen Speicher generalisieren.
   V1-Entwurf und vorhandene Demobelege migrieren. Rückgaben im Warenkorb,
   freie/unerwartete Artikel, Verkäufe mehrerer Kassen, Wiederaufnahme und Sicherung.
2. Desktop-kompatible Exporte/V1-Daten, Checksummen und Archivformate lesen/schreiben;
   Konsolidierung mit Ereignis-IDs, Stornos, Konflikten und manueller Auswahl.
3. Login/Tokenablage, Marktlisten/Download, idempotenter Upload und Sync-Protokoll.
4. Verkäufer-/Artikel-/Kundensuche, Marktdetails und lokale Kassenverwaltung.
5. Statistik, Verkäuferabrechnung/Gebühren, Auszahlungskontrolle und Prüflisten.
6. Rücksortierlisten und Scan-Abgleich mit allen Status-/Boxprüfungen.
7. PDF/CSV/Bons, Teilen/Systemdruck, Einstellungen, Theme, Kamera, Protokolle/About.
8. Integrations-/Vertragstests, Funktionsmatrix-Abgleich, Android-Build und iOS-Buildpfad.

## Gemeinsame Schnittstellen

`ArticleListing` bleibt immutable: Artikel/Listing/Markt, Centpreis, codeFull,
Revision/Generation (0 bei Legacy), Box, Titel, Größe, freie fields, unexpected.
SellerKey verwendet die gesamte regionale Identität, nicht nur die sichtbare Nummer.
`SaleEvent` enthält immutable Listing-Snapshot, UUIDv7, UTC, Kasse, Kunde, cancelOf.
`MarketSession` bindet Markt, Kasse, Generation, Checksum, Metadata und Demoflag.
Ein CheckoutStore gehört einer Sitzung; Markt-/Kassenwechsel sperrt bei offenem Entwurf.
SQLite bestätigt Mutation erst nach Commit; Outbox und Verkauf werden atomar gespeichert.

## Prüfung

Bestehende 12 Tests erhalten; neue Domänen-/SQL-/UI- und HTTP-Vertragstests ergänzen.
Echte Desktop-Formate durch synthetische identische Fixtures prüfen. Daten- und
Ereignisverlust, Preis-/Rundungsunterschiede, Doppelverkäufe und Exportwechsel testen.
Keine Platzhalterseite als portiertes Feature zählen. Hardware-/Signierungsnachweise
explizit von automatisiert verifizierter Implementierung unterscheiden.

## Arbeitsaufteilung

Root: Modelle, SQLite/Bibliothek, App-Navigation und Integration.
Abgegrenzte Implementierungsaufträge nach Bestandsanalyse: Daten/API, Abrechnung/
Rücksortierung/Berichte, UI-Suche/Einstellungen. Gemeinsame Dateien nur durch Root.
Abhängigkeiten/Flutter-Aufrufe/Indizierung zentral koordinieren.
