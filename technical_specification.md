# Technische Dokumentation - LifeHub 2.0

Diese Zusammenfassung dient als technischer Blueprint für LifeHub 2.0, eine ganzheitliche Life-Management-App für Finanzen, Aufgaben, Termine, Habits, langfristige Ziele (Vision Board), Journal, Fitness (Training, Ernährung, Essensplan, Vorrat) und Style (Kleiderschrank, Outfits, Wunschliste). Stand: 11.10.2026.

## 1. System-Architektur & Tech-Stack
- **Framework**: Flutter (Dart) - Cross-Platform UI.
- **Datenhaltung**: SQLite (`sqflite`), Schema-Version 33 mit Change-Tracking (`last_changed` immer UTC, siehe J.) und Soft-Deletes. `DatabaseService` verwaltet nur Verbindung und Schema; fachlicher Zugriff läuft über Repositories je Feature.
- **Architektur**: Feature-Ordner (`lib/features/<feature>/{models,repositories,services,screens,widgets}`), App-Hülle in `lib/app/`, Gemeinsames in `lib/core/`.
- **Dependency Injection & Zustand**: `provider` stellt alle Repositories/Services bereit (`lib/core/di/app_providers.dart`); UI-Zustand in `StatefulWidgets`, ThemeMode per `ValueNotifier`.
- **Synchronisation**: Session-basiertes Delta-Sync-Protokoll zur Minimierung des Datenverbrauchs nach der Initial-Synchronisation.
- **Design-System**: `AppTheme` mit Design-Tokens (`AppColors`) für Light/Dark Mode, gemeinsame Widgets in `lib/core/ui/`.

---

## 2. Kern-Module & Features

### A. Finanz-Management (Finance)
- **Konten & Kategorien**: Dynamische Verwaltung von Konten (Icons/Farben) und Kategorien (Einnahme/Ausgabe-Typ + Monatsbudget).
- **Transaktionen**: Erfassung von Einnahmen/Ausgaben mit optionalem Bild-Anhänge (File Picker) und automatischer Budget-Prüfung.
- **Wiederkehrende Zahlungen**: `FixedTransactions` mit `RecurrenceInterval` (täglich bis jährlich). Fällige Termine werden beim App-Start gebucht – auch mehrere verpasste, ohne Doppelbuchung; Termine bleiben am Startdatum verankert (Monatsende).
- **Umbuchungen**: Transfers zwischen eigenen Konten als Ausgabe + Einnahme in einer DB-Transaktion; zählen nicht als Umsatz.
- **Bilanz-Dashboard**: Echtzeit-Berechnung des Monats-Saldos und der Gesamtersparnisse.

### B. Dashboard & Prognosen
- **PredictionService**: Fortgeschrittener Algorithmus zur End-of-Month Vorhersage.
  - *Formel*: Aktueller Saldo + Verbleibende Fix-Einnahmen - Verbleibende Fix-Ausgaben + (Variable Einnahmen Avg * Tage) - (Variable Ausgaben Avg * Tage).
  - *Zeitraum*: Die variablen Durchschnitte werden über die **letzten 365 Tage** berechnet.
  - *Logik*: Fixbuchungen werden strikt aus der historischen Durchschnittsberechnung exkludiert.
  - *Visualisierung*: Detaillierte Aufschlüsselung mit dynamischen Tipps basierend auf dem Vergleich zwischen Prognose und aktuellem Saldo.
- **Life-Overview**: Zusammenfassende Ansicht von Finanzen, Habits und Terminen.

### C. Zeit- & Aufgaben-Management (Todos & Calendar)
- **To-Do-System**: Status-Tracking (Offen/Erledigt), Fälligkeitsdaten und Priorisierung.
- **Kalender**: Integration von Terminen (`Appointment`) mit Zeitangaben und Verknüpfung zu Kategorien. `appointments.reminderMinutes` (v20, `null` = keine; bestehende Termine behalten 30 min, neue 15 min) steuert die Erinnerung, die `AppointmentRepository` beim Anlegen/Ändern neu plant. `allDay` und `repeatYearly` (v21): ganztägige Einträge enden am Tagesende und erinnern um 9 Uhr (am Tag, Vortag, 1 Woche vorher); jährliche Einträge werden per `occurrencesBetween`/`nextOccurrence` in jedem Jahr ab dem ersten angezeigt (29.2. → 28.2.), `yearsAt` liefert das Alter. Es wird immer nur die nächste Erinnerung geplant; `refreshReminders` plant beim App-Start nach.

### D. Habit-Tracking
- **Geplante Wochentage**: Jedes Habit hat eigene Wochentage; Streaks zählen nur geplante Tage.
- **Gamification**: XP pro Erledigung (einmalig pro Tag, Zurücknehmen zieht sie wieder ab), Level-System.

### E. Vision Board & Ziele
- **Bereiche → Ziele → Schritte**: Tabellen `vision_areas`, `vision_goals`, `goal_steps`. Bereiche haben ein Bild (im App-Ordner `vision_images/`, relativ gespeichert).
- **Schritt-für-Schritt-Plan**: Schritte werden der Reihe nach freigeschaltet; ein Schritt ist erst abschließbar, wenn alle verknüpften To-Dos erledigt sind.
- **Verknüpfung**: `todos.goalStepId` und `appointments.goalStepId` verweisen auf einen Schritt. Wird ein Ziel gelöscht, bleiben To-Dos/Termine erhalten und verlieren nur die Zuordnung.
- **Vorlage**: 6 Bereiche und 18 Ziele inkl. Bilder (`assets/vision_template/`).

### F. Inventar (Vorrat & Kleiderschrank)
- **Tabelle `inventory_items`** mit `kind` (food/drink/clothing/other), Kategorie, Ort, Menge/Einheit, Marke, Barcode, Kauf-/Ablauf-/Öffnungsdatum, Zustand, Foto (`inventory_images/`), Größe, Farbe, Saison, zuletzt benutzt/getragen, Tragezähler, Preis.
- **Ein Screen für beides** (`InventoryScreen(kinds: …)`): Suche, Status-Chips mit Zählern (läuft bald ab ≤ 3 Tage, abgelaufen, lange nicht getragen ≥ 90 Tage), Filter Kategorie/Ort/Zustand, Sortierung, Liste/Raster, Wischen für −1/getragen und Löschen, Schnell-Hinzufügen.
- **Erinnerung**: Notification um 9 Uhr am Vortag des Ablaufs (eigener ID-Bereich `inventoryIdOffset`).

### F0. Navigation (`lib/app/`)
- 6 Tabs nach Nutzung (`AppTab`): Heute · Planen (`PlanSection`: To-Dos, Habits, Termine, Journal) · Essen (`FoodSection`: Ernährung, Essensplan, Einkauf, Vorrat) · Training · Geld (`FinanceHubScreen`) · Mehr (`MoreSection`: Lernen, Kontakte, Geschenke, Kleiderschrank, Outfits, Wunschliste – öffnen sich als eigene Seite über `openMoreSection`).
- Bereiche sind Enums; die Hubs bauen ihre Chips aus `Section.values`, sodass Reihenfolge und Sprungziele nicht auseinanderlaufen. `TabNavigator(tab, [section])` für Sprünge von Heute.
- Die Shell merkt sich je Tab den zuletzt gewählten Bereich (`HubTabs.onChanged`); ein Tipp auf den aktiven Tab führt zum ersten Bereich.
- Leiste: 6 gleich breite Knöpfe mit Icon und Beschriftung (`FittedBox`, passt auf 360 dp bei 130 %). `TabStyle` (`lib/app/tab_style.dart`) hält Beschriftung, Icons und je Tab eine Farbe (Pastell im dunklen, tief im hellen Modus, Kontrast ≥ 3 : 1 getestet) für die aktive Pille und das Icon im Seitenkopf.
- Jede Tab-Seite hat genau einen Kopf: `TabTitle` (über `HubTabs(title:)` bzw. `TabPage`) oder bei Finanzen `ScreenHeader` in derselben Größe. Bereichsseiten beginnen mit `SummaryRow` („2 offen“).
- Heute ordnet die Abschnitte nach täglicher Nutzung (Habits, Essen, Training, To-Dos, Termine, Menschen, Lernen, Läuft ab, Journal, Vision, Finanzen); leere optionale Abschnitte entfallen.

### F2. Einheitliche Bedienung (`lib/core/ui/app_actions.dart`)
- Abstände: `pagePadding(context)` (20 dp seitlich, unten Navigation/Systemleiste + Platz für den `AppFab`) für Listen, `detailPadding(context)` für Detail- und Formularseiten. Farben ausschließlich über `AppColors`; Karten haben im dunklen Modus eine feine Kontur.
- `AppFab` ist der eine Hinzufügen-Button; die Startseite reicht die echte Höhe der schwebenden Navigation per `NavBarInset` weiter (Flutter entfernt beim FAB eines inneren Scaffolds den unteren Abstand), Listen nutzen `navClearance(context)`.
- `SwipeTile` (Wischen links: Bearbeiten/Löschen, rechts: Zusatzaktion) und `deleteWithUndo` (sofort löschen, 5 s „Rückgängig“). Repositories haben dazu `restore…`-Methoden; was ein Löschen nebenbei ändert, wird beim Wiederherstellen zurückgedreht (Kontostand bei Buchungen, Ziele/Schritte und To-Do-Verknüpfungen beim Vision Board über `VisionDeletion`, Einkaufsherkünfte über Zeitstempel).
- Editoren liefern beim Löschen `kDeletedResult`; die Liste löscht dann mit Rückgängig. `runGuarded` zeigt Fehler als Snackbar. `EditorSheet`/`showEditorSheet` für kurze Formulare mit allen Feldern.
- `Repeat` (`lib/core/models/repeat.dart`): täglich, wöchentlich an Wochentagen, alle N …, monatlich (Monatsende), jährlich (29.2. → 28.2.); genutzt von To-Dos (`todos.repeat/repeatStart/seriesId`, v23 – Abhaken legt das nächste Vorkommen einmalig an) und Terminen (`appointments.repeat`, v23 aus `repeatYearly` migriert).
- `test/app/layout_test.dart` rendert jeden Screen bei 360 × 780 dp, 130 % Schrift und 48 px Systemleiste und scrollt ihn durch – die Hauptscreens und Editoren zusätzlich im dunklen Modus.
- Alle Editoren nutzen dieselben Bausteine (`FormFieldCard`, `FormActions` mit „Hinzufügen“ bzw. „Speichern“, „Abbrechen“, „Löschen“ → `kDeletedResult`) und `ModernAppBar`; das gilt jetzt auch für Termin, Habit, Sparziel und Rezept. Speichern läuft über `runGuarded`, Busy-Flags werden auch nach Fehlern zurückgesetzt.
- `EmptyState` (Icon, Titel, Hinweis, optional Knopf) für leere Listen und Ladefehler; Finanzlisten zeigen „Laden fehlgeschlagen“ mit „Erneut versuchen“. Fehlermeldungen laufen über `errorText()` (kein „Exception: …“). Texte duzen, „E-Mail“ statt „Email“.
- Kalendertage: `lib/core/models/dates.dart` (`addDays`, `daysBetween`, `weekStart`) statt `add(Duration(days: n))` – an der Zeitumstellung (23/25 Stunden) verrutschten sonst Essensplan-Wochen und Verteil-Tage.

### F2b. Diktieren in allen Eingabefeldern (`lib/core/ui/dictation_overlay.dart`)
- `DictationOverlay` liegt einmal in `MaterialApp.builder` und folgt dem fokussierten Feld (`FocusManager` → `EditableTextState`). Für jedes Feld außer Passwort- und schreibgeschützten erscheint links über der Tastatur ein Mikrofon-Knopf; einzelne Felder müssen nicht angepasst werden.
- Solange der Knopf sichtbar ist, meldet der Overlay der App eine um `barHeight` (64 dp) größere Tastatur – Inhalte, aktives Feld und schwebende Knöpfe rücken darüber.
- `DictationService` (Paket `speech_to_text`, Deutsch, `RECORD_AUDIO`) fragt beim ersten Mal nach dem Mikrofon; Zwischentext erscheint in einer Pille, das Ergebnis wird über `userUpdateTextEditingValue` an der Cursorposition eingefügt (wie getippt: Formatter, `onChanged`, Validierung). Satzanfänge werden groß geschrieben, Leerzeichen ergänzt. Ohne Erkennung/Berechtigung bzw. wenn nichts verstanden wurde, gibt es einen Hinweis. In Tests ersetzt `FakeDictation` den Dienst.
- Die Erkennung des Geräts gibt nach ca. 2,5 s Stille auf (auf dem Handy gemessen, `NO_SPEECH_DETECTED`). Solange noch nichts erkannt wurde, startet `DictationService` sie bis zu 10 s neu; späte Ende-Meldungen der vorigen Aufnahme werden über `SpeechEngine.isListening` erkannt. Ohne Tastatur sitzt der Knopf über der System-Navigationsleiste; für Screenreader ist er ein eigener Knoten (vorher lag „Diktieren“ auf dem ganzen Bildschirm).
- `HubTabs` baut alle Bereichs-Chips und scrollt den aktiven ins Bild (Sprung von Heute zum Journal zeigte vorher keinen aktiven Chip).

### F9. Kontakte (`lib/features/contacts/`)
- Unterbereich „Kontakte“ unter Mehr (`MoreSection.contacts`). `contacts` (Schema 30): Name, Spitzname, Beziehung, Telefon, E-Mail, Adresse, Geburtstag, „Allgemeines“; `contact_notes`: Text, optionales Datum, `followUp`, `done`.
- **Geburtstag:** `ContactRepository.saveContact` legt einen ganztägigen, jährlichen Termin „Geburtstag: <Name>“ mit Erinnerung am Tag an (`contacts.appointmentId`), verschiebt/benennt ihn mit und löscht ihn, wenn der Geburtstag entfernt wird. Löschen/Rückgängig des Kontakts nehmen Termin, Notizen und Erinnerungen mit (gemeinsamer Zeitstempel). Knopf „Geschenkliste“ öffnet die `GiftList` mit gleichem Personennamen oder legt sie zum nächsten Geburtstag an.
- **Schnellnotiz:** `parseRelativeDate(text, now)` (reines Dart) erkennt heute/morgen/übermorgen, Wochentage (der nächste nach heute), „nächste Woche Mittwoch“, „in 3 Tagen/2 Wochen“ und „am 24.10.“ (ohne Jahr der nächste solche Tag, auch über den Jahreswechsel; 31.2. wird verworfen), auch ohne Umlaute getippt („naechste“). Die Angabe wird aus dem Text entfernt („hat nächste Woche Mittwoch einen Arzttermin“ → 28.10., „hat einen Arzttermin“); das erkannte Datum steht als Chip darunter, lässt sich ändern oder wegklicken.
- **Erinnerungen:** 9:00 am Tag („Lena: Arzttermin“), mit „Am Tag danach nachfragen“ zusätzlich am Folgetag („Bei Lena nachfragen“). IDs `NotificationService.contactIdOffset + 2 × Notiz-ID (+1)`. Erledigt/Löschen hebt sie auf, Rückgängig plant neu, `refreshReminders` nach der Anmeldung.
- **Heute:** Abschnitt „Menschen“ (nur mit Inhalt) mit den Notizen des Tages (abhakbar), Nachfragen vom Vortag und Geburtstagen der nächsten 7 Tage. Die globale Suche findet Kontakte über Name, Beziehung, Spitzname und Notizen.

### F8. Lernen – Karteikarten (`lib/features/learning/`)
- Unterbereich „Lernen“ unter Mehr (`MoreSection.learning`). `flash_decks` und `flash_cards` (Schema 30, Termin `due`, `intervalDays`, `ease`, `reps`, `lapses`); neue Karten haben kein `due` und sind sofort dran.
- `scheduleNext` (vereinfachtes SM-2, reine Funktion): Nochmal → in 10 Minuten wieder, Reihe neu, Leichtigkeit −0,2; Schwer → Abstand ×1,2 (mind. 1 Tag), −0,15; Gut → 1, 3, dann Abstand × Leichtigkeit; Leicht → wie Gut ×1,3 (mind. 2 Tage), +0,15. Leichtigkeit ≥ 1,3; Tage zählen als Kalendertage (fällig ab Mitternacht, robust über die Zeitumstellung). Die Knöpfe zeigen den nächsten Abstand („10 Min“, „1 T“, „3 Wo“).
- `DeckScreen`: Karten suchen, anlegen/bearbeiten, Wischen zum Löschen mit Rückgängig, Import vieler Karten je Zeile („Vorderseite – Rückseite“, auch „;“, „=“, Tab). `StudyScreen`: Vorderseite, „Antwort zeigen“, Bewertung; „Nochmal“-Karten kommen in derselben Runde ans Ende; am Ende „Fertig für heute“. Ein Stapel löschen nimmt seine Karten mit (Rückgängig über den Zeitstempel).
- Heute zeigt „Lernen · N Karten fällig“, solange etwas fällig ist.

### F7d. Handy-Kalender in beide Richtungen (Schema 33)
- **Android-Anbindung:** eigener MethodChannel `lifehub/device_calendar` (`android/.../DeviceCalendarChannel.kt`, registriert in `MainActivity`) auf `CalendarContract`, Abfragen auf einem Hintergrund-Thread. Kein Fremdpaket: `device_calendar` ließe sich wegen `timezone 0.10` nur als veraltete 3.9.0 einbinden. Berechtigung über `permission_handler` (`Permission.calendarFullAccess`), Manifest `READ_CALENDAR`/`WRITE_CALENDAR`.
- **Lesen:** `DeviceCalendarService.eventsBetween` liest `Instances` (Serien schon aufgelöst) der gewählten Kalender; `ExternalEvent` wird nie gespeichert, sondern je sichtbarem Monat (Kalender) bzw. 31 Tage (Heute › „Als Nächstes“) live gelesen. Der eigene Kalender „LifeHub“ wird beim Lesen ausgeschlossen. Anzeige nur lesend in der Farbe des Quellkalenders (`ExternalEventCard`, Details im Bottom Sheet), mehrtägige an jedem Tag (`groupExternalByDay`).
- **Schreiben:** `CalendarSync.enableWrite` legt einen lokalen Kalender „LifeHub“ an (`ACCOUNT_TYPE_LOCAL`, Google-Konten bleiben unberührt). `AppointmentRepository` spiegelt nach Anlegen/Ändern/Wiederherstellen (`upsertEvent`, Serien über RRULE + DURATION) und Löschen (`deleteEvent`); Fehler am Handy brechen das Speichern nie ab. Handy-Termine haben keine Erinnerung (sonst doppelt). Die Zuordnung steht in `device_calendar_links` (ohne Sync-Spalten, nicht im Export/Sync – gilt nur auf diesem Gerät). Ausschalten löscht den Kalender und vergisst die Zuordnungen.
- **Einstellungen:** `CalendarSyncCard` im Profil (Anzeigen + Kalenderauswahl, Schreiben), gespeichert je Nutzer in den SharedPreferences (`calendarSync.<uid>.*`).
- **Arbeits-Outlook:** bewusst keine Exchange-/VPN-Anbindung. Erscheint er (mit Freigabe der IT) im Handy-Kalender, zeigt LifeHub ihn automatisch an.

### F7c. Einkauf ↔ Kassenzettel (Schema 32)
- **Abhaken mit Dialog:** Artikel für Vorrat/Kleiderschrank öffnen beim Abhaken immer „Was hast du gekauft?“ (`askBought` → `BoughtResult`): Packungen des Lebensmittels (Zähler, vorbelegt über `packPlan`), selbst eingetragene Menge mit Einheit (optional „als Packungsgröße merken“ → `foods.packSizes`) oder **Barcode** (`BarcodeScanner` + `FoodLookupService.byBarcode`; unbekannt/offline: `linkBarcode` an das zugeordnete Lebensmittel samt Packungsgrößen). „Wie geplant“ übernimmt die geplante Menge. Danach `toggleShopping(bought:, boughtUnit:, barcode:, foodId:)` und sofort `moveToInventory` (übernimmt `barcode`, setzt `inventory_items.fromShopping`); die Snackbar bietet „Rückgängig“ (`undoMoveToInventory`: Vorratsartikel weg, Artikel wie vorher offen). Gruppen fragen je Menge. `boughtFor` zählt auch Gekauftes, das schon im Vorrat bzw. von der Liste geräumt ist.
- **Ein Bon je Einkaufstag:** `InventoryRepository.shoppingTrip(uid, day)` liefert, was am Kalendertag von der Liste in den Vorrat kam und noch keinen Bon hat (`receiptTxId IS NULL`, Verbrauchtes zählt mit). Nur damit vergleicht die Prüfansicht (`ReceiptMatcher.compare`: gleiche `foodId` > gleicher `shoppingKey` > `ReceiptAnalyzer.nameScore`, gierig, jedes Paar einmal; Status passt / Menge weicht ab / nur auf dem Bon, dazu „abgehakt, aber nicht auf dem Bon“). Passende Positionen sind für den Vorrat abgewählt und werden über `ReceiptLink` verknüpft (Preis, auf Wunsch die Bon-Menge); `closesTrip` ordnet danach den ganzen Tag dem Bon zu (`assignTrip`). Alles in einer DB-Transaktion; `createTransaction` liefert dafür die neue ID an `together`.
- **Bon zu einer vorhandenen Buchung:** im Buchungs-Editor „Kassenzettel scannen & abgleichen“ → `scanReceipt(existing:)`; `ReceiptImportService.save` aktualisiert die Buchung (`updateTransaction(together:)`, Kontostand korrigiert) statt eine zweite anzulegen, das alte Foto wird gelöscht, wenn es keine Buchung mehr nutzt.
- **Hinweis „noch kein Kassenzettel“:** `MissingReceiptBanner` (Einkaufsliste, Finanzen › Verwalten, Heute) zeigt Einkaufstage ohne Bon nur am Tag selbst und am Tag danach (`tripsWithoutReceipt`, danach verschwindet er von selbst – ein Bon ist kein Muss; abgeglichen wird trotzdem, wann immer ein Bon eingepflegt wird); Antippen scannt mit dem Tag als Vorgabe, „Ohne Bon“ schließt den Tag ab (`receiptTxId = 0`, mit Rückgängig). Ältere Vorratsartikel (vor v32) gelten nicht als Einkauf.

### F7b. Gerichte, Essen ohne Kochen, Einkauf ohne Doppelungen (Schema 31)
- **Gerichte in der Ernährung:** Chip „Gericht“ im Picker. „Eigenes Gericht“ (Name, kcal je Portion, optional Makros und Gramm je Portion, Portionen) wird als `Food` mit `isDish` gespeichert (`saveDish`, `per100` aus den Portionswerten, ohne Gramm nominell 100 g) und danach in Portionen statt Gramm abgefragt (`askPortions`). „Aus Rezept“ trägt `recipe.perServing × Portionen` über `addDishEntry` ohne `foodId` ein. `meal_entries.portions` lässt das Protokoll „1,5 Portionen“ zeigen; `updateEntry(portions:)` rechnet anteilig um. Das KI-Foto-Gericht wird ebenfalls als Gericht gespeichert (eine Portion = geschätzte Menge).
- **Essensplan „+“:** Kochen planen · Gericht ohne Kochen (Rezept + Portionen über `MealPlanRepository.plan()`, kein Block, Termin, Vorrat oder Einkauf) · Lebensmittel.
- **Keine doppelten Einkäufe:** `saveIngredientPlan` entfernt nur offene Herkünfte des Blocks (`removeFromList(onlyOpen: true)`) und zieht Gekauftes ab (`ListsRepository.boughtFor`) – erneutes Speichern (z. B. nur Uhrzeit) setzt Gekauftes nicht wieder auf die Liste, mehr Portionen bringen nur die Differenz. Beim Bearbeiten ohne geänderte Menge speichert „Speichern“ ohne den Zutaten-Schritt. „Zutaten auf die Einkaufsliste“ im Rezept ersetzt die offenen Mengen dieses Rezepts statt sie zu verdoppeln.
- **Schalter im Zutaten-Schritt:** „Vorrat nutzen“ und „Fehlendes auf die Einkaufsliste“ (`meal_batches.usePantry`/`shop`, beim Bearbeiten erhalten); ohne Einkauf werden auch offene Einträge des Blocks entfernt.
- **Einkaufsliste:** `shoppingKey` (klein, ohne Klammerzusatz, einfache Mehrzahl → Einzahl: Zwiebeln/Zwiebel, Eier/Ei) fasst gleiche Lebensmittel zusammen – beim Hinzufügen und für ältere Doppelungen beim Laden (`_mergeDuplicates`). Die Anzeige gruppiert je Lebensmittel über Einheiten (`groupShopping`, „2× + 200 g Zwiebeln“, gemeinsam abhakbar) und nach `ShoppingAisle` in Laufreihenfolge (Obst & Gemüse, Brot, Kühlregal, Tiefkühl, Vorrat, Getränke, Drogerie, Haushalt, Kleidung, Sonstiges). Haltbares (Dose, Brühe, Mark, Pulver …) geht vor Gemüse-Wörtern. `ShoppingCategory` (Inventar-Ziel) bleibt unverändert.

### F7. Lebensmittel im Essensplan (`lib/features/meals/`)
- Das „+“ je Mahlzeit fragt „Rezept“ oder „Lebensmittel“. „Lebensmittel“ öffnet denselben Picker wie die Ernährung (`showFoodPicker`/`FoodPickerSheet`: Suche, Foto – Nährwerttabelle oder KI –, Barcode, neues Lebensmittel, Vorrat) und plant mit Gramm ein (`meal_plan.foodId`, `grams`, `itemId`, Schema 30).
- „Als gegessen eintragen“ bucht das Lebensmittel ins Ernährungsprotokoll und zieht es, falls aus dem Vorrat gewählt, dort ab; „Gegessen zurücknehmen“ und „Menge ändern“ wie bei Gerichten.

### F6. Mahlzeit per Foto (`lib/features/fitness/services/`)
- Im „+“-Sheet der Ernährung: Chip „Foto“ → Gericht oder Nährwerttabelle, per Kamera oder Galerie (`FoodPhotoScanner`, verkleinert auf 1280 px).
- **Nährwerttabelle (offline):** ML-Kit-Text → `parseNutritionLabel` (kcal bzw. kJ, Fett, Kohlenhydrate, Eiweiß pro 100 g, Portion aus „pro Portion (40 g)“; „davon …“-Zeilen ignoriert; `joinSplitDecimals` repariert „7, 0 g“). Passt die erste kcal-Zahl nicht zu den kJ der 100-g-Spalte (verschmolzene Spalten), wird aus den kJ gerechnet.
- **Gericht (KI):** `MealPhotoAi` schickt das Foto per HTTP an die Anthropic Messages API (`claude-opus-5-5`, Bildblock, `output_config.format` JSON-Schema, `effort: low`, `fallbacks: "default"`) und bekommt Name, geschätzte Menge, Makros und erkannte Bestandteile. Datenschutz: Das Foto verlässt dabei das Gerät; der API-Schlüssel liegt nur im `FlutterSecureStorage` (`AiKeyStore`, Profil → „KI“, vor dem Speichern geprüft), nie in DB oder Export.
- Beide Wege öffnen den Lebensmittel-Editor vorbefüllt (Foto-Vorschau, Hinweis „geschätzt“ bzw. „nicht erkannt: …“); danach Menge (Portion/Schätzung vorgeschlagen) und Eintrag. Probleme erscheinen als Dialog, weil eine Snackbar hinter dem Sheet läge.

### F5. Kochen planen (Meal Prep, `lib/features/meals/`)
- `PortionPlannerScreen`: beliebige Portionenzahl (Zähler plus ×1–×3), Kochtag mit Uhrzeit und Dauer, Verteilung auf Mahlzeiten (mehrere Portionen je Mahlzeit). Nicht verteilte Portionen sind erlaubt – der Essensplan zeigt „<Rezept>: N Portionen noch nicht eingeplant“ mit „Verteilen“.
- Koch-Termin: `planBatch`/`replanBatch` halten einen Termin „Kochen: …“ im Kalender aktuell (`meal_batches.appointmentId`), Löschen/Rückgängig nehmen ihn mit.
- Schritt „Zutaten“: `pantry_check.dart` ordnet Zutaten Vorratsartikeln zu (Namensabgleich wie beim Kochen), rechnet kg/g und l/ml um und zieht ab, was andere Koch-Blöcke reserviert haben (`pantry_reservations`, Schema 29). Vorhandenes wird standardmäßig reserviert, Teilmengen werden aufgefüllt, Abgelehntes und Fehlendes kommt mit dem Block als Herkunft auf die Einkaufsliste (erneutes Speichern ersetzt, nichts doppelt).
- „Gekocht“ übernimmt reservierte Artikel und Mengen, bucht sie ab und gibt die Reservierungen frei.

### F4. Journal (`lib/features/journal/`)
- Unterbereich „Journal“ im Tab Planen (`PlanSection.journal`). Ein Eintrag je Tag (`journal_entries`, Schema 28): Stimmung 1–5 (`Mood`), Antworten auf drei Leitfragen (JSON) und freier Text. Ein zweites Speichern am selben Tag aktualisiert den Eintrag; wird ein Eintrag auf einen Tag mit vorhandenem Eintrag umdatiert, warnt der Editor, dass Speichern ihn ersetzt.
- `JournalScreen`: Heute-Karte, Stimmungsstreifen der letzten 30 Tage, tägliche Erinnerung (Uhrzeit je Nutzer in `SharedPreferences`, `NotificationService.scheduleDaily`, nach der Anmeldung neu geplant), Suche, Einträge nach Monat mit Wischen zum Löschen und Rückgängig. Heute zeigt „Heute schon geschrieben?“, die globale Suche findet Einträge.
- Export, Sync-Trigger und Kontolöschung über `lifestyleTables`.
- `FormActions` stellt auf schmalen Bildschirmen (< 420 dp) Speichern über Abbrechen/Löschen – beim Bearbeiten liefen die drei Knöpfe auf 360 dp mit 130 % Schrift über.

### F3. Kassenzettel (`lib/features/receipts/`)
- `ReceiptScanner`: Foto über `image_picker`, Texterkennung mit ML Kit (lateinische Schrift, offline). Die Wörter werden über ihre Rahmen wieder zu Bon-Zeilen zusammengesetzt (`rowsFromBoxes`: gleiche Höhe → eine Zeile, links nach rechts), das Foto wird über den `ReceiptImageStore` nach `receipt_images/` kopiert und **relativ** (`receipt_images/…`) als `imagePath` an der Buchung gespeichert – wie Vision- und Inventarbilder, damit der Pfad Restore und Gerätewechsel übersteht (Schema 27 hat alte absolute Pfade umgestellt). Auch ein im Buchungs-Editor gewähltes Bild wird dorthin kopiert (Picker-Dateien im Cache kann das System löschen); angezeigt wird über `ReceiptPhoto`, bei fehlender Datei mit Hinweis. Beim Schließen löscht der Editor ersetzte bzw. nach Abbrechen ungenutzte Fotos, sofern keine Buchung (auch keine gelöschte – Rückgängig) sie noch nutzt (`isImageUsed`). Wird die Bon-Prüfung abgebrochen oder kein Text erkannt, löscht `scanReceipt` das neue Foto. Der Parser fügt von der Texterkennung getrennte Preise wieder zusammen („0, 89“ → „0,89“) und liest Daten mit Komma („05.10,26“) – beides auf dem Emulator mit echter ML-Kit-Erkennung gefunden. Im Test per Provider durch einen Fake ersetzt.
- `ReceiptParser` (reines Dart): Händler (bekannte Ketten, sonst erste Textzeile), Datum/Uhrzeit, Summe („Summe“, „Zu zahlen“ …, auch in der Folgezeile), Zahlart, Positionen mit Preis am Zeilenende, Stückzahl („2 x 1,79“), Gewicht („1,230 kg x …“), Name und Preis in getrennten Zeilen, Rabatte/Pfand. Kopfzeilen (Adresse, PLZ, GmbH …) werden übersprungen.
- `ReceiptAnalyzer`: Kategorie-Ranking (frühere Buchungen beim Händler ×10, Händlerart-Stichwörter, Lebensmittelanteil; nie Überweisung/Anpassung/Investition; Rückfall „Allgemein“), Konto (Karte → Giro/Kreditkarte, bar → Bargeld, sonst zuletzt genutzt), Lebensmittel-Zuordnung über (abgekürzte) Wortanfänge, Vorratsvorschlag (keine Nicht-Waren, im Supermarkt Lebensmittel/Getränke).
- `ReceiptReviewScreen` → `ReceiptImportService.save`: eine Ausgabe plus je gewählter Position ein Vorratsartikel (Menge in g/ml/Stück, `foodId`, Preis, Kaufdatum) – in **einer** DB-Transaktion (`createTransaction(..., together:)` + `InventoryRepository.insertItem`), Erinnerungen erst danach. Der Parser verwirft unmögliche (31.02.) und künftige Daten. Gibt es keine Ausgaben-Kategorie, wird beim Speichern „Allgemein“ angelegt.

### G. Fitness
- **Ernährung**: `foods` (Nährwerte pro 100 g), `meal_entries` (Snapshot von Name und Makros), `nutrition_goals`. Barcode: erst eigene Lebensmittel, dann Open Food Facts (`/api/v2/product/{code}.json`), Treffer werden lokal gespeichert. Die Code-Erkennung nutzt das gebündelte ML-Kit-Modell von `mobile_scanner` und funktioniert offline. Ist ein Code unbekannt oder das Netz weg, kann er per `NutritionRepository.linkBarcode` einem vorhandenen Lebensmittel zugeordnet werden (Kopie mit Barcode). Standardprodukte (`catalog/standard_foods.dart`, Marke „Standardprodukt“) legt `ensureStandardFoods` einmalig pro Nutzer an; gelöschte bleiben gelöscht. „Aus Vorrat“ bucht Gramm (g/ml) bzw. Stück ab. Getränke sind eine eigene Mahlzeit (`Meal.drinks`, Menge in ml); Wasser wird per `addWater` ohne Nährwerte eingetragen, `NutritionDay.drankMl` summiert alle Getränke gegen `nutrition_goals.waterMl` (v20).
- **Einkauf** (v24): `shopping_items.amount/unit/foodId/boughtAmount` und `shopping_sources` (Menge je Herkunft: Rezept bzw. Koch-Block, Geschenk, selbst eingetragen). `addToList` addiert gleiche Artikel (Name + Einheit, kg/l → g/ml) und ordnet ein Lebensmittel zu; `foods.packSizes` liefert Packungsgrößen, `packPlan` den Vorschlag (wenig Rest, wenige Packungen), beim Abhaken landet `boughtAmount` im Vorrat. `removeFromList`/`restoreRemoved` nehmen alle Mengen eines Koch-Blocks bzw. Rezepts wieder herunter.
- **Koch-Blöcke** (v25): `meal_batches` (Rezept, Faktor, Kochtag, `cookedAt`), `meal_plan.batchId`, `cook_logs` (Verbrauch je Zutat als JSON: Soll laut Rezept, Vorratsartikel, genommene Menge). `planBatch` erzwingt die vollständige Verteilung der Portionen, `replanBatch` behält Gegessenes, `markCooked` bucht über `InventoryRepository.consume` ab.
- **Essensplan** (`lib/features/meals/`, v22): `meal_plan` (Datum, Mahlzeit, optionale Uhrzeit in Minuten, `recipeKey` für den Katalog oder `recipeId` für eigene Rezepte, Name als Snapshot, Portionen, `mealEntryId`) und `recipes` (eigene Rezepte; Zutaten und Schritte als JSON, Nährwerte pro Portion). Der Katalog (`catalog/recipe_catalog.dart`) ist Code und wird nicht in die DB kopiert. `markEaten` schreibt in einer Transaktion einen `meal_entries`-Eintrag (Makros × Portionen) und merkt sich dessen ID; wird der Eintrag im Ernährungsprotokoll gelöscht, gilt das Gericht beim Lesen (LEFT JOIN) wieder als offen. `addToShopping` fasst gleiche Zutaten (Name + Einheit, Einheiten im Singular) über mehrere Gerichte zusammen, skaliert sie auf die geplanten Portionen und überspringt, was schon offen auf der Einkaufsliste steht.
- **Budgets**: `BudgetPlanService` (Fixeinnahmen/-ausgaben mit `monthlyEquivalent`, Termine im Monat, Budgets mit `planned = max(Budget, Fixkosten der Kategorie)`, frei verfügbar, offen).
- **Training**: `exercises` (eigene Übungen, im Katalog neben den mitgelieferten), `workouts` (+ `repeatWeekdays` als JSON) mit `workout_exercises` (Reihenfolge, Sätze, Vorgabe), `planned_workouts` (Datum, Status geplant/erledigt/übersprungen), `workout_sessions` + `session_sets`. Wöchentliche Wiederholungen werden beim Lesen des Plans virtuell ergänzt und erst beim Starten/Überspringen gespeichert. Fortschritt = Bestwert erledigter Sätze je Einheit.
- **Trainingsformen** (`models/training_method.dart`, `models/method_timer.dart`): `workouts.method` (v18). Je Form eine reine Ablaufsteuerung (`StufenTimer`, `IntervalTimer` für Intervall-/Supersatz, `ZirkelTimer`, `HochTimer`), die per `tick(Duration)` weitergedreht wird und erfasste Werte als `LoggedSet` sammelt; `MethodSessionScreen` taktet sie sekündlich, gibt bei Phasenwechsel Vibration/Ton und speichert über `WorkoutRepository.addSets`. `startNow` startet ein Workout sofort (heute). Einmalige Termine sind explizite `planned_workouts`-Zeilen (`getUpcomingOnce`, `importSampleBlock(once: true)`), Wochenwiederholungen kommen aus `workouts.repeatWeekdays`. Bei Formen mit Timer werden keine Sätze vorbelegt.
- **Übungskatalog** (`lib/features/fitness/catalog/`): ~120 Übungen als Konstanten (`exercise_catalog.dart`), Strichfigur-Animationen aus Schlüsselhaltungen mit `CustomPainter` (`exercise_motion.dart`), 4 Beispielprogramme mit Blöcken, Tagen und Trainingsmethoden (`sample_plans.dart`). `exercises.catalogKey` (v17) verknüpft eigene Übungen mit dem Katalog; `WorkoutRepository.addFromCatalog` / `importSampleBlock` übernehmen Übungen bzw. ganze Blöcke als Workouts.

### H. Style
- **Outfits**: `outfits` + `outfit_items` (Verweis auf Kleidungsstücke). „Heute tragen“ erhöht Tragezähler und Datum bei Outfit und allen Teilen.
- **Wunschliste**: `wishlist_items` (Preis, Link, Bild, Priorität, Status). Kauf: Ausgabe über `TransactionRepository.createTransaction` (Konto/Kategorie wählbar, Standard „Kleidung“) + neues Kleidungsstück; `boughtItemId` verweist darauf. Budget-Anzeige nutzt das Monatsbudget der Kategorie.

### I. Einkauf & Geschenke
- **Einkaufsliste** (`shopping_items`, v19): eine Liste in Eingabereihenfolge; Name, Menge (normalisiert per `parseShoppingInput`/`normalizeQuantity`, z. B. „600 g“, „4×“), intern geschätzte Abteilung (`ShoppingCategory.guess`) als Ziel für die Inventar-Übernahme inkl. Einheit, erledigt/Zeitpunkt. `ListsRepository.moveToInventory` legt Gekauftes als Inventar-Eintrag an (Vorrat, Kleiderschrank, Pflege & Duft).
- **Geschenke** (`gift_lists`, `gift_items`, v19): Liste je Person und Anlass mit optionalem Datum; Ideen mit Preis, Link, Notiz und Status (Idee/Gekauft/Verschenkt). Sortierung: anstehende Anlässe zuerst.
- **Inventar-Arten** erweitert um `accessory` (Accessoires, wird getragen) und `care` (Pflege & Duft, wird verbraucht, mit Ablaufdatum). Der Kleiderschrank zeigt alle drei; beim Hinzufügen wählbar.
- **Hinzufügen-Buttons** in Tab-Seiten nutzen `HubFab` (Abstand zur schwebenden Navigation).

### J. Daten-Administration & Integrität
- **Updates ohne Datenverlust** (`DatabaseService._open`, `lib/core/database/db_backups.dart`): Vor jedem Schema-Update wird `finance.db` nach `db_backups/finance_v<alt>_<Zeit>_update.db` kopiert (die 5 neuesten bleiben). Migrationen fügen nur Spalten/Tabellen hinzu. Scheitert ein Update, wird die Kopie zurückgespielt und `main` zeigt statt der App `UpgradeFailedApp` („Deine Daten sind unverändert“, Erneut versuchen, Fehler kopieren). Eine neuere Datenbank (ältere App installiert) wird mit ihrer eigenen Version unverändert geöffnet, statt dass sqflite das Öffnen verweigert.
- **Sicherungen & Wiederherstellen** (`BackupsScreen`, Profil → Sichern & Synchronisieren): Liste der Sicherungen, „Jetzt sichern“, Teilen als Datei (übersteht so ein Deinstallieren), Wiederherstellen aus der Liste oder einer Datei. `restoreBackup` prüft die Datei (LifeHub-Datenbank, nicht von einer neueren App), sichert vorher den aktuellen Stand („Vor dem Wiederherstellen“), spielt sie ein und führt das nötige Update aus; danach meldet die App ab, damit alle Ansichten neu laden.
- **Eindeutige Namen**: Konten (je Nutzer) und Kategorien (je Nutzer und Typ) dürfen nicht doppelt heißen – Anlegen, Umbenennen und Wiederherstellen prüfen das (`UserFacingException`), weil Buchungen sie über den Namen referenzieren. Ein Konto mit Buchungen lässt sich nicht löschen.
- **Ganz oder gar nicht**: Bon-Import, Wunsch kaufen (`StyleRepository.buy`, zweiter Kauf wird abgelehnt), „Gekocht“ (`markCooked` mit `consumeIn`), CSV-Import (`createTransactions`) und „In Vorrat“ (`moveToInventory`, idempotent) laufen in einer SQL-Transaktion.
- **Fixkosten**: Vor dem Bearbeiten einer Serie werden fällige Termine noch nach den alten Daten gebucht; die Prognose zählt jeden Termin bis Monatsende (wöchentlich 4–5×).
- **Erinnerungen**: Abmelden und Konto löschen entfernen alle geplanten Benachrichtigungen; beim Anmelden planen Termine, To-Dos und Vorrat sie neu (`refreshReminders`).
- **Sync-Zeitstempel**: `syncStamp()` schreibt `last_changed` als UTC mit Millisekunden und „Z“. Trigger (`sync_insert_*`, `sync_update_*`) setzen den Wert bei Einfügungen und rechnen lokale Zeiten um; Schema 26 hat alte Werte vereinheitlicht. Vorher lag `CURRENT_TIMESTAMP` („2026-10-10 08:00:00“) beim Textvergleich vor jedem „…T…“ desselben Tages, sodass der Delta-Sync Einfügungen vom Sync-Tag übersah. Sync-Sitzungen gelten je Nutzer, der Zeitstempel wird vor dem Export genommen.
- **Robustes Lesen**: Unbekannte Werte für Buchungstyp/Intervall fallen auf Ausgabe/monatlich zurück; Heute und Finanzen zeigen bei kaputten Zeilen eine Meldung statt endlos zu laden. Bank-CSV: Latin-1, zweistellige Jahre, unlesbare Beträge/Daten werden übersprungen und gemeldet. Packungsgrößen werden mit „;“ gespeichert („1,5“ ist eine Dezimalzahl).
- **User-Cleanup**: Rekursive Löschlogik auf Repository-Ebene (`deleteUser`), die bei Entfernung eines Benutzers alle verknüpften Objekte (Transaktionen, To-Dos, Termine, Habits) in der Datenbank bereinigt.
- **Datenbank-Management**: Unterstützung für vollständige Resets durch sicheres Löschen der `.db` Datei im App-Dokumentenverzeichnis.

---

## 3. Schnittstellen (Interfaces)

### Interne Schnittstellen (Services)
- **AuthService**: 
  - *Passwort-Hashing*: PBKDF2-HMAC-SHA256 mit zufälligem Salt pro Nutzer (Format `pbkdf2_sha256$<Iterationen>$<Salt>$<Hash>`). Sehr alte Hashes werden beim Login umgestellt; nicht mehr prüfbare Hashes führen zu einer Aufforderung, ein neues Passwort zu setzen. Ist man dabei abgemeldet, nennt die Anmeldung den Grund und „Passwort vergessen?“ setzt ein neues Passwort: bei nicht prüfbarem Alt-Hash direkt, sonst nur nach Bestätigung per Gerätesperre (`local_auth`, PIN/Biometrie). Registrieren mit vorhandener E-Mail wirft `AccountExistsException`.
  - *Biometrie*: Brücke zu `local_auth`. Erfordert `FlutterFragmentActivity` im `MainActivity.kt` sowie `USE_BIOMETRIC`/`USE_FINGERPRINT` Berechtigungen im Manifest.
- **NotificationService**: Wrapper für `flutter_local_notifications`. Plant Termin- und To-Do-Erinnerungen und Budget-Alarme (bei Überschreitung). Getrennte ID-Bereiche je Quelle; veraltete Kanäle werden beim Start entfernt.
- **ExportService**: Verwandelt DB-Inhalte in das Zielformat (String-Buffer für CSV, Map-Transformation für JSON). Unterstützt die Erstellung von **Changesets** für die Delta-Synchronisation.
- **LocalSyncService**: Verwaltet die Peer-to-Peer Synchronisation. Erkennt bestehende Sessions und entscheidet zwischen **Full Sync** und **Delta Sync**.

### Schnittstellen nach Außen (IO & Formate)
1. **Dateisystem**:
   - SQLite-Datenbank (`.db` Datei im App-Dokumentenverzeichnis).
   - Temporäre Datei-Exporte (JSON/CSV) im Cache-Verzeichnis zur Weitergabe per Share-Dialog.
2. **Native iOS/Android APIs**:
   - `Local Auth`: Biometrische Hardware-Abfrage.
   - `Notifications`: System-Ebene Benachrichtigungen.
   - `File Picker`: Zugriff auf Bilder und Speichermedien zum Import/Export.
3. **Daten-Protokolle**:
   - **JSON (Backup)**: Vollständiger Datenbank-Dump inklusive User-Profil (ohne Passwort-Hash), Konten, Transaktionen, To-Dos, Vision Board etc. Wiederherstellen aus dem Backup ist noch nicht umgesetzt.
   - **CSV (Transaktionen)**: Tabellarischer Export für Excel/LibreOffice.
   - **Bank-CSV (Import)**: Schnittstelle zum Einlesen externer Bankdaten mit Mapping-Logik für Kategorien.

---

## 4. Sicherheits-Konzept
- **Passwörter**: nur als PBKDF2-Hash in der Datenbank, nie im Klartext.
- **Secure Storage**: `flutter_secure_storage` (KeyChain/Keystore) enthält nur die Sitzung (E-Mail) und die Fingerabdruck-Einstellung – kein Passwort.
- **Datensatz-Integrität**: Verwendung von `last_changed` (ISO-8601 in UTC) und `is_deleted` (Boolean-Flag) zur konsistenten Replikation über mehrere Geräte hinweg ohne Datenverlust bei Löschungen (**Soft-Delete**).
- **Multi-User**: Daten sind durch `userid` isoliert; auch Kontostände werden nur für Konten des jeweiligen Nutzers geändert.

## 5. Qualitätssicherung
- 541 automatische Tests (Unit, Repository gegen echte Test-DB, Widget-Tests je Screen, Schema- und Migrations-Test), Aufbau spiegelt `lib/`.
- Release-Check `tool/check.ps1` / `tool/check.sh` (Analyse mit `--fatal-infos` + alle Tests), automatisch vor `git push` und in GitHub Actions.

## 6. Deployment & Build-Details
- **Mindestversions-Anforderung**: Android SDK 24 (Android 7.0).
- **Build-Tooling**: Android Gradle Plugin 8.7.0, Gradle 8.10.2, Kotlin 2.1.0, NDK 27.0.12077973, Core Library Desugaring (`desugar_jdk_libs` 2.1.4).
- **Kamera/Barcode**: `mobile_scanner` 6.0.11 (7.x braucht AGP ≥ 8.9.1). Kamera-Berechtigung kommt unter Android über das Plugin-Manifest, unter iOS über `NSCameraUsageDescription` in `Info.plist`.
- **SDK-Anschluss**: `compileSdk` 36 (von mehreren Plugins verlangt, abwärtskompatibel), `targetSdkVersion` aus der Flutter-Vorgabe.

---

## 7. Schnittstellen für externe Services (Integration)

Um eine Verbindung zur LifeHub von einem externen System (z.B. Desktop-Anwendung, Cloud-Server) herzustellen, müssen folgende Schnittstellen implementiert bzw. bedient werden:

### A. Datentransfer-Protokoll (JSON)
Die App nutzt ein zentrales JSON-Format für den vollständigen Datenabgleich. Ein externer Service muss dieses Schema interpretieren oder generieren können:

```json
{
  "sync_type": "full | delta",
  "since": "ISO-8601-Timestamp (nur bei delta)",
  "exportDate": "ISO-8601-Timestamp",
  "accounts": [ 
    { 
      "id": 1, 
      "accountName": "Bank", 
      "last_changed": "...", 
      "is_deleted": 0,
      "server_id": "..." 
    } 
  ],
  "categories": [...],
  "transactions": [...],
  "fixed_transactions": [...],
  "todos": [...],
  "appointments": [...],
  "habits": [...],
  "habit_records": [...],
  "financial_goals": [...],
  "vision_areas": [...],
  "vision_goals": [...],
  "goal_steps": [...]
}
```

### B. Authentifizierungs-Brücke
Externen Systemen wird empfohlen, die in der App hinterlegten Credentials zu nutzen:
1.  **User-ID**: Eindeutiger Primärschlüssel (`uid`) aus der `users`-Tabelle.
2.  **Passwort-Validierung**: Der Export enthält bewusst keinen Passwort-Hash. Ein externer Dienst braucht eine eigene Authentifizierung (z. B. Token-basiert), bevor ein Datenaustausch stattfindet.

### C. Import-Schnittstellen (Mapping)
Für den Import von Bankdaten (Bank-CSV) erwartet die App eine Struktur, die folgende Felder aufweist:
-   **Datum**: (Parsing von `dd.MM.yyyy` oder `yyyy-MM-dd`)
-   **Betrag**: (Dezimalzahl mit Punkt oder Komma)
-   **Verwendungszweck / Empfänger**: (Wird für die automatische Kategorisierung genutzt)

### D. Konzeptionelle API-Endpunkte (für Cloud-Sync)
Falls ein Cloud-Service aufgebaut wird, sollte dieser folgende REST-Resourcen bereitstellen, um mit dem `LocalSyncService` kompatibel zu sein:
-   `POST /sync`: Empfängt das JSON-Paket (Full oder Delta). Der Server sollte den `sync_type` auswerten und die Daten entsprechend persistieren oder loggen.
-   `GET /sync/status`: (Optional) Prüft die Konnektivität und liefert ggf. den Zeitstempel der letzten erfolgreichen Cloud-Synchronisation.
-   `GET /auth/verify`: Prüft die Credentials gegen die DB-Hashes.
