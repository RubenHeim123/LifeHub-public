/// Hilfen für Zahlen aus der Texterkennung.
library;

/// ML Kit trennt Wörter am Komma: „0, 89“ → „0,89“, „7 , 0 g“ → „7,0 g“. Mehrfache Leerzeichen
/// werden zu einem. [decimals] sind die erlaubten Nachkommastellen (Bon: genau 2, Nährwerte: 1–2).
String joinSplitDecimals(String line, {String decimals = '2'}) => line
    .replaceAll(RegExp(r'\s+'), ' ')
    .replaceAllMapped(RegExp('(\\d) ?([.,]) (\\d{$decimals})(?!\\d)'), (m) => '${m[1]}${m[2]}${m[3]}')
    .trim();
