# LifeHub – Teststrategie

Ziel: Jedes Feature ist automatisch getestet. Kein Release, solange der Release-Check
(`tool/check.ps1` bzw. `tool/check.sh`) oder die CI rot ist.

## Aufbau

`test/` spiegelt `lib/`:

| Bereich | Datei | Was wird geprüft |
|---|---|---|
| App | `app/app_test.dart` | Echte App startet ohne Sitzung auf dem Login |
| Core | `core/database_schema_test.dart` | Jede Spalte, die ein Model schreibt, existiert im Schema; Sync-Spalten vorhanden |
| | `core/ui_test.dart` | `formatEuro`, Lösch-Dialog (bestätigen, abbrechen, Fehler) |
| Auth | `features/auth/auth_service_test.dart` | PBKDF2-Hashing, alte Hash-Formate, Registrierung mit Standarddaten, doppelte E-Mail, Passwort zurücksetzen (Alt-Hash ohne, aktueller Hash nur mit Gerätesperre), Passwort ändern, kein Klartext im Secure Storage |
| | `features/auth/auth_screens_test.dart` | Registrieren und Anmelden über die Oberfläche, falsches Passwort, unbekannte E-Mail, Konto aus alter Version → „Passwort vergessen?“, doppelte Registrierung, Formularvalidierung, Aufforderung zum neuen Passwort bei veraltetem Hash |
| | `features/auth/wrapper_test.dart` | Ohne Sitzung → Login |
| Finanzen | `features/finance/repositories/…` | Salden pro Nutzer, Update/Löschen/Alles löschen, Umbuchung, Fixkosten nachbuchen (mehrere, nie doppelt, Monatsende, Enddatum), Umbenennen zieht Referenzen mit |
| | `features/finance/models/…` | Intervall-Berechnung, alte Schreibweisen, Sparziel-Konten |
| | `features/finance/services/…` | Prognose, CSV-Import (Banken), JSON/CSV-Export ohne Passwort-Hash |
| | `features/finance/screens/…` | Buchung und Umbuchung über das Formular ändern die Salden, Validierung, Listen (Transaktionen, Konten, Kategorien, Fixkosten), Finanz-Hub, CSV-Import-Screen |
| | `features/finance/widgets/charts_test.dart` | Torten- und Balkendiagramm |
| Dashboard | `features/dashboard/home_screen_test.dart` | Heute-Screen zeigt Habits, To-Dos, Termine, Finanzen; Habit abhaken |
| To-Dos | `features/todos/…` | Repository CRUD; Schnell-Hinzufügen und Abhaken im Screen |
| Bedienung | `core/app_actions_test.dart` | + über der Navigation (mit/ohne Gestennavigation), Wischen → Löschen → Rückgängig, Fehler als Snackbar |
| | `core/repeat_test.dart` | Wöchentlich/alle 2 Wochen/Wochentage, täglich, Monatsende, 29. Februar, Speichern |
| Layout | `app/layout_test.dart` | Alle Tab-Seiten, Editoren und Listen bei 360 dp, 130 % Schrift und Gestennavigation ohne Overflow |
| To-Dos | `features/todos/todo_repository_test.dart` | Wiederkehrend: nächstes Vorkommen genau einmal, Uhrzeit bleibt, Rückgängig |
| | `features/todos/todo_list_screen_test.dart` | + öffnet alle Felder, Fälligkeit heute, wöchentlich alle 2 Wochen, Wischen → Rückgängig |
| Einkauf | `features/lists/lists_test.dart` | Mengen parsen/formatieren, Packungsplan, Aufaddieren je Einheit, Herkünfte entfernen/zurück, gekaufte Packung in den Vorrat |
| Essensplan | `features/meals/meal_plan_repository_test.dart` (Gruppe `batches`) | Verteilung vollständig, Umverteilen behält Gegessenes, Löschen/Rückgängig, Einkauf je Block ganzes Rezept × Faktor, wieder entfernbar, „Gekocht“ bucht Vorrat ab |
| Training | `features/fitness/method_timer_test.dart` | Stufenintervall: Satz über 7:30 hinaus, Pause = Satzdauer, kein neuer Satz nach Ablauf in der Pause; Vorschau; Hochintensität ohne Wiederholungen |
| Finanzen | `features/finance/services/budget_plan_service_test.dart` | Bilanz, Fixkosten nicht doppelt, Warnung bei Überschreitung, Termine/Monatswert wöchentlicher Fixkosten |
| Kassenzettel | `features/receipts/receipt_parser_test.dart` | ALDI/REWE/dm/Hofladen: Händler, Datum, Summe, Zahlart, Positionen mit Stück, Gewicht, Packungsgröße, Rabatt, Pfand; Zeilenbildung aus OCR-Rahmen |
| | `features/receipts/receipt_analyzer_test.dart` | Kategorie (Händlerart, gelernt aus Verlauf, Tanken, Rückfall), Konto, Lebensmittel trotz Abkürzungen, Vorratsauswahl |
| | `features/receipts/receipt_screens_test.dart` | Foto → Prüfen → Betrag/Menge/Einheit ändern, Position abwählen → Buchung und Vorrat gespeichert; Einstieg im Vorrat; kein Text erkannt |
| Kalender | `features/calendar/birthday_test.dart` | Geburtstage: jährliche Vorkommen, 29. Februar, nächstes Vorkommen, Alter, Erinnerung um 9 Uhr inkl. Folgejahr, Editor-Vorlage mit Datum in der Vergangenheit, Anzeige in Kalender und Heute |
| Kalender | `features/calendar/…` | Repository (Dauer, Sortierung, pro Nutzer, Soft-Delete); Kalender-Screen |
| Habits | `features/habits/…` | Streak-Logik, geplante Tage, XP genau einmal pro Abhaken, Löschen; Tracker-Screen |
| Profil | `features/profile/profile_screen_test.dart` | Passwort ändern (falsch/richtig), Profil speichern behält Passwort |
| Vision Board | `features/vision/vision_repository_test.dart` | Vorlage (6 Bereiche/18 Ziele), Zähler, Schritt-Reihenfolge (freigeschaltet/gesperrt), To-Dos blockieren den Abschluss, Verknüpfen, Verschieben, Löschen behält To-Dos |
| | `features/vision/vision_image_store_test.dart` | Bilder werden in den App-Ordner kopiert (relativer Pfad), alle Vorlagenbilder sind als Asset vorhanden, Löschen nur eigener Bilder |
| | `features/vision/vision_screens_test.dart` | Board: Vorlage inkl. Bilder, „Bild hinzufügen“ bei Bereichen ohne Bild, Abhaken → Status, Bereich/Ziel anlegen, Tipp öffnet Plan; Plan: Schritte anlegen, To-Do aus Schritt anlegen, abhaken, Schritt abschließen, bestehendes To-Do verknüpfen; Ziel-Hinweis in der To-Do-Liste; Heute-Screen; Handy-Layout (360 dp) ohne Überlauf |
| Core | `core/database_migration_test.dart` | Upgrade einer v14-Datenbank: neue Tabellen und Spalten (inkl. aller Lifestyle-Tabellen), Daten bleiben erhalten |
| App | `app/home_shell_test.dart` | Fünf Tabs passen auf 360 dp, Tabs und Unterbereiche wechseln |
| Inventar | `features/inventory/inventory_test.dart` | Ablauf/Alter, Filter, Sortierung, Status-Zähler, Verbrauchen, Getragen, Erinnerungen |
| | `features/inventory/inventory_screen_test.dart` | Suchen, Filtern, Schnell-Hinzufügen, Wischen, Editor, Handy-Layout |
| Ernährung | `features/fitness/nutrition_test.dart` | Makro-Summen, Ziele, Vorrat-Abbuchung, Open Food Facts (Treffer, unbekannt, Netzfehler) |
| | `features/fitness/nutrition_screen_test.dart` | Lebensmittel anlegen und eintragen, Barcode-Scan (gefakter Scanner), offline: Barcode einem Standardprodukt zuordnen und beim zweiten Scan ohne Netz finden, Standardprodukte auswählen, Aus Vorrat, Handy-Layout |
| Essensplan | `features/meals/meal_plan_repository_test.dart` | Katalog vollständig, Mengen skalieren/runden, Zeilen parsen, Plan nach Uhrzeit, gegessen ↔ Protokoll (auch nach Löschen im Protokoll), Zutaten zusammengefasst ohne Duplikate auf die Einkaufsliste, eigene Rezepte |
| | `features/meals/meal_plan_screens_test.dart` | Gericht fürs Mittagessen wählen, Rezept öffnen, Portionen ändern, als gegessen eintragen; Rezeptliste filtern, Zutaten auf Einkaufsliste, Einplanen; eigenes Rezept aus der Auswahl; Heute-Karte; Fitness-Tab; Handy-Layout |
| Training | `features/fitness/workout_test.dart` | Startübungen, Workouts (Reihenfolge, ersetzen), Plan inkl. Wochenwiederholung ohne Duplikate, Session vorbelegt → erledigt, Überspringen, Fortschritt |
| | `features/fitness/training_screen_test.dart` | Workout zusammenstellen und einplanen, Session protokollieren und beenden, Überspringen (nach rechts wischen), ein Katalog mit eigenen Übungen, Handy-Layout |
| Katalog | `features/fitness/catalog_test.dart` | Eindeutige Schlüssel, jede Übung hat Animation und Anleitung, Animationen bleiben im Bild, Pläne verweisen nur auf Katalog-Übungen, Übernehmen ist idempotent, Block-Import (Wochentage, Supersatz-Werte) |
| | `features/fitness/catalog_screen_test.dart` | Katalog suchen/filtern, Detail + hinzufügen, Auswahl im Workout-Editor, Plan-Block übernehmen, Handy-Layout |
| Timer | `features/fitness/method_timer_test.dart` | Stufenintervall (Pause = Arbeitszeit, min. 1 s, Muskelversagen zählt und geht abwärts, 7:30-Block), Intervall-/Supersatz (Takt, Paare, verpasste Sätze), Zirkel (Runden × Wdh.), Hochintensität (20/10 s, Wechsel), Signale, Überspringen |
| | `features/fitness/schedule_once_test.dart` | Einmalig einplanen: Plan-Block auf die nächsten Wochentage, im Editor per Datum, aus der Workout-Liste, Import-Dialog |
| | `features/fitness/method_session_test.dart` | Workout aus der Liste starten und mit Timer durchlaufen, Stufen-Leiter und vorzeitiges Beenden, Trainingsform im Editor, Handy-Layout |
| Listen | `features/lists/lists_test.dart` | Einkauf: Sortierung, Abhaken, Erledigte entfernen, Übernahme in Vorrat/Kleiderschrank/Pflege; Geschenke: Reihenfolge nach Anlass, Status, Summe, Idee auf Einkaufsliste, Liste löschen |
| | `features/lists/lists_screens_test.dart` | Schnell hinzufügen mit Menge, abhaken und in den Vorrat, Erledigte entfernen, Geschenkeliste anlegen und Idee kaufen, Parfüm im Kleiderschrank, Handy-Layout |
| App | `app/home_shell_test.dart` (Buttons) | „Outfit“, „Wunsch“ und „Liste“ sind auf 360 dp oberhalb der Navigation antippbar |
| Style | `features/style/style_test.dart` | Outfits mit Teilen, Tragen zählt bei Outfit und Teilen, Kauf bucht Ausgabe + Kleidungsstück, Budget, Sortierung der Wunschliste |
| | `features/style/style_screens_test.dart` | Outfit zusammenstellen und tragen, Wunsch anlegen und kaufen, Handy-Layout |
| | `core/dictation_service_test.dart` | Stille nach dem Antippen beendet nicht, späte Ende-Meldung startet nicht doppelt, nach 10 s Schluss, Stopp sofort, ohne Erkennung `false` |
| Foto-Mahlzeit | `features/fitness/nutrition_label_parser_test.dart` | Deutsche/englische Tabellen, kJ/kcal in einer oder zwei Zeilen, Portion, „davon …“, OCR-Kommas, verschmolzene Spalten (Emulator-Fund), unvollständig/leer |
| | `features/fitness/meal_photo_ai_test.dart` | Anfrage (Schlüssel, Modell, Bild, JSON-Schema), Antwort → Schätzung, kein Schlüssel = nichts gesendet, 401/offline/Ablehnung/kaputtes JSON, Schlüssel im Secure Storage |
| | `features/fitness/nutrition_screen_test.dart` (`photo`) | Tabelle → Prüfung → 40 g = 148 kcal; Gericht → „Geschätzt …“ → 300 g eingetragen, in der Suche; ohne Schlüssel Dialog „Zum Profil“; unlesbar → „Manuell eingeben“; KI-Fehler; Profil-Schlüssel prüfen/speichern/entfernen |
| Meal Prep | `features/meals/pantry_check_test.dart` | Zutat ↔ Vorrat: reicht, teilweise (kg/g), fehlt, Stück-Einheiten, nicht vergleichbar (TL aus Packung), Reservierung anderer Blöcke, zweite Packung |
| | `features/meals/meal_plan_repository_test.dart` (Koch-Blöcke) | Teilverteilung erlaubt, zu viel abgelehnt; Koch-Termin anlegen/verschieben/löschen/Rückgängig; Reservieren, Rest und Abgelehntes auf die Einkaufsliste ohne Doppel; Gekocht gibt frei; Löschen/Rückgängig mit Reservierungen |
| | `features/meals/meal_plan_screens_test.dart` | Beispiel: 9 Portionen, So 17:00, 3/1/4 verteilt, 1 frei, Linsen reserviert, Tomaten abgelehnt, zweites Kochen bekommt nur den Linsen-Rest; Hinweis „noch nicht eingeplant“ → Verteilen; Kochen übernimmt die Reservierung |
| Diktieren | `core/dictation_overlay_test.dart` | Knopf nur bei fokussiertem, beschreibbarem Feld (nicht Passwort/schreibgeschützt); Einfügen an der Cursorposition mit Leerzeichen und Satzanfang; `onChanged`; Platz über der Tastatur; nicht verfügbar / nichts verstanden → Hinweis; ganzes To-Do per Stimme |
| Journal | `features/journal/journal_repository_test.dart` | Ein Eintrag pro Tag, leere Antworten, kaputtes JSON, Umdatieren auf belegten Tag, Suche, Löschen/Wiederherstellen, Stimmungsreihe, tägliche Erinnerung (an/aus, nach Abmelden neu), Export und Kontolöschung |
| | `features/journal/journal_screens_test.dart` | Schreiben mit Stimmung/Leitfrage/Text, erneut öffnen = bearbeiten, leerer Eintrag abgelehnt, Löschen mit Rückgängig (Liste und Editor), Warnung bei belegtem Tag, Erinnerung einstellen, Planen-Unterbereich, Heute-Karte und „Alle“, Suche, Diktat im Journal |
| | `core/database_migration_test.dart` (v27 → v28) | Journal-Tabelle mit Sync-Zeitstempel |
| Navigation | `app/home_shell_test.dart` | 6 Tabs auf 360 dp bei 130 % Schrift, alle Beschriftungen sichtbar, je Tab genau ein Seitenkopf; Tab merkt sich den Bereich, erneuter Tipp → erster Bereich; Planen hat 4 Bereiche; Mehr öffnet jede Seite mit ihrem Hinzufügen-Knopf |
| | `app/tab_style_test.dart` | Jede Tab-Farbe einmalig, Icon auf Pille und Kopf-Icon ≥ 3 : 1 in hell und dunkel |
| | `features/dashboard/home_screen_test.dart` (`daily use`) | Reihenfolge der Heute-Abschnitte; „Als Nächstes“ ohne Termine ausgeblendet |
| Sicherungen | `core/database_backup_test.dart` | Update sichert vorher und behält jede Zeile jeder Tabelle (Rezepte!), Neuinstallation ohne Sicherung, fehlgeschlagenes Update → Daten unverändert + `DatabaseUpgradeException`, ältere App öffnet neuere DB unverändert, nur 5 Sicherungen, Wiederherstellen mit Sicherung des aktuellen Stands (rückgängig machbar), fremde/kaputte/neuere Dateien abgelehnt |
| | `features/finance/backups_screen_test.dart` | Jetzt sichern → ändern → wiederherstellen → Anmeldung, alter Stand zurück; Hinweis-Screen bei fehlgeschlagenem Update mit „Erneut versuchen“ |
| Gerichte | `features/fitness/nutrition_test.dart` (`dishes`) | Eigenes Gericht je Portion, 1,5 Portionen = 1350 kcal, in der Suche wieder; Gramm je Portion → Werte pro 100 g; Rezept-Portionen ohne Lebensmittel, Portionen ändern rechnet um; `isDish` überlebt DB/Export |
| | `features/fitness/nutrition_screen_test.dart` (`dishes`, `photo`) | Eigenes Gericht anlegen und später über die Suche in Portionen; Rezept mit 2 Portionen; Foto-Gericht als Gericht gemerkt, 0,75 Portionen = 300 g |
| Essen ohne Kochen | `features/meals/meal_plan_screens_test.dart` (`without cooking`) | Gericht mit 2 Portionen eingeplant – kein Koch-Block, keine Einkaufsliste, kein Termin |
| Einkauf ohne Doppelungen | `features/meals/meal_plan_repository_test.dart` (`batches`) | Nach dem Abhaken erneut speichern → nichts doppelt; doppelte Menge → nur Differenz; Vorrat aus → keine Reservierung; beides aus → nichts auf der Liste; Rezept-Zutaten zweimal → einmal; von Hand geänderte Menge bleibt |
| | `features/meals/meal_plan_screens_test.dart` | Beide Schalter aus im Planer; Bearbeiten mit „Speichern“ lässt die Liste unverändert |
| Einkaufsliste | `features/lists/lists_test.dart` (`same food, grouped`) | `shoppingKey` (Plural, Klammern, Groß/klein), Zwiebel + Zwiebeln addiert, alte Doppelungen beim Laden zusammengeführt, Gruppen über Einheiten und nach Abteilung, Haltbares vor Gemüse |
| | `features/lists/lists_screens_test.dart` | Abteilungen als Überschriften, „2× + 200 g“ als eine Zeile, gemeinsam abgehakt |
| | `core/database_migration_test.dart` (v30 → v31) | `foods.isDish`, `meal_entries.portions`, Schalter je Koch-Block (Standard an) |
| Einkauf ↔ Kassenzettel | `features/lists/lists_screens_test.dart` | Abhaken fragt immer (eigene Menge, Packungen, „Wie geplant“ je Gruppenmenge) und legt direkt in den Vorrat; Barcode-Scan → Packungsgröße von Open Food Facts, Barcode im Vorrat; Rückgängig; Hinweis „noch kein Kassenzettel“ und „Ohne Bon“ |
| | `features/receipts/receipt_matcher_test.dart` | Abgleich (Kürzel, Mengenabweichung, kg ↔ g, gleiches Lebensmittel vor ähnlichem Namen, Stück ↔ g nicht vergleichbar); Barcode/Herkunft/Rückgängig im Repository; `boughtFor` nach dem Verschieben; nur der Bon-Tag wird geladen, Verknüpfen statt doppelt, Preis und Bon-Menge; Bon zu vorhandener Buchung ohne Doppelbuchung; Tag ohne Bon abschließen und zurück; Hinweis nur am Einkaufstag und am Tag danach |
| | `features/receipts/receipt_screens_test.dart` | Prüfansicht zeigt den Abgleich mit dem Einkauf des Tages (passt / Menge / nicht auf dem Bon), verknüpft statt doppelt, Vortag bleibt offen; Bon an einem Tag ohne Einkauf vergleicht nichts; Bon aus dem Buchungs-Editor ergänzt die Buchung, Hinweis verschwindet |
| Handy-Kalender | `features/calendar/calendar_sync_test.dart` | Wiederholung → RRULE, ganztägig/Dauer, mehrtägige Handy-Termine an jedem Tag; Anlegen/Ändern/Löschen/Wiederherstellen gespiegelt (gleicher Termin, nicht doppelt), Ausschalten räumt auf; kaputter Handy-Kalender blockiert das Speichern nicht; ohne Berechtigung kein Schreiben; nur gewählte Kalender, nie „LifeHub“ selbst; Kalender zeigt Handy-Termine farbig und gemischt nach Uhrzeit, nur lesend; „Als Nächstes“ mischt beide; Profil-Karte (Auswahl, Schreiben, Hinweis ohne Berechtigung) |
| | `core/database_migration_test.dart` (v32 → v33) | `device_calendar_links` ohne Sync-Spalten |
| | `core/database_migration_test.dart` (v31 → v32) | `inventory_items.fromShopping`/`receiptTxId`, `shopping_items.barcode`; alte Vorratsartikel gelten nicht als Einkauf |
| Lebensmittel im Plan | `features/meals/meal_plan_repository_test.dart` (`single food`) | Lebensmittel planen, essen → Protokoll + Vorrat 500 → 440 g, Rückgängig |
| | `features/meals/meal_plan_screens_test.dart` (`single food`) | „+“ → Lebensmittel → Foto der Nährwerttabelle → 60 g eingeplant → gegessen im Ernährungsprotokoll |
| Lernen | `features/learning/spaced_repetition_test.dart` | Alle vier Bewertungen, 1 → 3 → Abstand × Leichtigkeit, Untergrenze 1,3, über die Zeitumstellung, Knopf-Beschriftung, Import-Zeilen mit allen Trennern |
| | `features/learning/learning_repository_test.dart` | Eindeutige Stapelnamen, Zähler fällig/gesamt, Reihenfolge (fällige vor neuen), „Nochmal“ nach 10 Min, Suche, Bearbeiten, Löschen/Rückgängig von Karte und Stapel samt Karten |
| | `features/learning/learning_screens_test.dart` | Stapel anlegen, importieren, lernen (Gut, Nochmal kommt wieder, Leicht) → „Fertig für heute“, Zähler 0; Heute-Karte nur mit fälligen Karten |
| Kontakte | `features/contacts/relative_date_test.dart` | heute/morgen/übermorgen (nicht „morgens“), Wochentage, „nächste Woche Mittwoch“ vorn/mittig/hinten, auch ohne Umlaute, in N Tagen/Wochen, Datum mit/ohne Jahr, 31.2., Jahreswechsel |
| | `features/contacts/contact_repository_test.dart` | Initialen, nächster Geburtstag/Alter/29.2.; Geburtstagstermin anlegen, verschieben, entfernen, mit Kontakt löschen/wiederherstellen; Erinnerungen am Tag und zum Nachfragen, erledigt/zurück, vergangen = keine, nach Anmeldung neu, mit Notiz/Kontakt gelöscht und zurück; Notiz-Reihenfolge; Heute-Abfragen; Suche |
| | `features/contacts/contact_screens_test.dart` | Kontakt anlegen, Schnellnotiz „nächste Woche Mittwoch …“ mit Nachfragen → Erinnerungen; Datum wegklicken; Heute „Menschen“ abhaken und Geburtstag öffnen, ohne Inhalt ausgeblendet; Geschenkliste nur einmal angelegt; globale Suche über eine Notiz |
| | `app/layout_test.dart` (`learning`, `contacts`) | Stapel, Stapel-Seite, Lernrunde, Kontaktliste, voller Kontakt mit Notizen und Heute „Menschen“ auf 360 dp/130 %, hell und dunkel |
| | `core/database_migration_test.dart` (v29 → v30) | Neue Spalten im Essensplan, Karteikarten- und Kontakt-Tabellen |
| Formulare | `features/editors_test.dart` | To-Do-, Habit- und Termin-Editor speichern; Sparziel: 0 € abgelehnt, Komma-Betrag, Konto verknüpfen, Löschen mit Rückgängig, kaputte Farbe; „Sichern & Synchronisieren“ (Restore noch nicht verfügbar, IP fehlt) |
| Qualität | `core/dates_test.dart` | Kalendertage über die Zeitumstellung (25.10./29.03.), Wochenanfang |
| | `core/restore_test.dart` | Rückgängig stellt genau das Gelöschte her: Habit-Einträge (nicht die vorher abgewählten), Geschenkideen, Termin-Erinnerung |
| | `core/reminders_test.dart` | Nach dem Abmelden plant das Anmelden To-Do- und Vorrats-Erinnerungen neu |
| | `core/picker_widgets_test.dart` | `RepeatPicker` (Abstand, Wochentage, mindestens ein Tag), `HubTabs` (nur der gewählte Bereich wird gebaut) |
| | `app/theme_mode_test.dart`, `app/layout_test.dart` (dark) | Theme speichern/laden; Hauptscreens und Editoren im dunklen Modus |
| | `features/finance/repositories/…` (`names and safe deletes`) | Doppelte Konto-/Kategorienamen, Konto mit Buchungen, tolerantes Lesen alter Werte, Serie bearbeiten bucht Fälliges vorher |
| | `features/finance/services/local_sync_service_test.dart` | Delta enthält Einfügungen vom Sync-Tag, Sitzungen je Nutzer, UTC-Zeitstempel |
| | `features/receipts/receipt_import_service_test.dart` | Fehler mitten im Speichern → weder Buchung noch Vorrat |
| | `features/receipts/receipt_screens_test.dart` (`receipt photos`) | Foto über relativen Pfad angezeigt und so gespeichert; Editor zeigt Hinweis, wenn die Datei fehlt; entferntes Foto wird gelöscht, außer eine andere Buchung oder ein abgebrochener Editor nutzt es noch; Prüfung abgebrochen → Foto gelöscht |
| | `features/receipts/receipt_parser_test.dart` (ML Kit) | Am Komma getrennte Preise und Daten („0, 89“, „05.10,26“) wie auf dem Emulator erkannt |
| | `core/database_migration_test.dart` (v26 → v27) | Absolute Belegpfade werden relativ, fremde Dateien bleiben |
| | `features/finance/screens/…` | Ladefehler mit „Erneut versuchen“, Konto-/Kategorie-/Fixkosten-Editor, Rückgängig bei Buchung (Kontostand), Konto, Kategorie, Fixkosten; gleichnamige Einnahme-/Ausgabekategorien getrennt; „unbegrenzt“ |
| | `features/dashboard/home_screen_test.dart` | Heute leer und voll befüllt bei 360 dp/130 % (Sprung in die richtigen Tabs), To-Do antippen öffnet, Kästchen hakt ab |
| | `features/meals/meal_plan_screens_test.dart` | Wochenpfeile und Verteil-Screen um die Zeitumstellung, Umverteilen mit gegessener Portion und Faktorwechsel, Kochen ohne Vorrat, eigenes Rezept löschen mit Rückgängig |

## Techniken

- **Echte Datenbank statt Mocks**: `createTestDatabase()` legt pro Test eine frische SQLite-Datei
  (sqflite_common_ffi) mit dem echten Schema an.
- **Screens mit echten Providern**: `testApp(db, screen)` baut den Screen mit `appProviders(db)`.
- **Externe Dienste gefakt**: `fakeOpenFoodFacts({...})` (HTTP-Client) und `FakeBarcodeScanner('…')` statt Kamera.
- **Asynchrone DB in Widget-Tests** (`test/helpers/test_app.dart`):
  - `seedDb` – Testdaten anlegen, danach Verbindung schließen
  - `pumpUntil` – warten, bis etwas angezeigt wird (achtung: `find.text` findet auch Eingabefelder)
  - `pumpUntilGone` – warten, bis Dialog/Formular geschlossen ist
  - `pumpUntilTrue` – warten, bis eine DB-Abfrage stimmt
  - `readDb` – nach dem Start des Screens aus der DB lesen. **Nicht** `tester.runAsync` für mehrere Abfragen nacheinander: sqflites Sperre läuft im Test-Takt, die zweite Abfrage hängt sonst
  - **Kein `pumpAndSettle`** bei Screens mit Ladeanzeige oder DB-Zugriff – stattdessen `pumpUntil`/`pumpUntilGone`
  - Dialoge mit Textfeldern: Controller im Dialog-State besitzen, nicht direkt nach `showDialog` disposen (die Ausblend-Animation nutzt ihn noch)
  - **Nie feste Wartezeiten vor einer Prüfung** – unter Last (viele Tests parallel) sind sie zu kurz
  - `disposeApp` – Screen abbauen, laufende DB-Ketten (Laden → Seeding → neu Laden) über Probe-Abfragen auslaufen lassen, dann DB schließen (sonst hängt der Test oder wirft „database closed“). Speichert der Screen im Hintergrund (z. B. Abhaken), vorher per `readDb` warten, bis der Wert in der DB steht – sonst bleibt unter Last ein sqflite-Timer übrig
  - `swipeDelete` – Eintrag wischen, „Löschen“, auf „Rückgängig“ warten
- **Fehler erst als Test**: Jeder gefundene Fehler bekommt zuerst einen Test, der ihn zeigt (rot), dann den Fix (grün).
- **Diktieren**: `testApp(..., dictation: FakeDictation(words: …))` liefert sofort ein Ergebnis; der Knopf hat den Key `DictationOverlay.micKey`.
- **Zeit**: Tests mit Datumsgrenzen setzen feste Tage (`clock:`/`now:`-Parameter), z. B. die Zeitumstellung am 25.10.2026.
- **Benachrichtigungen**: `RecordingNotifications` (in `test_app.dart`) merkt sich geplante Erinnerungen; `testApp(..., notifications: …, dark: true)`.
- **Formulare**: `launcher(page)` öffnet eine Seite per Navigator, damit `pop` wie in der App funktioniert;
  `enterInCard` und `selectDropdown` bedienen Formularkarten.
- **Schriften**: Tests nutzen ein Theme ohne Google Fonts (kein Netzwerk).

## Neues Feature – Checkliste

1. Repository-/Logik-Tests unter `test/features/<feature>/`
2. Mindestens ein Widget-Test pro Screen (Anzeigen + wichtigste Aktion)
3. Wenn ein Model neue Spalten schreibt: in `core/database_schema_test.dart` aufnehmen
4. `tool/check` lokal grün, dann pushen (der pre-push-Hook prüft es ohnehin)
