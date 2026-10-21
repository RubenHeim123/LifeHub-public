/// Inhalt der Vision-Board-Vorlage („Vorlage laden“): neutrale Beispiele zum Anpassen.
/// Vorlage: (Bereich, Farbe, Bild-Asset oder `null`, [(Ziel, Zusatz)]).
const visionBoardTemplate = <(String, int, String?, List<(String, String?)>)>[
  ('Gesundheit & Fitness', 0xFFF2AF48, null, [
    ('Halbmarathon laufen', '21,1 km'),
    ('Jede Woche dreimal trainieren', null),
    ('Sieben bis acht Stunden Schlaf', null),
  ]),
  ('Finanzen', 0xFF5ED99E, null, [
    ('Notgroschen aufbauen', '3 Monatsausgaben'),
    ('Sparrate automatisieren', null),
    ('Alle Fixkosten einmal im Jahr prüfen', null),
  ]),
  ('Lernen & Beruf', 0xFF6C8EBF, null, [
    ('Eine neue Sprache lernen', 'Niveau B1'),
    ('Zwölf Bücher im Jahr lesen', null),
    ('Einen Online-Kurs abschließen', null),
  ]),
  ('Freunde & Familie', 0xFFBDADFF, null, [
    ('Jede Woche Zeit mit Freunden', null),
    ('Familie regelmäßig anrufen', null),
    ('Ein Ehrenamt ausprobieren', null),
  ]),
];
