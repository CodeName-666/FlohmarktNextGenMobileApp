# Desktop → Mobile: Funktionsparität

Inventar vom 26.09.2026. Technische Prüfliste für den ausdrücklich beauftragten **vollständigen** Port; kein Architekturkonzept und keine Fertigmeldung. Kanonische Projektplanung bleibt im [Projektkompass](<D:/OneDrive/ObsidianBrain/02 Projekte/MarketMate/Flohmarkt NextGen Mobile App/Projektkompass Mobile.md>). Dessen frühere Demo-Beschränkung beschreibt den Ausgangsstand, nicht den erweiterten Auftrag.

## Quellen und Status

Desktop-Root: `D:/Projekte/WebDevelopment/FlohmarktNextGenApp`.
Gelesener HEAD: `2d89184e1522a65ca425922d72b2292aca8f90f3`.
**Dirty Source:** Parallel bearbeitete Arbeitskopie, kein unveränderlicher Release-Snapshot. Insbesondere Verkäuferidentität, manuelle Eingabe, Kassenbetrieb, Abrechnung und Rücksortierung enthalten uncommittete Änderungen. Der Inventarstand berücksichtigt die tatsächlich gelesenen Dateien. Vor Umsetzung deren aktuellen Inhalt und Tests erneut vergleichen; keine Desktop-Änderungen überschreiben.

Geänderte Dateien bei Beginn: `core/statistik/abrechnung.py`, `gui/models.py`, `gui/payout.py`, `gui/reconciliation_box_select_dialog.py`, `gui/reconciliation_page.py`, `gui/register/manual_entry_dialog.py`, `gui/register/register_page.py`, `gui/statistics.py`, `services/data_manager.py`, `services/export_service.py`, `services/reconciliation_service.py`, `services/scan_resolver.py` sowie zugehörige Tests; zusätzlich nicht versionierte Verkäuferidentitäts-Tests und Plan. GitNexus-Abfrage für Repository `FlohmarktNextGenApp` lieferte Klassen-/Dateiverweise; wegen laufender Änderungen sind direkte Quelldateien maßgeblich. Kein Index oder Testlauf durch diesen Inventarauftrag.

Alle Quellen unten sind relativ zum Desktop-Root; `Datei:Symbol` ist der Suchanker, kein behaupteter stabiler Zeilenstand. Zielbezeichnungen sind mobile Funktionsziele, nicht bereits vorhandene Klassen.

Statuslegende:

- **Offen**: im mobilen Ausgangsstand nicht implementiert.
- **Demo-Teil**: begrenzter Baustein vorhanden, vollständige Parität weiterhin offen.
- **Entscheidung offen**: Desktop-Verhalten kollidiert mit geltender mobiler Sicherheits-/Bedienregel oder braucht eine native Entsprechung. Kein stillschweigender Funktionsverzicht.

Ausgangsstand Mobile: ausschließlich lokaler Demo-Katalog, SQLite-Warenkorb, MM1-/Vollcode-Eingabe, Kamera-Einzelscan, FIFO-HID-Eingabe, Barzahlung mit Pflichtbetrag, Belegliste und unmittelbarer Storno. Keine der folgenden vollständigen Produktfunktionen gilt allein dadurch als abgenommen. Native Geräteprüfung bleibt separat.

## Navigation, Start und Markt

| ID | Desktop-Quelle und Verhalten | Mobiles Gegenstück | Ausgangsstatus | Abnahmekriterium |
|---|---|---|---|---|
| N01 | `gui/main_window.py:MainWindow._init_navigation` – Start, Marktdetails, Kasse, Artikel-/Kundensuche, Rücksortierlisten, Scan-Rücksortierung, Abrechnung, Statistik, Design, Einstellungen, Über | Vollständige Navigation, auf kleinen Displays scrollbar | Demo-Teil | Jede Funktion erreichbar; Zurücknavigation verliert weder Entwurf noch aktive Marktidentität. |
| N02 | `gui/home_page.py:HomePage._build_phasen` – Vorbereiten/Kassieren/Nach dem Markt | Startseite mit drei Arbeitsphasen | Offen | Alle Desktop-Aktionen sind zugeordnet; ohne Markt führt Hauptaktion zur Marktauswahl, sonst zur Kasse. |
| N03 | `HomePage._build_status_card`, `_kennzahlen`, `_build_admin_card` | Aktiver Markt, Kennzahlen, Herkunft, Status; Einstellungen/Sync/Archiv | Offen | Wechsel aktualisiert Angaben konsistent; Verwaltung ist auch ohne geladenen Markt verständlich bedienbar. |
| N04 | `gui/main_window.py:_design_umschalten` | Persistente helle/dunkle Darstellung | Offen | Auswahl über Neustart erhalten; alle Seiten/Dialoge lesbar. |
| N05 | `controllers/cash_data_controller.py:try_load_last_market` | Letzten Markt/Kasse nach Neustart laden | Offen | Exakter gespeicherter Markt wird revalidiert; vertauschtes Paket/Hash/Pfad führt zu sichtbarem Fehler, nie zur neuesten beliebigen Datei. |
| N06 | `gui/main_window.py:_warne_bei_unsauberem_ende`, `_beenden_bestaetigt` | Wiederanlaufhinweis und Entwurfserhalt bei App-Ende | Demo-Teil | Abbruch/OS-Kill erhalten Entwurf; unklarer Zahlungsstand verlangt Prüfung; kein Verkauf durch bloßes Schließen. |
| M01 | `gui/sync/load_market_dialog.py:LoadMarketDialog` | Lokale Marktbibliothek | Offen | Karten zeigen lesbaren Markt und Herkunft; aktiver Markt vorgewählt, defekte Märkte sichtbar aber nicht aktivierbar; leere Liste erklärt nächsten Schritt. |
| M02 | `controllers/cash_data_controller.py:load_market` | Transaktionaler Marktwechsel | Offen | Offener Warenkorb sperrt Wechsel; fehlgeschlagene Aktivierung erhält alten Markt, Kasse, Einstellungen und Ansichten. |
| M03 | `gui/checkout_dialog.py:CheckoutDialog`, `CashDataController.load_checkout` | Kasse innerhalb aktivem Markt wählen | Offen | Vorhandene Kassen, aktuelle Nummer und Quelldatei angezeigt; Abbrechen unverändert; defekte/fremde Kasse wird nicht als leer übernommen. |
| M04 | `CashDataController._activate_checkout`, `MainWindow._open_settings` | Kassenwechsel samt Konfigurationscommit | Offen | Neuer Stand erst nach vollständigem Laden/Speichern veröffentlicht; Fehler rollt Auswahl zurück. |
| M05 | `gui/market_details_page.py:MarketDetailsPage.on_data_loaded` | Marktdetails | Offen | Name/Datum, Herkunft, Bestand, Markt-ID, Exportdatum, Freeze-Status, Quellen/Kasse, Gebühren samt Herkunft vollständig sichtbar, lange Werte umbrechbar. |
| M06 | `MarketDetailsPage._export_marktinfo_pdf` | Marktinformation als PDF anzeigen/teilen | Offen | PDF enthält denselben aktiven Stand; Schreibfehler erzeugt keinen Erfolg; Öffnungsfehler löscht erstellte Datei nicht. |
| M07 | `gui/market_origin_badge.py` | V1-/V2-/unbekannte Herkunft sichtbar | Offen | Herkunft kommt aus Paket, nicht aus einem globalen Modusschalter. |

## Lokale Dateien und Importe

| ID | Desktop-Quelle und Verhalten | Mobiles Gegenstück | Ausgangsstatus | Abnahmekriterium |
|---|---|---|---|---|
| F01 | `gui/market_storage_dialog.py:MarketStorageDialog`, `SettingsDialog._build_pfade_card` | Verwaltete Ablage und native Datei-/Ordnerauswahl | Offen | Bibliotheksort, gültige/prüfbedürftige Märkte und Zugriff sichtbar; verweigerter/verlorener Zugriff lässt Daten unverändert. |
| F02 | `gui/sync/v1_import_dialog.py:V1ImportDialog._choose`, `_inspect` | V1-Datei wählen und Vorschau prüfen | Offen | Neue Datei invalidiert alte Vorschau; Statistik nennt Stammnummern, übernehmbare Artikel, ignorierte Leerzeilen und alle Probleme; Import erst nach positiver Prüfung. |
| F03 | `V1ImportDialog._import`, `_show_existing` | Benannter lokaler V1-Markt | Offen | Eigenständige Bibliothekseintragung; Quell-JSON bleibt unverändert; Doppelimport überschreibt keine Kasse und bietet vorhandenen Markt an. |
| F04 | `V1ImportDialog._save_report` | V1-Prüfbericht speichern/teilen | Offen | Bericht enthält Zusammenfassung und Probleme; Abbruch ist folgenlos, Schreibfehler sichtbar. |
| F05 | `services/file_manager.py` und `tests/test_file_io_failures.py` | Desktop-kompatibler Kassenimport/-export | Offen | Ungültiges JSON, Kodierung, Schema, fehlende Verkaufsliste oder ungültige Position lehnen ganze Eingabe ab; vorhandene Datei/Datenbank bleiben erhalten. |
| F06 | `config/defaults.py`, `config/keys.py` – Bibliothek, Kassen-Unterordner, zuletzt geladener Markt, konkretes Exportpaket | Persistente mobile Ablageverweise | Offen | Relative/benutzergewählte Ablage eindeutig aufgelöst; Markt und Exportgeneration bleiben gebunden; Backup/Teilen führt nicht zur Aktivierung einer anderen Kasse. |
| F07 | `controllers/cash_data_controller.py:export_unsold_articles` | Nicht-verkauft-Liste als Text exportieren | Offen | Nur aktueller Bestand, korrekt nach Verkäufen/Rückgaben; nativer Speicher-/Teildialog und sichtbare Fehler. Desktop-Callback vorhanden, derzeit keine sichtbare Startkachel gefunden. |
| F08 | `tests/test_persistenz_haltbarkeit.py`, `test_file_io_failures.py`, `test_market_library_failure_edges.py` | Atomare dauerhafte Änderungen | Demo-Teil | Unterbrochene Schreibvorgänge, voller Speicher und korrupte Dateien erzeugen keinen halben Import/Verkauf und keinen fälschlichen Erfolg. |

## Kassieren, Scan und Rückgabe

| ID | Desktop-Quelle und Verhalten | Mobiles Gegenstück | Ausgangsstatus | Abnahmekriterium |
|---|---|---|---|---|
| K01 | `gui/register/register_page.py:RegisterPage._init_ui`, `_refresh_list` | Markt-/Kassenkopf, Kunde, Warenkorb, Artikelzahl, Kunden-/Gesamtumsatz | Demo-Teil | Nicht nur Gesamtsumme: laufender Kunde und Kasse eindeutig; negative Rückgaben reduzieren Artikelzahl und Umsatz. |
| K02 | `RegisterPage._barcode_eingabe`, `_barcode_konsumiert`, `_on_barcode_editiert` | HID-Feld mit Enter, letzter Code sichtbar | Demo-Teil | Wiederholtes Enter verkauft nicht erneut; nächster Scan ersetzt konsumierten Code; schnelle Scans bleiben in Reihenfolge ohne Verlust. |
| K03 | `RegisterPage._letzten_scan_anzeigen`, `tests/test_scan_anzeige.py` | Auffällige letzte Position mit Identität, Beschreibung, Preis/Rückgabe | Offen | Sichtprüfung sofort möglich; Entfernen dieser Position löscht Hinweis, Entfernen anderer Positionen nicht. |
| K04 | `RegisterPage._refresh_list`, `tests/test_kassen_bedienung.py` | Neueste Position sichtbar, Auswahl ohne Verlust des Scan-Ziels | Demo-Teil | Scan scrollt zur neuesten Position; Tabellen-/Listenbedienung verhindert keine folgenden HID-Scans; Bildschirmtastatur bleibt nutzbar. |
| K05 | `RegisterPage._resolve_scan`, `services/scan_resolver.py` | Marktgebundene V2-MM1-Auflösung | Demo-Teil | CRC32, Luhn, akzeptierte Revision, Listing, Markt, Generation und Preis-Snapshot geprüft; unbekannt/verkauft/veraltet sichtbar abgelehnt. |
| K06 | `gui/register/manual_entry_dialog.py:ManualEntryDialog`, `RegisterPage._verkauf_manuell` | Verkäufernummer + Artikelnummer + sichtbare Revision | Offen | Ersetzt beschädigten Code anhand echter Labelangaben; positive Ganzzahlen und Revision prüfen; Demo-Vollcode-Dialog allein genügt nicht. |
| K07 | `RegisterPage._seller_scan_result`, `gui/register/seller_select_dialog.py:SellerSelectDialog` | Mehrdeutige Verkäuferidentität auswählen | Offen | Gleiche lokale Verkäufernummer mit verschiedenen Bundesland/Landkreis/Shard führt zur expliziten Auswahl; Abbruch bucht nichts; niemals Box als Verkäufernummer behandeln. |
| K08 | `ManualEntryDialog(revisionslos=True)`, `services/scan_resolver.py` | Expliziter revisionsloser V1-Modus | Offen | Nur nach validiertem V1-Paket ohne Revisionsfeld; V2 bleibt revisionsstreng; V1 kann nicht als revisionsfähiger Backend-Verkauf hochgeladen werden. |
| K09 | `RegisterPage._beschreibung_suche`, `gui/register/article_search_dialog.py` | Artikel aus Beschreibungssuche übernehmen | Offen | Auswahl behält Identität/Snapshot; bereits verkauft im Verkaufsmodus gesperrt; nicht verkauft im Rückgabemodus gesperrt; Abbruch stellt Eingabefokus wieder her. |
| K10 | `RegisterPage._verkauf_ohne_scanner`, `services/data_manager.py:artikel_verkaufen` | Bekannter Offline-/Legacy-Artikel ohne Backend-Auflösung | Offen | Nur bereits vorhandener Artikel; Herkunft/fehlende Backend-ID nachvollziehbar; kein erfundenes Listing, kein stiller V2-Snapshot-Fallback. |
| K11 | `RegisterPage._do_verkaufen`, `tests/test_register_failure_flows.py:test_manual_rejects_unknown_article_without_opening_customer` | Unbekannte Verkäufer/Artikel ablehnen | Demo-Teil | Kein freier Ersatzartikel oder Nullpreis; kein neuer Kunde und keine Buchung bei unbekanntem Artikel. Kein Freipreisverkaufsdialog im aktuellen Desktop gefunden. |
| K12 | `RegisterPage._markierten_entfernen` | Gewählte Entwurfsposition entfernen, zuletzt gescannte vorgewählt | Demo-Teil | Entfernen ändert nur Entwurf, aktualisiert offene Zahlungsansicht, hinterlässt kein Storno eines nie abgeschlossenen Verkaufs. |
| K13 | `RegisterPage._kontrollsumme` | Kontrollsumme (F5-Entsprechung) | Offen | Aktueller Kunde und Gesamt: Kundenanzahl, Artikelzahl und Umsatz stimmen mit Ansichten überein; leere neue Kunden zählen nicht. |
| K14 | `RegisterPage._neuer_kunde` | Nächster Kunde / Zahlungsansicht (F6) | Demo-Teil | Leerer Warenkorb überspringt keine Kundennummer; Öffnen allein verändert keinen Verkauf; abgebrochene Zahlung lässt vollständigen Entwurf bestehen. |
| K15 | `RegisterPage._berechne_rueckgeld`, `_als_betrag`, `_checkout_bestaetigen` | Live-Wechselgeld/Fehlbetrag und bestätigter Abschluss | Demo-Teil | Komma/Punkt ohne Geld-Float; Betrag/Fehlbetrag während Eingabe sichtbar; Speicherfehler erhält Zahlungsansicht und wiederholbaren Entwurf; Doppeltippen erzeugt einen Beleg. Desktop erlaubt auch Abschluss ohne Gegeben-Betrag: Zielentscheidung K16. |
| K16 | `RegisterPage._neuer_kunde`, `_kunde_festschreiben_und_wechseln`, `_gegeben_enter` | Zwei-Personen-/Parallelkundenablauf | Entscheidung offen | Beide Kunden und Zahlungszustände bleiben getrennt; Scan darf nach mobiler Regel keinen unbestätigten Kunden abschließen. Optionales Gegeben und Weiterarbeiten müssen ausdrücklich gestaltet und getestet werden; siehe Entscheidungen unten. |
| K17 | `RegisterPage._checkout_abbrechen` | Zahlungsabbruch vor/nach Kundenübergabe | Entscheidung offen | Vor Abschluss unveränderter Entwurf; bereits bestätigter Vorgang bleibt erreichbar und kann nicht durch Dialogabbruch verschwinden. |
| K18 | `RegisterPage._rueckgabe_modus_umschalten`, `_set_rueckgabe_modus` | Sichtbarer anhaltender Rückgabemodus (F8) | Offen | Alle Eingabewege sind eindeutig Rückgabe statt Verkauf; Modus über mehrere Artikel aktiv und bei Kundenwechsel zurückgesetzt. |
| K19 | `RegisterPage._rueckgabe_per_code`, `_rueckgabe_per_seller_eingabe`, `_do_rueckgabe` | Rückgabe per Scan, manueller Identität oder Suche | Offen | Nur belegbarer aktiver Verkauf; unauflösbarer Scan bietet kontrollierte manuelle Eingabe; negative Position bleibt Entwurf bis Abschluss. |
| K20 | `services/data_manager.py:artikel_zurueckgeben`, `kunden_artikel_entfernen`, `tests/test_data_manager.py` | Rückgaben mit Verkäufen im selben Kundenkorb | Offen | Rückgabeentwurf kann entfernt werden, Original bleibt dann aktiv; Abschluss erzeugt neues Storno; negativer Gesamtbetrag als Auszahlung behandelt; Wiederverkauf erst nach bestätigter Freigabe. |
| K21 | `RegisterPage._drucke_bon`, `services/bon_drucker.py` | Bon nach bestätigter Speicherung | Offen | Fehlender Drucker kann übersprungen werden; Druckfehler sichtbar und nachdruckbar, nie Rollback/Doppelverkauf. Native Druckerunterstützung separat nachweisen. |
| K22 | `RegisterPage._init_ui` – F5/F6/F7/F8/F9/F10/F11, Escape | Touch-Aktionen und optional Hardwaretastatur | Demo-Teil | Alle Aktionen ohne Funktionstasten erreichbar; angeschlossene Tastatur löst dieselben kontrollierten Aktionen aus, keine globalen Scanner-Fangevents in fremden Feldern. |
| K23 | `RegisterPage._sicherung_aktualisieren`, `services/basket_journal.py` | Sichtbarer Sicherungszustand | Offen | Ausstehende/fehlgeschlagene Sicherung darf nicht als gespeichert erscheinen; Korrekturversuch möglich ohne Datenverlust. |
| K24 | `gui/basket_recovery_dialog.py:BasketRecoveryDialog`, `CashDataController._offer_basket_recovery` | Explizite Wiederaufnahme | Demo-Teil | Positionen/Kasse/Kunde/Summe zeigen; Checkbox „Artikel und Zahlungsstand geprüft“ vor Wiederherstellen; Später sperrt Kasse; bewusstes Verwerfen löscht nur Entwurf. |
| K25 | `tests/test_recovery_validation.py`, `test_basket_recovery_controller.py` | Defekter/fremder Entwurf und Wiederanlauf | Offen | Kasse/Markt/Generation und Originalverkäufe geprüft; korrupter Entwurf bleibt gesperrt statt leerer Kasse; gültiger Entwurf wird niemals automatisch als Verkauf gebucht. |

## Artikel- und Kundensuche

| ID | Desktop-Quelle und Verhalten | Mobiles Gegenstück | Ausgangsstatus | Abnahmekriterium |
|---|---|---|---|---|
| S01 | `gui/search_page.py:SearchPage.SUCHMODI`, `_do_search` | Beschreibung, Stammnummer, Artikelnummer | Offen | Beschreibung mit Mindestlänge; Nummer ab einer Ziffer; Stamm-/Verkäufernummer, Kurzcode und Etikett suchen; Artikelnummer sucht verkäuferübergreifend. |
| S02 | `services/feldprofil_cache.py`, `tests/test_artikelsuche.py` | Suche über angezeigtes Feldprofil | Offen | Teilwörter, Groß-/Kleinschreibung, mehrere Wörter über Feldgrenzen, deutsche Zahlenanzeige; versteckte Felder/Preis nicht ungefragt einbeziehen; ohne Profil Beschreibung+Größe. |
| S03 | `SearchPage._do_search` | Filter Alle/Verfügbar/Verkauft plus Kennzahlen | Offen | Treffer, verfügbar, verkauft und Gesamtwert konsistent; leere/ungültige Eingabe löscht Resultate; verfügbare zuerst gemäß Desktop-Sortierung. |
| S04 | `gui/models.py:_FeldprofilColumnsModel`, `SuchergebnisModel`, `KundenArtikelModel` | Dynamische sichtbare Feldspalten und feste Identitäts-/Preisinformationen | Offen | Reihenfolge/Labels/Format aus Marktprofil; unbekannte/fehlerhafte Profile blenden nicht gültige Artikel aus; mobile Karten dürfen Informationen nicht verlieren. |
| S05 | `gui/customer_lookup_page.py:CustomerLookupPage._suchen` | Beleg nach Kundennummer oder Vorgang-ID suchen | Offen | Numerische Kundennummer und nichtnumerische Vorgang-ID lösen richtigen Kassen-/Kundenbeleg auf; Positionen und Summe zeigen; kein Treffer löscht alten Beleg. |
| S06 | `CustomerLookupPage._bon_erneut_drucken` | Historischen Bon erneut ausgeben | Offen | Gespeicherten Beleg unverändert drucken/teilen; Fehler ohne neue Verkaufsbuchung; Button ohne Treffer deaktiviert. |
| S07 | `SearchPage.on_data_loaded`, `CustomerLookupPage.on_data_loaded` | Suchstand bei Marktwechsel erneuern | Offen | Keine Treffer oder druckbaren Belege aus vorherigem Markt stehen bleiben; eingegebene Suche kann erhalten bleiben. |

## Backend-Oberflächen und Konflikte

Die detaillierten API-, Identitäts- und Idempotenzverträge werden separat anhand der Services geprüft; diese Zeilen sichern die Bedienoberfläche und dürfen dadurch nicht als erledigt markiert werden.

| ID | Desktop-Quelle und Verhalten | Mobiles Gegenstück | Ausgangsstatus | Abnahmekriterium |
|---|---|---|---|---|
| B01 | `gui/auth/login_dialog.py:LoginDialog`, `controllers/sync_controller.py:ensure_organizer_login` | Organisator-Anmeldung | Offen | E-Mail-Vorbelegung, Passwort verdeckt, fehlende Provisionierung/gesperrter Login/Netzfehler verständlich; Abbruch ohne gestarteten Download/Upload. |
| B02 | `gui/sync/export_dialog.py:ExportDialog._load_markets`, `_apply_filter` | V2-Marktkatalog suchen/aktualisieren | Offen | Name/Ort/ID filterbar, Status und Metadaten anzeigen; gültige Auswahl nach Refresh erhalten, ungültige entfernen; Organisationsbindung beachten. |
| B03 | `ExportDialog._choose_target_folder`, `_on_export` | Markt herunterladen und lokal ablegen | Offen | Zielablage sichtbar/wählbar; überprüftes vollständiges Paket vor Aktivierung; Fehler/Abbruch erhalten bestehenden Stand. |
| B04 | `gui/sync/import_dialog.py:ImportDialog._on_stufe1`, `_on_stufe2`, `_on_stufe3` | Listing-Status, Tagesumsatz, Verkäufe synchronisieren | Offen | Drei Ergebnisse getrennt sichtbar; fehlender Markt gesperrt; revisionslose V1-Märkte ausdrücklich vom V2-Upload ausgeschlossen. |
| B05 | `ImportDialog._on_retry`, `_aktualisiere_retry_button` | Dauerhafte Wiederholungswarteschlange | Offen | Offene Anzahl sichtbar, erneuter Versuch gezielt möglich; Neustart erhält Arbeit, erneutes Senden vervielfacht keine Verkäufe. |
| B06 | `gui/consolidation/conflict_dialog.py:ConflictDialog` | Konflikte und Dubletten bearbeiten | Offen | Dublette bereinigen, lokal stornieren, an Organisator verweisen, akzeptieren/ignorieren jeweils explizit; erfolglose Aktion bleibt offen; keine Offline-Garantie globaler Eindeutigkeit. |
| B07 | `gui/sync/import_archive_dialog.py:ImportArchiveDialog._render` | Importprotokoll/Archiv | Offen | Marktübersicht, Läufe, Konflikte, verwiesene Konflikte und Dateien getrennt lesbar; Aktualisieren und aktueller-Markt-Filter. |
| B08 | `ImportArchiveDialog._on_export`, `_on_loeschen` | Konflikte CSV/JSON teilen; Archiv/Protokolle gezielt löschen | Offen | Filter wirkt auf Export; Löschung bestätigt exaktes Artefakt und löscht keine Verkäufe; Zugriffs-/Schreibfehler sichtbar. |

## Nach dem Markt: Oberflächenabdeckung

Rechenformeln, Dateiformate und Identitätsdetails gehören zur gesonderten Vertragsprüfung; alle unten genannten Bedienfunktionen bleiben Teil des vollständigen Ports.

| ID | Desktop-Quelle und Verhalten | Mobiles Gegenstück | Ausgangsstatus | Abnahmekriterium |
|---|---|---|---|---|
| A01 | `gui/ruecksortierung_page.py:RuecksortierungPage._merge` | Kassenlisten zusammenführen | Offen | Alle Quellen und aktueller Zusammenführungsstand sichtbar; Fehler behalten bisherigen konsistenten Stand; erneutes Zusammenführen möglich. |
| A02 | `RuecksortierungPage._build_liste_card`, `_erzeuge_ruecksortier_pdf` | Rücksortier-PDF mit auswählbarem Nummernblock pro Seite | Offen | PDF erst aus gültigem Stand; Nummernblock wirksam/persistent, nicht vergebene Nummern entfallen und umfangreiche Verkäufer können mehrere Spalten benötigen; Erzeugungs- und Öffnungsfehler getrennt. |
| A03 | `gui/reconciliation_page.py:ReconciliationPage._load_seller`, `_box_fuer_verkaeufer`; `gui/reconciliation_box_select_dialog.py` | Verkäufer-/Boxliste laden und Mehrdeutigkeit wählen | Offen | Label-Verkäuferidentität nicht mit Box verwechseln; mehrere Kandidaten explizit wählen; Abbrechen erhält vorherige Liste. |
| A04 | `ReconciliationPage._record_scan`, `_show_scan_feedback` | Rücksortierung via HID, Kamera, manuell | Offen | Erwartet/gefunden/fehlend/verkauft und unerwartet bzw. ungültig sichtbar unterscheiden; Wiederholung zählt nicht doppelt. |
| A05 | `ReconciliationPage._reset_page`, `_refresh_view` | Liste zurücksetzen, Summen und Zustand | Offen | Keine alte Verkäuferliste nach Marktwechsel; aktiver/finalisierter Zustand sichtbar, Eingaben nur im passenden Zustand. |
| A06 | `ReconciliationPage._export_report`, `_finish_and_export` | CSV-Zwischenstand, Abschließen und Export | Offen | Gewählte Liste vollständig, fehlende/unexpected Artikel enthalten; Exportfehler meldet keinen erfolgreich ausgegebenen Bericht. |
| A07 | `gui/payout.py:PayoutPage._refresh_tabelle`, `_markiere`, `_on_selection` | Abrechnung je vollständiger Verkäuferidentität | Offen | Summen/Tabelle, Verkäuferauswahl und Teilabrechnungen pro Box (Warenwert, Erlös, Restwert, offene Rücksortierung, Gebühren, Auszahlung) konsistent; verschiedene Verkäufer mit gleicher Kurznummer nicht verschmelzen. |
| A08 | `PayoutPage._erzeuge_abrechnungen_pdf`, `_erzeuge_einzel_pdf` | Gesamtabrechnung und Einzel-PDF | Offen | Gleiche Quellen/Formeln wie angezeigte Abrechnung; Einzelausgabe nur für richtige Auswahl; PDFs nativ teilbar. |
| A09 | `gui/statistics.py:StatisticsPage._refresh`, `_update_title` | Marktstatistik samt Datenstand | Offen | Gesamt/verkauft/unverkauft, Verkaufsquote, Umsatz, Angebotswert, Verkäufer/Kunden und Durchschnitt korrekt; aktueller Kassenstand vs. Zusammenführung erkennbar. |
| A10 | `StatisticsPage._erzeuge_pdf` | Statistik-PDF | Offen | Zahlen und Quellstand stimmen mit Anzeige überein, kein erfolgreicher Export bei Schreibfehler. |
| A11 | `gui/stammdaten_hinweis.py:StammdatenHinweis` | Nicht blockierender Stammdaten-Prüfhinweis | Offen | Historische Verkäufe ohne passende Stammdaten bleiben berechenbar und sichtbar; Details und CSV-Prüfliste genau für angezeigten Snapshot. |

## Einstellungen, Kamera, Diagnose und Über

| ID | Desktop-Quelle und Verhalten | Mobiles Gegenstück | Ausgangsstatus | Abnahmekriterium |
|---|---|---|---|---|
| E01 | `gui/settings_dialog.py:_build_kasse_card`, `_on_save` | Kassennummer | Offen | Validierter Wertebereich, Wechsel bei offenem Korb gesperrt; erst nach erfolgreichem Laden und Speichern wirksam. |
| E02 | `SettingsDialog._build_pfade_card`, `_refresh_market_count`, `_oeffne_markets_ordner` | Datenablage ändern/anzeigen | Offen | Standort und gültige/prüfbedürftige Märkte sichtbar; native Auswahl/Dateiöffnung ersetzt Windows-Explorer, ohne Daten automatisch zu verschieben. |
| E03 | `SettingsDialog._build_statistik_card`, `_update_gebuehren_fields` | Umsatzanteil, Gebühr je Verkäufernummer, manuelles Überschreiben | Offen | Exportgebühren standardmäßig maßgeblich und geschützt; explizites Override; Quelle sichtbar; Eingabe/Rundung nach mobilem Centvertrag. |
| E04 | `SettingsDialog._build_webcam_card`, `_update_webcam_fields` | Kamera aktivieren und Gerät wählen | Demo-Teil | Verfügbare Kameras, keine Kamera und verweigerte Berechtigung sichtbar; deaktiviert beendet aktive Aufnahme; Auswahl persistent. |
| E05 | `SettingsDialog.combo_barcode_typ`, `core/barcodes.py:BARCODE_TYPEN` | EAN-8/EAN-13/Code 128/Automatisch wählen | Offen | Alle tatsächlich unterstützten Desktop-Formatoptionen auf native Fähigkeiten abbilden und prüfen; Auswahl wirkt auf laufende nächste Scans, keine erfundene Formatunterstützung. |
| E06 | `gui/webcam_scanner.py:CameraScanPanel.start_scan`, `stop_scan`, `hideEvent`; `RegisterPage._webcam_scan` | Kontinuierlicher Kamerabetrieb/Start/Stopp | Demo-Teil | Live-Vorschau und Scanfeedback; Mehrfachscans ohne Doppelerfassung; Kamera endet bei Verlassen/Hintergrund und bleibt manuell ersetzbar. Demo-Einzelscan ist keine vollständige Parität. |
| E07 | `SettingsDialog._build_api_card` | Backend-URL, Organisations-ID, Login-E-Mail | Offen | Validieren und persistent speichern; lokale V1-Importe unabhängig; geänderte Verbindung verwirft nicht ungefragt aktiven Markt. |
| E08 | `SettingsDialog._build_drucker_card` | Native Druckerverbindung konfigurieren | Entscheidung offen | Unterstützter Transport und konkretes Gerät nachgewiesen; Windows-Druckername nicht als mobile Funktion ausgeben; Bondruck/Nachdruck und Fehlerpfad nutzbar. |
| E09 | `SettingsDialog._build_logging_card`, `_load_logging_values` | Diagnoselevel DEBUG/INFO/WARNING/ERROR, Kategorien scanner/sync/io | Offen | Auswahl persistent und zur Laufzeit wirksam; Geheimnisse redigiert; ungeprüfte Kategorien ignoriert; Diagnose darf Kasse nicht blockieren. |
| E10 | `SettingsDialog._open_log_folder`, `config/defaults.py:logging` | Logs anzeigen/teilen; Rotation/Retention | Offen | Mobile App-Logs kontrolliert exportierbar; Tageswechsel, Größenrotation, Anzahl Backups und Schreibfehler erhalten nutzbare Diagnose. Desktop-Konsole wird durch native Diagnose ersetzt. |
| E11 | `gui/main_window.py:_open_settings`, `tests/test_settings_transaction_edges.py` | Einstellungen atomar anwenden/abbrechen | Offen | Abbrechen verändert nichts; Speicherfehler publiziert keine Teilwerte; erfolgreicher Save aktualisiert Seiten, Kamera, Logger und API-Client. |
| E12 | `gui/about_page.py:AboutPage`, `_links_row` | Über-Seite | Offen | Appname/Beschreibung, Version, Entwickler/Firma/Support/Lizenz, Build-/Flutter-/Dart-/OS-Infos, Projektseite/Fehler melden/Support und Copyright erreichbar. |
| E13 | `tests/test_crash_handler.py`, `test_crash_log.py`, `test_startup_failure_flows.py` | Start-/Crashdiagnose | Offen | Fehler vor und nach UI-Start nachvollziehbar, unsauberes Ende sichtbar; keine Endlosschleife oder automatische Löschung zur „Reparatur“. |

## Explizite Paritätsentscheidungen vor Umsetzung

1. **Parallelkunden:** Desktop `_kunde_festschreiben_und_wechseln` persistiert den zahlenden Kunden beim ersten gültigen Scan des nächsten Kunden, obwohl die Zahlungsansicht noch offen ist. Mobile Regeln verlangen bestätigten Abschluss. Funktionsziel sind parallele Entwürfe mit getrennten Zahlungszuständen; vorab keine stillschweigende Übernahme des Desktop-Commit-Zeitpunkts.
2. **HID im Gegeben-Feld:** Desktop `_gegeben_enter` erkennt angehängte Barcodes, stellt Betrag wieder her und leitet Scan weiter. Mobile Regeln begrenzen HID auf das vorgesehene Feld. Gleichwertige Arbeitsfähigkeit muss bewusst über eigenes Scan-Ziel und sichtbare Fehlleitung hergestellt werden, nicht über globales Abfangen.
3. **Gegeben optional:** Desktop nutzt Wechselgeldrechner optional und kann auch bei leerem/zu kleinem Betrag bestätigen. Mobile Demo erzwingt ausreichenden Betrag. Vollport braucht explizite Darstellung „Bargeld erhalten“ ohne falsche Tender-/Wechselgelddaten; nicht unbemerkt Validierung entfernen.
4. **V1:** Revisionslose Eingabe ist auf verifizierten V1-Markt beschränkt; V2-Prüfung bleibt strikt. Herkunft muss über Neustart/Export erhalten bleiben.
5. **Native Dateien und Drucken:** Android/iOS haben keine Windows-Pfade oder Windows-ESC/POS-Spooler. System-Dateidialoge, App-Ablage, Teilen/Preview und geprüfte native Druckerverbindungen erfüllen die fachlichen Aufgaben. Ein reiner PDF-Export ersetzt physischen Bondruck nicht automatisch.
6. **Aktuelle Identitätsänderungen:** Neue dirty-source Tests zu vollständiger Verkäuferidentität vor jedem Implementierungsschritt erneut lesen; kurze Verkäufernummer, Box/Stammnummer und globale Identität getrennt halten.

## Nachweise für spätere Abnahme

Diese Desktop-Tests wurden als Verhaltensanker gelesen/gezielt durchsucht, nicht ausgeführt. Mobile Abnahme benötigt eigene Tests sowie Gerätebelege; Desktop-Testexistenz ist kein Mobile-Erfolg.

| Gruppe | Besonders relevante Desktop-Tests |
|---|---|
| Navigation/Markt/Dateien | `test_home_tiles.py`, `test_market_ui.py`, `test_market_dialog_failure_flows.py`, `test_market_context.py`, `test_marktwechsel_rollback.py`, `test_checkout_atomic.py`, `test_file_io_failures.py` |
| Kasse/Fokus/Parallelkunden | `test_kassen_bedienung.py`, `test_kassen_anzeige.py`, `test_scan_anzeige.py`, `test_neuer_kunde.py`, `test_abrechnung_kundenwechsel.py`, `test_register_failure_flows.py` |
| Identität/Scan/Legacy | `test_barcodes_v2.py`, `test_scan_validation_edges.py`, `test_scan_resolver.py`, `test_seller_identity.py`, `test_manual_entry_dialog.py`, `test_import_dialog_v1_guard.py` |
| Entwurf/Wiederanlauf | `test_basket_draft.py`, `test_basket_journal.py`, `test_basket_recovery_ui.py`, `test_basket_recovery_controller.py`, `test_recovery_validation.py`, `test_beenden_offener_warenkorb.py`, `test_persistenz_haltbarkeit.py` |
| Suche/Profile/Belege | `test_artikelsuche.py`, `test_search_page_flows.py`, `test_fieldprofile_search_edges.py`, `test_feldprofil_spalten.py`, `test_table_model_contracts.py`, `test_bon_beleg.py`, `test_bon_drucker.py` |
| Sync/Archiv | `test_login_dialog_flows.py`, `test_export_dialog_flows.py`, `test_import_dialog_flows.py`, `test_conflict_dialog_flows.py`, `test_archive_dialog_flows.py`, `test_sync_failure_edges.py` |
| Nachbearbeitung | `test_ruecksortierung_page.py`, `test_reconciliation_input_flows.py`, `test_reconciliation_flows.py`, `test_payout_flows.py`, `test_report_page_flows.py`, `test_abrechnung_datenintegritaet.py`, `test_statistics_context.py` |
| Einstellungen/Hardware/Diagnose | `test_settings_transaction_edges.py`, `test_settings_kassenwechsel.py`, `test_camera_settings.py`, `test_camera_worker.py`, `test_logging_failure_flows.py`, `test_crash_handler.py`, `test_startup_failure_flows.py` |

Abnahme pro ID: Implementierungspfad, gezielter Test, Prüfdatum und gegebenenfalls Android-/iOS-Gerät ergänzen. Bis dahin bleibt der Ausgangsstatus bestehen. Inventar deckt alle gefundenen `gui/`-Seiten/Dialoge und deren sichtbare Aktionen sowie Konfigurations-/Controller-Einstiege ab; Detailverträge aus API, Abrechnung und Rücksortierung werden ergänzend verknüpft. Nicht angebundene Hilfsmodelle wie `ArtikelTableModel`/`artikel_preis_aendern` begründen allein keine erfundene Desktop-Oberfläche für freie Preise.

## Implementierungsnachweise vom 26.09.2026

Die obere Spalte **Ausgangsstatus** bleibt als historisches Inventar erhalten. Für den aktuellen Stand gilt die folgende Zuordnung. Alle 85 Einträge besitzen eine mobile Implementierung; **das ist keine vollständige Geräte- oder Produktionsabnahme**. Testdateien liegen unter `app/test/` und tragen die Endung `.dart`. Die genannten Suiten prüfen den jeweiligen Funktionsbereich; sie ersetzen keine Einzelprüfung sämtlicher nativer Dialoge.

| ID | Aktueller Stand | Mobile Quelle | Automatisierte Nachweise / Ergänzung |
|---|---|---|---|
| N01 | Implementiert; Fachtests vorhanden | `app/lib/main.dart; app/lib/ui/register_page.dart` | `widget_test; register_safety_test; market_library_test; settings_page_test`. |
| N02 | Implementiert; Fachtests vorhanden | `app/lib/main.dart; app/lib/ui/register_page.dart` | `widget_test; register_safety_test; market_library_test; settings_page_test`. |
| N03 | Implementiert; Fachtests vorhanden | `app/lib/main.dart; app/lib/ui/register_page.dart` | `widget_test; register_safety_test; market_library_test; settings_page_test`. |
| N04 | Implementiert; native Abnahme offen | `app/lib/main.dart; app/lib/ui/register_page.dart` | `widget_test; register_safety_test; market_library_test; settings_page_test`. |
| N05 | Implementiert; Fachtests vorhanden | `app/lib/main.dart; app/lib/ui/register_page.dart` | `widget_test; register_safety_test; market_library_test; settings_page_test`. |
| N06 | Implementiert; native Abnahme offen | `app/lib/main.dart; app/lib/ui/register_page.dart` | `widget_test; register_safety_test; market_library_test; settings_page_test`. |
| M01 | Implementiert; Fachtests vorhanden | `app/lib/data/market_library.dart; app/lib/ui/library_page.dart; app/lib/ui/catalog_pages.dart` | `market_library_test; catalog_pages_test; market_package_test`. |
| M02 | Implementiert; Fachtests vorhanden | `app/lib/data/market_library.dart; app/lib/ui/library_page.dart; app/lib/ui/catalog_pages.dart` | `market_library_test; catalog_pages_test; market_package_test`. |
| M03 | Implementiert; Fachtests vorhanden | `app/lib/data/market_library.dart; app/lib/ui/library_page.dart; app/lib/ui/catalog_pages.dart` | `market_library_test; catalog_pages_test; market_package_test`. |
| M04 | Implementiert; Fachtests vorhanden | `app/lib/data/market_library.dart; app/lib/ui/library_page.dart; app/lib/ui/catalog_pages.dart` | `market_library_test; catalog_pages_test; market_package_test`. |
| M05 | Implementiert; Fachtests vorhanden | `app/lib/data/market_library.dart; app/lib/ui/library_page.dart; app/lib/ui/catalog_pages.dart` | `market_library_test; catalog_pages_test; market_package_test`. |
| M06 | Implementiert; native Abnahme offen | `app/lib/data/market_library.dart; app/lib/ui/library_page.dart; app/lib/ui/catalog_pages.dart` | `market_library_test; catalog_pages_test; market_package_test`. |
| M07 | Implementiert; Fachtests vorhanden | `app/lib/data/market_library.dart; app/lib/ui/library_page.dart; app/lib/ui/catalog_pages.dart` | `market_library_test; catalog_pages_test; market_package_test`. |
| F01 | Implementiert; native Abnahme offen | `app/lib/ui/files_page.dart; app/lib/ui/library_page.dart; app/lib/services/desktop_archive.dart; app/lib/services/desktop_draft.dart` | `legacy_inspection_test; desktop_archive_test; desktop_draft_test; draft_store_test; full_checkout_test`. Private Bibliothek, validierte Einträge und native Dokumentauswahl; kein frei verschiebbarer Windows-Liveordner. |
| F02 | Implementiert; Fachtests vorhanden | `app/lib/ui/files_page.dart; app/lib/ui/library_page.dart; app/lib/services/desktop_archive.dart; app/lib/services/desktop_draft.dart` | `legacy_inspection_test; desktop_archive_test; desktop_draft_test; draft_store_test; full_checkout_test`. |
| F03 | Implementiert; Fachtests vorhanden | `app/lib/ui/files_page.dart; app/lib/ui/library_page.dart; app/lib/services/desktop_archive.dart; app/lib/services/desktop_draft.dart` | `legacy_inspection_test; desktop_archive_test; desktop_draft_test; draft_store_test; full_checkout_test`. |
| F04 | Implementiert; native Abnahme offen | `app/lib/ui/files_page.dart; app/lib/ui/library_page.dart; app/lib/services/desktop_archive.dart; app/lib/services/desktop_draft.dart` | `legacy_inspection_test; desktop_archive_test; desktop_draft_test; draft_store_test; full_checkout_test`. |
| F05 | Implementiert; Fachtests vorhanden | `app/lib/ui/files_page.dart; app/lib/ui/library_page.dart; app/lib/services/desktop_archive.dart; app/lib/services/desktop_draft.dart` | `legacy_inspection_test; desktop_archive_test; desktop_draft_test; draft_store_test; full_checkout_test`. |
| F06 | Implementiert; native Abnahme offen | `app/lib/ui/files_page.dart; app/lib/ui/library_page.dart; app/lib/services/desktop_archive.dart; app/lib/services/desktop_draft.dart` | `legacy_inspection_test; desktop_archive_test; desktop_draft_test; draft_store_test; full_checkout_test`. Sitzungsschlüssel aus Markt/Kasse/Generation/Checksum; Hash der unveränderten Importquelle gespeichert. |
| F07 | Implementiert; Fachtests vorhanden | `app/lib/ui/files_page.dart; app/lib/ui/library_page.dart; app/lib/services/desktop_archive.dart; app/lib/services/desktop_draft.dart` | `legacy_inspection_test; desktop_archive_test; desktop_draft_test; draft_store_test; full_checkout_test`. |
| F08 | Implementiert; Fachtests vorhanden | `app/lib/ui/files_page.dart; app/lib/ui/library_page.dart; app/lib/services/desktop_archive.dart; app/lib/services/desktop_draft.dart` | `legacy_inspection_test; desktop_archive_test; desktop_draft_test; draft_store_test; full_checkout_test`. |
| K01 | Implementiert; Fachtests vorhanden | `app/lib/data/checkout_store.dart; app/lib/ui/register_page.dart; app/lib/ui/payment_dialog.dart` | `checkout_store_test; full_checkout_test; draft_store_test; register_safety_test; widget_test`. |
| K02 | Implementiert; native Abnahme offen | `app/lib/data/checkout_store.dart; app/lib/ui/register_page.dart; app/lib/ui/payment_dialog.dart` | `checkout_store_test; full_checkout_test; draft_store_test; register_safety_test; widget_test`. |
| K03 | Implementiert; Fachtests vorhanden | `app/lib/data/checkout_store.dart; app/lib/ui/register_page.dart; app/lib/ui/payment_dialog.dart` | `checkout_store_test; full_checkout_test; draft_store_test; register_safety_test; widget_test`. |
| K04 | Implementiert; Fachtests vorhanden | `app/lib/data/checkout_store.dart; app/lib/ui/register_page.dart; app/lib/ui/payment_dialog.dart` | `checkout_store_test; full_checkout_test; draft_store_test; register_safety_test; widget_test`. |
| K05 | Implementiert; Fachtests vorhanden | `app/lib/data/checkout_store.dart; app/lib/ui/register_page.dart; app/lib/ui/payment_dialog.dart` | `checkout_store_test; full_checkout_test; draft_store_test; register_safety_test; widget_test`. |
| K06 | Implementiert; Fachtests vorhanden | `app/lib/data/checkout_store.dart; app/lib/ui/register_page.dart; app/lib/ui/payment_dialog.dart` | `checkout_store_test; full_checkout_test; draft_store_test; register_safety_test; widget_test`. |
| K07 | Implementiert; Fachtests vorhanden | `app/lib/data/checkout_store.dart; app/lib/ui/register_page.dart; app/lib/ui/payment_dialog.dart` | `checkout_store_test; full_checkout_test; draft_store_test; register_safety_test; widget_test`. |
| K08 | Implementiert; Fachtests vorhanden | `app/lib/data/checkout_store.dart; app/lib/ui/register_page.dart; app/lib/ui/payment_dialog.dart` | `checkout_store_test; full_checkout_test; draft_store_test; register_safety_test; widget_test`. |
| K09 | Implementiert; Fachtests vorhanden | `app/lib/data/checkout_store.dart; app/lib/ui/register_page.dart; app/lib/ui/payment_dialog.dart` | `checkout_store_test; full_checkout_test; draft_store_test; register_safety_test; widget_test`. |
| K10 | Implementiert; Fachtests vorhanden | `app/lib/data/checkout_store.dart; app/lib/ui/register_page.dart; app/lib/ui/payment_dialog.dart` | `checkout_store_test; full_checkout_test; draft_store_test; register_safety_test; widget_test`. |
| K11 | Implementiert; Fachtests vorhanden | `app/lib/data/checkout_store.dart; app/lib/ui/register_page.dart; app/lib/ui/payment_dialog.dart` | `checkout_store_test; full_checkout_test; draft_store_test; register_safety_test; widget_test`. |
| K12 | Implementiert; Fachtests vorhanden | `app/lib/data/checkout_store.dart; app/lib/ui/register_page.dart; app/lib/ui/payment_dialog.dart` | `checkout_store_test; full_checkout_test; draft_store_test; register_safety_test; widget_test`. |
| K13 | Implementiert; Fachtests vorhanden | `app/lib/data/checkout_store.dart; app/lib/ui/register_page.dart; app/lib/ui/payment_dialog.dart` | `checkout_store_test; full_checkout_test; draft_store_test; register_safety_test; widget_test`. |
| K14 | Implementiert; Fachtests vorhanden | `app/lib/data/checkout_store.dart; app/lib/ui/register_page.dart; app/lib/ui/payment_dialog.dart` | `checkout_store_test; full_checkout_test; draft_store_test; register_safety_test; widget_test`. |
| K15 | Implementiert; Fachtests vorhanden | `app/lib/data/checkout_store.dart; app/lib/ui/register_page.dart; app/lib/ui/payment_dialog.dart` | `checkout_store_test; full_checkout_test; draft_store_test; register_safety_test; widget_test`. |
| K16 | Implementiert; Fachtests vorhanden | `app/lib/data/checkout_store.dart; app/lib/ui/register_page.dart; app/lib/ui/payment_dialog.dart` | `checkout_store_test; full_checkout_test; draft_store_test; register_safety_test; widget_test`. Dynamische geparkte Vorgänge; Parken aus Zahlung erhält Betrag und Vorgangsidentität. Kein automatischer Abschluss durch Folgescan. |
| K17 | Implementiert; Fachtests vorhanden | `app/lib/data/checkout_store.dart; app/lib/ui/register_page.dart; app/lib/ui/payment_dialog.dart` | `checkout_store_test; full_checkout_test; draft_store_test; register_safety_test; widget_test`. Bestätigte Vorgänge unveränderlich; Abbruch vor Bestätigung lässt Entwurf bestehen. |
| K18 | Implementiert; Fachtests vorhanden | `app/lib/data/checkout_store.dart; app/lib/ui/register_page.dart; app/lib/ui/payment_dialog.dart` | `checkout_store_test; full_checkout_test; draft_store_test; register_safety_test; widget_test`. |
| K19 | Implementiert; Fachtests vorhanden | `app/lib/data/checkout_store.dart; app/lib/ui/register_page.dart; app/lib/ui/payment_dialog.dart` | `checkout_store_test; full_checkout_test; draft_store_test; register_safety_test; widget_test`. |
| K20 | Implementiert; Fachtests vorhanden | `app/lib/data/checkout_store.dart; app/lib/ui/register_page.dart; app/lib/ui/payment_dialog.dart` | `checkout_store_test; full_checkout_test; draft_store_test; register_safety_test; widget_test`. Verkauf/Rückgabe im selben Entwurf einschließlich Desktop-Roundtrip getestet. |
| K21 | Implementiert; native Abnahme offen | `app/lib/data/checkout_store.dart; app/lib/ui/register_page.dart; app/lib/ui/payment_dialog.dart` | `checkout_store_test; full_checkout_test; draft_store_test; register_safety_test; widget_test`. |
| K22 | Implementiert; native Abnahme offen | `app/lib/data/checkout_store.dart; app/lib/ui/register_page.dart; app/lib/ui/payment_dialog.dart` | `checkout_store_test; full_checkout_test; draft_store_test; register_safety_test; widget_test`. |
| K23 | Implementiert; Fachtests vorhanden | `app/lib/data/checkout_store.dart; app/lib/ui/register_page.dart; app/lib/ui/payment_dialog.dart` | `checkout_store_test; full_checkout_test; draft_store_test; register_safety_test; widget_test`. SQLite-Commit wird abgewartet; Speicherfehler bleibt sichtbar, Zahlungsdialog erhält Eingabe. |
| K24 | Implementiert; Fachtests vorhanden | `app/lib/data/checkout_store.dart; app/lib/ui/register_page.dart; app/lib/ui/payment_dialog.dart` | `checkout_store_test; full_checkout_test; draft_store_test; register_safety_test; widget_test`. |
| K25 | Implementiert; Fachtests vorhanden | `app/lib/data/checkout_store.dart; app/lib/ui/register_page.dart; app/lib/ui/payment_dialog.dart` | `checkout_store_test; full_checkout_test; draft_store_test; register_safety_test; widget_test`. |
| S01 | Implementiert; Fachtests vorhanden | `app/lib/domain/catalog_search.dart; app/lib/ui/catalog_pages.dart; app/lib/services/catalog_reports.dart` | `catalog_pages_test; operations_reports_test`. |
| S02 | Implementiert; Fachtests vorhanden | `app/lib/domain/catalog_search.dart; app/lib/ui/catalog_pages.dart; app/lib/services/catalog_reports.dart` | `catalog_pages_test; operations_reports_test`. |
| S03 | Implementiert; Fachtests vorhanden | `app/lib/domain/catalog_search.dart; app/lib/ui/catalog_pages.dart; app/lib/services/catalog_reports.dart` | `catalog_pages_test; operations_reports_test`. |
| S04 | Implementiert; Fachtests vorhanden | `app/lib/domain/catalog_search.dart; app/lib/ui/catalog_pages.dart; app/lib/services/catalog_reports.dart` | `catalog_pages_test; operations_reports_test`. |
| S05 | Implementiert; Fachtests vorhanden | `app/lib/domain/catalog_search.dart; app/lib/ui/catalog_pages.dart; app/lib/services/catalog_reports.dart` | `catalog_pages_test; operations_reports_test`. |
| S06 | Implementiert; native Abnahme offen | `app/lib/domain/catalog_search.dart; app/lib/ui/catalog_pages.dart; app/lib/services/catalog_reports.dart` | `catalog_pages_test; operations_reports_test`. |
| S07 | Implementiert; Fachtests vorhanden | `app/lib/domain/catalog_search.dart; app/lib/ui/catalog_pages.dart; app/lib/services/catalog_reports.dart` | `catalog_pages_test; operations_reports_test`. |
| B01 | Implementiert; Fachtests vorhanden | `app/lib/services/api_client.dart; app/lib/services/sync_service.dart; app/lib/ui/sync_page.dart; app/lib/ui/archive_page.dart` | `api_client_transport_test; sync_service_test; sync_page_test; archive_page_test`. |
| B02 | Implementiert; Fachtests vorhanden | `app/lib/services/api_client.dart; app/lib/services/sync_service.dart; app/lib/ui/sync_page.dart; app/lib/ui/archive_page.dart` | `api_client_transport_test; sync_service_test; sync_page_test; archive_page_test`. |
| B03 | Implementiert; native Abnahme offen | `app/lib/services/api_client.dart; app/lib/services/sync_service.dart; app/lib/ui/sync_page.dart; app/lib/ui/archive_page.dart` | `api_client_transport_test; sync_service_test; sync_page_test; archive_page_test`. |
| B04 | Implementiert; Fachtests vorhanden | `app/lib/services/api_client.dart; app/lib/services/sync_service.dart; app/lib/ui/sync_page.dart; app/lib/ui/archive_page.dart` | `api_client_transport_test; sync_service_test; sync_page_test; archive_page_test`. |
| B05 | Implementiert; Fachtests vorhanden | `app/lib/services/api_client.dart; app/lib/services/sync_service.dart; app/lib/ui/sync_page.dart; app/lib/ui/archive_page.dart` | `api_client_transport_test; sync_service_test; sync_page_test; archive_page_test`. |
| B06 | Implementiert; Fachtests vorhanden | `app/lib/services/api_client.dart; app/lib/services/sync_service.dart; app/lib/ui/sync_page.dart; app/lib/ui/archive_page.dart` | `api_client_transport_test; sync_service_test; sync_page_test; archive_page_test`. |
| B07 | Implementiert; Fachtests vorhanden | `app/lib/services/api_client.dart; app/lib/services/sync_service.dart; app/lib/ui/sync_page.dart; app/lib/ui/archive_page.dart` | `api_client_transport_test; sync_service_test; sync_page_test; archive_page_test`. Alle lokalen Märkte ohne Aktivierungswechsel, Marktfilter, Läufe, Verweise und Originalpakete. |
| B08 | Implementiert; native Abnahme offen | `app/lib/services/api_client.dart; app/lib/services/sync_service.dart; app/lib/ui/sync_page.dart; app/lib/ui/archive_page.dart` | `api_client_transport_test; sync_service_test; sync_page_test; archive_page_test`. Gefilterter Export und bestätigte Löschung genau eines Protokolls; keine Löschung von Verkäufen. |
| A01 | Implementiert; Fachtests vorhanden | `app/lib/domain/accounting.dart; app/lib/domain/reconciliation.dart; app/lib/ui/operations_pages.dart; app/lib/services/operations_reports.dart` | `operations_test; operations_pages_test; operations_reports_test; desktop_archive_test`. |
| A02 | Implementiert; native Abnahme offen | `app/lib/domain/accounting.dart; app/lib/domain/reconciliation.dart; app/lib/ui/operations_pages.dart; app/lib/services/operations_reports.dart` | `operations_test; operations_pages_test; operations_reports_test; desktop_archive_test`. |
| A03 | Implementiert; Fachtests vorhanden | `app/lib/domain/accounting.dart; app/lib/domain/reconciliation.dart; app/lib/ui/operations_pages.dart; app/lib/services/operations_reports.dart` | `operations_test; operations_pages_test; operations_reports_test; desktop_archive_test`. |
| A04 | Implementiert; Fachtests vorhanden | `app/lib/domain/accounting.dart; app/lib/domain/reconciliation.dart; app/lib/ui/operations_pages.dart; app/lib/services/operations_reports.dart` | `operations_test; operations_pages_test; operations_reports_test; desktop_archive_test`. |
| A05 | Implementiert; Fachtests vorhanden | `app/lib/domain/accounting.dart; app/lib/domain/reconciliation.dart; app/lib/ui/operations_pages.dart; app/lib/services/operations_reports.dart` | `operations_test; operations_pages_test; operations_reports_test; desktop_archive_test`. |
| A06 | Implementiert; native Abnahme offen | `app/lib/domain/accounting.dart; app/lib/domain/reconciliation.dart; app/lib/ui/operations_pages.dart; app/lib/services/operations_reports.dart` | `operations_test; operations_pages_test; operations_reports_test; desktop_archive_test`. |
| A07 | Implementiert; Fachtests vorhanden | `app/lib/domain/accounting.dart; app/lib/domain/reconciliation.dart; app/lib/ui/operations_pages.dart; app/lib/services/operations_reports.dart` | `operations_test; operations_pages_test; operations_reports_test; desktop_archive_test`. Vollständige Verkäuferidentität, Teilboxen und rationale Centgebühren mit half-even. |
| A08 | Implementiert; native Abnahme offen | `app/lib/domain/accounting.dart; app/lib/domain/reconciliation.dart; app/lib/ui/operations_pages.dart; app/lib/services/operations_reports.dart` | `operations_test; operations_pages_test; operations_reports_test; desktop_archive_test`. |
| A09 | Implementiert; Fachtests vorhanden | `app/lib/domain/accounting.dart; app/lib/domain/reconciliation.dart; app/lib/ui/operations_pages.dart; app/lib/services/operations_reports.dart` | `operations_test; operations_pages_test; operations_reports_test; desktop_archive_test`. |
| A10 | Implementiert; native Abnahme offen | `app/lib/domain/accounting.dart; app/lib/domain/reconciliation.dart; app/lib/ui/operations_pages.dart; app/lib/services/operations_reports.dart` | `operations_test; operations_pages_test; operations_reports_test; desktop_archive_test`. |
| A11 | Implementiert; Fachtests vorhanden | `app/lib/domain/accounting.dart; app/lib/domain/reconciliation.dart; app/lib/ui/operations_pages.dart; app/lib/services/operations_reports.dart` | `operations_test; operations_pages_test; operations_reports_test; desktop_archive_test`. |
| E01 | Implementiert; Fachtests vorhanden | `app/lib/ui/settings_page.dart; app/lib/ui/camera_page.dart; app/lib/services/app_diagnostics.dart; app/lib/data/checkout_store.dart` | `settings_page_test; full_checkout_test; register_safety_test; app_diagnostics_test`. |
| E02 | Implementiert; native Abnahme offen | `app/lib/ui/settings_page.dart; app/lib/ui/camera_page.dart; app/lib/services/app_diagnostics.dart; app/lib/data/checkout_store.dart` | `settings_page_test; full_checkout_test; register_safety_test; app_diagnostics_test`. Mobile Entsprechung: private SQLite-Bibliothek; Dokumentauswahl für Import, Sicherung und Export. Keine SQLite-Datei auf unsicheren Cloud-Provider verschieben. |
| E03 | Implementiert; Fachtests vorhanden | `app/lib/ui/settings_page.dart; app/lib/ui/camera_page.dart; app/lib/services/app_diagnostics.dart; app/lib/data/checkout_store.dart` | `settings_page_test; full_checkout_test; register_safety_test; app_diagnostics_test`. |
| E04 | Implementiert; native Abnahme offen | `app/lib/ui/settings_page.dart; app/lib/ui/camera_page.dart; app/lib/services/app_diagnostics.dart; app/lib/data/checkout_store.dart` | `settings_page_test; full_checkout_test; register_safety_test; app_diagnostics_test`. Front/Rückkamera gespeichert; erkannte Kamerazahl und Wechsel im Scanbildschirm. Tatsächliche Hardware offen. |
| E05 | Implementiert; native Abnahme offen | `app/lib/ui/settings_page.dart; app/lib/ui/camera_page.dart; app/lib/services/app_diagnostics.dart; app/lib/data/checkout_store.dart` | `settings_page_test; full_checkout_test; register_safety_test; app_diagnostics_test`. Native Formate EAN-8, EAN-13, Code128, QR, automatisch; V2 bleibt MM1/revisionsstreng. |
| E06 | Implementiert; native Abnahme offen | `app/lib/ui/settings_page.dart; app/lib/ui/camera_page.dart; app/lib/services/app_diagnostics.dart; app/lib/data/checkout_store.dart` | `settings_page_test; full_checkout_test; register_safety_test; app_diagnostics_test`. |
| E07 | Implementiert; Fachtests vorhanden | `app/lib/ui/settings_page.dart; app/lib/ui/camera_page.dart; app/lib/services/app_diagnostics.dart; app/lib/data/checkout_store.dart` | `settings_page_test; full_checkout_test; register_safety_test; app_diagnostics_test`. |
| E08 | Implementiert; native Abnahme offen | `app/lib/ui/settings_page.dart; app/lib/ui/camera_page.dart; app/lib/services/app_diagnostics.dart; app/lib/data/checkout_store.dart` | `settings_page_test; full_checkout_test; register_safety_test; app_diagnostics_test`. Systemdruck/Preview und PDF-Teilen; kein ungeprüfter direkter ESC/POS-Transport. |
| E09 | Implementiert; Fachtests vorhanden | `app/lib/ui/settings_page.dart; app/lib/ui/camera_page.dart; app/lib/services/app_diagnostics.dart; app/lib/data/checkout_store.dart` | `settings_page_test; full_checkout_test; register_safety_test; app_diagnostics_test`. |
| E10 | Implementiert; native Abnahme offen | `app/lib/ui/settings_page.dart; app/lib/ui/camera_page.dart; app/lib/services/app_diagnostics.dart; app/lib/data/checkout_store.dart` | `settings_page_test; full_checkout_test; register_safety_test; app_diagnostics_test`. SQLite-Log mit Zeitstempel, Retention und Bytebudget; separater rotierter Startfehlerlog. |
| E11 | Implementiert; Fachtests vorhanden | `app/lib/ui/settings_page.dart; app/lib/ui/camera_page.dart; app/lib/services/app_diagnostics.dart; app/lib/data/checkout_store.dart` | `settings_page_test; full_checkout_test; register_safety_test; app_diagnostics_test`. |
| E12 | Implementiert; native Abnahme offen | `app/lib/ui/settings_page.dart; app/lib/ui/camera_page.dart; app/lib/services/app_diagnostics.dart; app/lib/data/checkout_store.dart` | `settings_page_test; full_checkout_test; register_safety_test; app_diagnostics_test`. |
| E13 | Implementiert; native Abnahme offen | `app/lib/ui/settings_page.dart; app/lib/ui/camera_page.dart; app/lib/services/app_diagnostics.dart; app/lib/data/checkout_store.dart` | `settings_page_test; full_checkout_test; register_safety_test; app_diagnostics_test`. Flutter-/Plattformfehlerhandler, dateibasierte Startdiagnose und explizite Entwurfsprüfung. |

### Abnahmegrenzen

- Android-Debug-APK lokal erfolgreich gebaut. Ein Build belegt keine Kamera-, USB-, Drucker- oder Datei-Provider-Funktion am Gerät.
- iOS-Projekt und CI-Buildjob vorhanden; Mac/Xcode-Build, Signierung und reale iOS-Bedienung noch nicht ausgeführt.
- Backend-Verträge mit synthetischen Antworten getestet; kein produktiver Organisator-Login oder Upload echter Verkäufe durchgeführt.
- Kleine Bildschirmgrößen werden zusätzlich per Widget-Rendering kontrolliert. Native Systemdialoge und unterbrochene OS-Prozesse benötigen die separate Hardware-Abnahme.
- Der vollständige End-to-End-Abnahmestatus bleibt offen, bis diese Nachweise vorliegen. Keine Store-Veröffentlichung oder Hardwarefreigabe aus dieser Matrix ableiten.

## Umstrukturierung und Bedienung am 02.10.2026

Die mobilen Quellen liegen vollständig unter `app/`; alle 85 Inventarpunkte
bleiben Bestandteil des Ports. Die Navigation bündelt Start, Kasse, Belege und
Mehr; Verwaltung, Synchronisation, Archive, Abrechnung und Rücksortierung bleiben
erreichbar. Gemeinsame helle/dunkle Gestaltung, umbruchfähige Aktionen und
skalierende Schrift ersetzen uneinheitliche Einzelansichten.

K16 verwendet eine dynamische Parkliste statt festem Kunde A/B. Vorgangsnummern
bezeichnen Transaktionen ohne personenbezogene Kundenkartei. Reservierungen und
Stornobindungen gelten über alle geparkten Entwürfe; Wiederaufnahme verlangt nach
Neustart eine ausdrückliche Prüfung. Die Migration alter A/B-Entwürfe und
Sicherungen erhält Positionen, Zahlungsbeträge und Ereignis-IDs.

Desktop-Kompatibilität: `services/basket_draft.py:158` der Referenz akzeptiert nur
Entwürfe oberhalb des bereits abgeschlossenen Nummernstands. Der mobile Export
bietet erforderlichenfalls eine bestätigte, atomar gespeicherte Neunummerierung.
Bereits exportierte Ereignis-IDs dürfen später nicht mit einer anderen Nummer
exportiert werden; die App blockiert diesen Fall ausdrücklich. Es gibt keine
stille Umnummerierung nur in einer Datei. Bereits vor Einführung der Exporthistorie
ausgegebene Dateien können nicht rückwirkend erkannt werden. Desktop-Quelldateien bleiben unverändert.

Gezielte Nachweise: `app/test/parked_drafts_test.dart` (Migration, beliebige
Parkliste, Reservierungen, Rollback, Exportidentität, beschädigte Sicherung),
`app/test/redesign_layout_test.dart` (Bildschirme hell/dunkel, 320 Pixel, große
Schrift, Navigation und Exportdialog). Datierten Gesamtprüfstand siehe
[Prüfbericht](verification.md). Store-, Server- und Hardwareabnahme bleiben getrennt.
