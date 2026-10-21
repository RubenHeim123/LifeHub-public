import 'package:frontend/core/models/decimals.dart';
import 'package:frontend/features/receipts/models/receipt.dart';

/// Bekannte Händler (Kleinschreibung) → Anzeigename.
const knownStores = <String, String>{
  'aldi süd': 'ALDI SÜD',
  'aldi sud': 'ALDI SÜD',
  'aldi nord': 'ALDI Nord',
  'aldi': 'ALDI',
  'lidl': 'Lidl',
  'rewe': 'REWE',
  'edeka': 'EDEKA',
  'netto': 'Netto',
  'penny': 'PENNY',
  'kaufland': 'Kaufland',
  'norma': 'NORMA',
  'tegut': 'tegut',
  'globus': 'Globus',
  'alnatura': 'Alnatura',
  'denns': 'denn’s Biomarkt',
  'dm-drogerie': 'dm',
  'dm drogerie': 'dm',
  'rossmann': 'Rossmann',
  'müller': 'Müller',
  'apotheke': 'Apotheke',
  'aral': 'Aral',
  'shell': 'Shell',
  'esso': 'Esso',
  'jet ': 'JET',
  'ikea': 'IKEA',
  'h&m': 'H&M',
  'decathlon': 'Decathlon',
  'mcdonald': 'McDonald’s',
  'burger king': 'Burger King',
  'bäckerei': 'Bäckerei',
};

/// Liest einen Kassenzettel aus den erkannten Textzeilen (oben nach unten, je Zeile links → rechts).
/// Erkennt Händler, Datum, Summe, Zahlart und die Positionen mit Stückzahl bzw. Gewicht.
class ReceiptParser {
  const ReceiptParser();

  static final _price = RegExp(r'(-?\d{1,4}[.,]\d{2})\s*(?:€|EUR)?\s*(?:[A-D]|[*])?\s*$', caseSensitive: false);
  static final _count = RegExp(r'^\s*(\d{1,3})\s*(?:stk\.?|st\.?)?\s*[x×*]\s*(\d{1,4}[.,]\d{2})', caseSensitive: false);
  static final _weight = RegExp(r'^\s*(\d{1,3}[.,]\d{1,3})\s*kg\s*[x×*]\s*(\d{1,4}[.,]\d{2})', caseSensitive: false);
  // Komma als Trenner: die Texterkennung liest „05.10.26“ gern als „05.10,26“.
  static final _date = RegExp(r'\b(\d{1,2})[./,-](\d{1,2})[./,-](\d{2,4})\b');
  static final _time = RegExp(r'\b(\d{1,2}):(\d{2})(?::\d{2})?\b');

  static const _totalWords = ['zu zahlen', 'summe', 'gesamt', 'total', 'betrag'];
  static const _endWords = [
    'zu zahlen', 'summe', 'gesamt', 'total', 'zwischensumme', 'mwst', 'steuer', 'netto ', 'brutto',
    'gegeben', 'rückgeld', 'rueckgeld', 'girocard', 'kartenzahlung', 'ec-karte', 'bar ',
  ];
  static const _skipWords = ['eur', 'preis', 'artikel', 'menge', 'uid', 'ust-id', 'steuer-nr', 'tel', 'www', 'filiale', 'kasse'];

  static double _num(String s) => double.parse(s.replaceAll(',', '.'));

  /// Kopfzeilen vor den Positionen: Händlername, Adresse, Telefon, Firmenform.
  static bool _isHeader(String line, int index) {
    final l = line.toLowerCase();
    return index == 0 ||
        RegExp(r'\d{5}').hasMatch(line) ||
        RegExp(r'str(\.|aße|asse)|platz|gmbh|kg|ag|ohg|e\.k\.|telefon|tel').hasMatch(l) ||
        _skipWords.any(l.startsWith);
  }

  /// [now] nur für Tests.
  ParsedReceipt parse(List<String> rawLines, {DateTime? now}) {
    // ML Kit trennt Wörter am Komma: „0, 89“ → „0,89“.
    final lines = [for (final l in rawLines) joinSplitDecimals(l)]..removeWhere((l) => l.isEmpty);
    final lower = [for (final l in lines) l.toLowerCase()];

    // ─── Händler ────────────────────────────────────────────────────────
    String? store;
    for (final l in lower.take(8)) {
      for (final e in knownStores.entries) {
        if ('$l '.startsWith(e.key)) {
          store = e.value;
          break;
        }
      }
      if (store != null) break;
    }
    store ??= lines.take(4).where((l) => RegExp(r'[A-Za-zÄÖÜäöü]{3,}').hasMatch(l) && !_price.hasMatch(l)).firstOrNull;

    // ─── Datum ──────────────────────────────────────────────────────────
    DateTime? date;
    for (var i = lines.length - 1; i >= 0 && date == null; i--) {
      for (final m in _date.allMatches(lines[i])) {
        final d = int.parse(m.group(1)!), mo = int.parse(m.group(2)!);
        var y = int.parse(m.group(3)!);
        if (y < 100) y += 2000;
        if (mo < 1 || mo > 12 || d < 1 || y < 2000 || d > DateTime(y, mo + 1, 0).day) continue;
        // Fehlerkennung in der Zukunft (z. B. „12.03.52“) verwerfen
        if (DateTime(y, mo, d).isAfter((now ?? DateTime.now()).add(const Duration(days: 1)))) continue;
        final t = _time.firstMatch(lines[i]);
        date = DateTime(y, mo, d, t == null ? 0 : int.parse(t.group(1)!), t == null ? 0 : int.parse(t.group(2)!));
        break;
      }
    }

    // ─── Summe und Zahlart ──────────────────────────────────────────────
    double? total;
    for (var i = 0; i < lines.length; i++) {
      final l = lower[i];
      if (!_totalWords.any(l.contains) || l.contains('zwischensumme') || l.contains('mwst')) continue;
      var m = _price.firstMatch(lines[i]);
      // Betrag steht manchmal in der nächsten Zeile
      if (m == null && i + 1 < lines.length) m = _price.firstMatch(lines[i + 1]);
      if (m != null) {
        total = _num(m.group(1)!);
        break;
      }
    }
    final all = lower.join(' ');
    final payment = RegExp(r'girocard|kartenzahlung|ec-karte|ec karte|visa|mastercard|kontaktlos|maestro|debit').hasMatch(all)
        ? ReceiptPayment.card
        : RegExp(r'\bbar\b|gegeben|rückgeld|rueckgeld').hasMatch(all)
            ? ReceiptPayment.cash
            : ReceiptPayment.unknown;

    // ─── Positionen ─────────────────────────────────────────────────────
    final items = <ReceiptItem>[];
    String? pendingName; // Name in einer Zeile, Preis in der nächsten
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      final l = lower[i];
      if (_endWords.any((w) => l.startsWith(w) || l.contains(' $w'))) {
        if (items.isNotEmpty) break; // Ende der Positionen
        continue;
      }
      final weight = _weight.firstMatch(line);
      if (weight != null && items.isNotEmpty) {
        items.last = items.last.copyWith(weightKg: _num(weight.group(1)!));
        continue;
      }
      final count = _count.firstMatch(line);
      if (count != null && !RegExp(r'[A-Za-zÄÖÜäöü]{3,}').hasMatch(line.substring(count.end))) {
        // „2 x 0,89“ unter der Position (oder mit dem Gesamtpreis dahinter)
        final n = int.parse(count.group(1)!);
        if (pendingName != null) {
          final unit = _num(count.group(2)!);
          final p = _price.firstMatch(line.substring(count.end));
          items.add(ReceiptItem(name: pendingName, price: p == null ? n * unit : _num(p.group(1)!), count: n));
          pendingName = null;
        } else if (items.isNotEmpty) {
          items.last = items.last.copyWith(count: n);
        }
        continue;
      }
      final price = _price.firstMatch(line);
      if (price == null) {
        // Reine Textzeile: möglicher Artikelname (Kopfzeilen und Adressen vor der ersten Position ignorieren)
        final letters = RegExp(r'[A-Za-zÄÖÜäöü]{3,}').hasMatch(line);
        final header = items.isEmpty && _isHeader(line, i);
        pendingName = letters && !header ? line : null;
        continue;
      }
      var name = line.substring(0, price.start).trim();
      if (name.isEmpty || !RegExp(r'[A-Za-zÄÖÜäöü]{2,}').hasMatch(name)) {
        if (pendingName == null) continue;
        name = pendingName;
      }
      pendingName = null;
      if (items.isEmpty && _isHeader(name, i)) continue;
      // „2 x 0,89“ in derselben Zeile wie der Name: „BANANEN 2 x 0,89 1,78“
      final inline = RegExp(r'\s(\d{1,3})\s*[x×]\s*\d{1,4}[.,]\d{2}\s*$').firstMatch(name);
      var n = 1;
      if (inline != null) {
        n = int.parse(inline.group(1)!);
        name = name.substring(0, inline.start).trim();
      }
      items.add(ReceiptItem(name: name, price: _num(price.group(1)!), count: n));
    }

    return ParsedReceipt(store: store, date: date, total: total, payment: payment, items: items, lines: lines);
  }
}
