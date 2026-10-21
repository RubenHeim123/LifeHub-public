# LifeHub

Eine All-in-One-App für den Alltag: Finanzen, To-dos, Termine, Habits, Ziele, Training, Ernährung, Essensplan, Einkauf, Vorrat und Kleiderschrank – in einer Flutter-App. Alle Daten bleiben lokal auf dem Gerät (SQLite). Es gibt kein Konto bei einem Anbieter und keine Cloud-Pflicht.

![Flutter](https://img.shields.io/badge/Flutter-3.29-02569B?logo=flutter) ![Plattform](https://img.shields.io/badge/Plattform-Android-3DDC84?logo=android) ![Tests](https://img.shields.io/badge/Tests-540%2B-success)

---

## Funktionen

**Heute** – ein Tagesüberblick: Habits, Essen, Training, To-dos (auch überfällige), nächste Termine (aus LifeHub und dem Handy-Kalender), Kontakte mit Geburtstagen, fällige Lernkarten, ablaufender Vorrat, Journal, Ziele und Monatsbilanz.

**Geld**
- Konten, Kategorien mit Monatsbudget, Buchungen mit Belegfoto, Umbuchungen, Fixkosten (verpasste Termine werden nachgebucht), Sparziele, Diagramme
- Monatsplanung: Fixeinnahmen − Fixausgaben − Budgets = frei verfügbar, mit Warnung
- Prognose des Kontostands zum Monatsende
- Bank-CSV-Import mit automatischer Kategorisierung, Export als JSON/CSV
- **Kassenzettel fotografieren:** Texterkennung auf dem Gerät (ML Kit, offline) liest Händler, Datum, Summe, Zahlart und Positionen; Konto und Kategorie werden vorgeschlagen. Der Bon wird mit dem Einkauf **desselben Tages** abgeglichen: Abgehaktes wird verknüpft statt doppelt angelegt, abweichende Mengen lassen sich übernehmen.

**Planen**
- To-dos und Termine mit Wiederholungen (täglich, wöchentlich an Wochentagen, alle N Wochen, monatlich, jährlich), Erinnerungen, ganztägige Einträge und Geburtstage
- **Handy-Kalender in beide Richtungen:** Termine aus Google, Samsung & Co. erscheinen in LifeHub, LifeHub-Termine landen in einem eigenen Handy-Kalender „LifeHub“ – direkt über den System-Kalender, ohne Internet und Anmeldung
- Habits mit Streaks und XP, Journal mit Stimmung und Leitfragen, Karteikarten mit Wiederholungsplan, Kontakte mit Notizen („nächste Woche Mittwoch …“ wird erkannt), Geschenklisten
- Vision Board: Bereiche, Ziele und Schritt-für-Schritt-Pläne, verknüpft mit To-dos und Terminen

**Essen**
- Ernährungsprotokoll mit kcal und Makros, Trinken, Barcode-Scan (Open Food Facts), Nährwerttabelle per Foto (offline), Gerichte in Portionen, optional KI-Schätzung per Foto mit eigenem API-Schlüssel
- Essensplan mit Rezepten (rund 20 mitgeliefert, eigene möglich), Kochen planen mit Portionen-Verteilung, Vorrat-Reservierung und Termin
- Einkaufsliste: gleiche Lebensmittel zusammengefasst, nach Abteilungen sortiert. Beim Abhaken fragt die App, was gekauft wurde (Packung, eigene Menge oder Barcode), und legt es direkt in den Vorrat
- Vorrat mit Ablaufdatum und Erinnerung

**Training** – Übungskatalog mit über 100 animierten Übungen, eigene Übungen und Workouts, Beispielprogramme, Timer je Trainingsform (Stufenintervall, Intervallsatz, Supersatz, Zirkel, Hochintensität), Protokoll mit Bestwerten.

**Mehr** – Kleiderschrank, Outfits, Wunschliste (Kauf bucht in den Finanzen), Sicherungen und Wiederherstellen, Diktieren in jedem Eingabefeld, Fingerabdruck-Login, heller und dunkler Modus.

---

## Datenschutz und Sicherheit

- Alle Daten liegen in einer lokalen SQLite-Datenbank auf dem Gerät. Vor jedem Datenbank-Update wird automatisch gesichert.
- Passwörter werden mit PBKDF2 und Salt pro Nutzer gespeichert.
- Optionale Online-Dienste: Open Food Facts (Barcode-Nährwerte) und die KI-Schätzung per Foto (Anthropic). Den API-Schlüssel dafür trägt jede Person selbst in der App ein; er liegt nur im sicheren Speicher des Geräts.
- Das Repository enthält keine Schlüssel oder privaten Daten. `tool/secret_scan.dart` prüft das bei jedem Release-Check (vor jedem Push und in der CI).

---

## Technik

| Bereich | Umsetzung |
|---|---|
| Framework | Flutter 3.29 (Dart), Material 3 mit eigenem Design-System |
| Daten | SQLite über `sqflite`, Migrationen mit Sicherung vorher |
| Architektur | Feature-Ordner, Repositories, Dependency Injection mit `provider` |
| Kamera & Erkennung | `mobile_scanner` (Barcodes), `google_mlkit_text_recognition` (Kassenzettel, Nährwerttabellen) |
| Kalender | eigener MethodChannel auf Androids `CalendarContract` |
| Benachrichtigungen | `flutter_local_notifications` |
| Diagramme | `fl_chart` |

### Projektstruktur

```
lib/
  app/        App-Hülle, Tab-Navigation, Theme
  core/       Datenbank, Dependency Injection, Services, gemeinsame UI
  features/   je Bereich models/, repositories/, services/, screens/, widgets/
              (finance, calendar, todos, habits, journal, learning, contacts,
               vision, fitness, meals, lists, inventory, receipts, style, …)
test/         spiegelt lib/ – Logik-, Datenbank- und Widget-Tests
tool/         Release-Check, Git-Hook, Schlüssel-Prüfung, App-Icon
```

Regeln: Screens greifen nur über Repositories auf die Datenbank zu; neue Repositories und Services werden in `lib/core/di/app_providers.dart` registriert; Kontostände ändern sich nur im selben Datenbank-Block wie die Buchung.

---

## Loslegen

```sh
git clone <URL dieses Repos>
cd LifeHub
flutter pub get
git config core.hooksPath tool/hooks   # Release-Check vor jedem Push
flutter run
```

Voraussetzung: Flutter 3.29 und ein Android-Gerät oder Emulator.

## Tests und Release-Check

| Befehl | Zweck |
|---|---|
| `flutter test` | alle Tests |
| `sh tool/check.sh` bzw. `powershell -File tool/check.ps1` | **Release-Check:** Schlüssel-Prüfung, Analyse (`--fatal-infos`) und alle Tests |
| `sh tool/check.sh --coverage` | zusätzlich Coverage nach `coverage/lcov.info` |

Der Release-Check läuft automatisch vor jedem `git push` (Hook in `tool/hooks/`) und in GitHub Actions bei jedem Push. Hilfen für eigene Tests stehen in `test/helpers/test_app.dart`, der Testplan in [`test/test_plan.md`](test/test_plan.md), die technische Beschreibung in [`technical_specification.md`](technical_specification.md).
