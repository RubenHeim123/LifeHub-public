import 'package:frontend/features/finance/models/account.dart';
import 'package:frontend/features/finance/models/category.dart';
import 'package:frontend/features/finance/models/transaction.dart';
import 'package:frontend/features/finance/models/transaction_type.dart';
import 'package:frontend/features/fitness/models/nutrition.dart';
import 'package:frontend/features/lists/models/lists.dart';
import 'package:frontend/features/receipts/models/receipt.dart';

/// Händlerart → Stichwörter, die in passenden Kategorienamen vorkommen (Reihenfolge = Vorrang).
const _storeKinds = <List<String>, List<String>>{
  ['aldi', 'lidl', 'rewe', 'edeka', 'netto', 'penny', 'kaufland', 'norma', 'tegut', 'globus', 'alnatura', 'denn', 'markt', 'hofladen', 'bäcker', 'metzger']:
      ['lebensmittel', 'supermarkt', 'einkauf', 'essen', 'nahrung'],
  ['dm', 'rossmann', 'müller', 'drogerie']: ['drogerie', 'haushaltsmittel', 'haushalt', 'pflege', 'hygiene'],
  ['apotheke']: ['gesundheit', 'apotheke', 'medizin'],
  ['aral', 'shell', 'esso', 'jet', 'tankstelle', 'total']: ['tanken', 'kraftstoff', 'benzin', 'auto'],
  ['mcdonald', 'burger king', 'restaurant', 'café', 'cafe', 'pizzeria', 'imbiss']: ['restaurant', 'essen gehen', 'gastronomie', 'freizeit'],
  ['h&m', 'zara', 'c&a', 'primark', 'deichmann', 'tk maxx']: ['kleidung', 'mode', 'schuhe'],
  ['ikea', 'obi', 'bauhaus', 'hornbach', 'toom']: ['haus', 'wohnen', 'haushalt', 'baumarkt'],
  ['decathlon', 'intersport']: ['sport'],
};

/// Kategorien, die für Kassenzettel nie vorgeschlagen werden.
const _neverSuggest = {'überweisung', 'anpassung', 'investition'};

/// Ergebnis der Auswertung eines Kassenzettels – Vorschläge für die Prüfansicht.
class ReceiptSuggestion {
  /// Passende Ausgabenkategorien, beste zuerst (die erste wird eingetragen).
  final List<String> categories;
  final String? account;

  /// Je Position: zugeordnetes Lebensmittel (oder `null`) und ob sie in den Vorrat gehört.
  final List<(Food?, bool)> items;
  const ReceiptSuggestion({required this.categories, this.account, required this.items});
}

class ReceiptAnalyzer {
  const ReceiptAnalyzer();

  ReceiptSuggestion analyze({
    required ParsedReceipt receipt,
    required List<Category> categories,
    required List<Account> accounts,
    required List<Transaction> history,
    required List<Food> foods,
  }) {
    final matches = [for (final item in receipt.items) matchFood(item.name, foods)];
    final grocery = _isKind(receipt.store, 0);
    final pantry = [
      for (final (i, item) in receipt.items.indexed)
        !item.isNonGoods &&
            (matches[i] != null ||
                (grocery &&
                    const {ShoppingCategory.food, ShoppingCategory.drinks}.contains(ShoppingCategory.guess(item.displayName)))),
    ];
    final foodShare = receipt.items.isEmpty ? 0.0 : pantry.where((p) => p).length / receipt.items.length;
    return ReceiptSuggestion(
      categories: suggestCategories(
        store: receipt.store,
        mostlyFood: foodShare >= 0.5,
        categories: categories,
        history: history,
      ),
      account: suggestAccount(receipt.payment, accounts, history),
      items: [for (var i = 0; i < receipt.items.length; i++) (matches[i], pantry[i])],
    );
  }

  static bool _isKind(String? store, int kindIndex) {
    final s = (store ?? '').toLowerCase();
    if (s.isEmpty) return false;
    return _storeKinds.keys.elementAt(kindIndex).any((k) => RegExp('(^|\\W)${RegExp.escape(k)}').hasMatch(s));
  }

  /// Kategorien nach Passung: 1. früher für diesen Händler gewählt, 2. Händlerart, 3. Lebensmittel.
  List<String> suggestCategories({
    String? store,
    bool mostlyFood = false,
    required List<Category> categories,
    required List<Transaction> history,
  }) {
    final candidates = [
      for (final c in categories)
        if (c.transactionType == TransactionType.expense && !_neverSuggest.contains(c.categoryName.toLowerCase())) c.categoryName,
    ];
    final scores = <String, double>{for (final c in candidates) c: 0};

    // Gelernt: welche Kategorie hatten frühere Buchungen bei diesem Händler?
    final storeKey = (store ?? '').toLowerCase().split(RegExp(r'\s')).first;
    if (storeKey.length >= 2) {
      for (final t in history) {
        if (t.transactionType != TransactionType.expense || !scores.containsKey(t.category)) continue;
        if (t.description.toLowerCase().contains(storeKey)) scores[t.category] = scores[t.category]! + 10;
      }
    }
    // Händlerart → Stichwörter im Kategorienamen
    void boost(List<String> words, double weight) {
      for (final (rank, w) in words.indexed) {
        for (final c in candidates) {
          if (c.toLowerCase().contains(w)) scores[c] = scores[c]! + weight - rank * 0.5;
        }
      }
    }

    for (var k = 0; k < _storeKinds.length; k++) {
      if (_isKind(store, k)) boost(_storeKinds.values.elementAt(k), 6);
    }
    if (mostlyFood) boost(_storeKinds.values.first, 3);

    final ranked = candidates.where((c) => scores[c]! > 0).toList()..sort((a, b) => scores[b]!.compareTo(scores[a]!));
    final fallback = candidates.firstWhere((c) => c.toLowerCase() == 'allgemein', orElse: () => candidates.isEmpty ? '' : candidates.first);
    return [...ranked, if (fallback.isNotEmpty && !ranked.contains(fallback)) fallback];
  }

  /// Konto: Karte → Girokonto/Kreditkarte, bar → Bargeld; sonst das zuletzt genutzte Ausgabenkonto.
  String? suggestAccount(ReceiptPayment payment, List<Account> accounts, List<Transaction> history) {
    String? find(List<String> words) => accounts
        .map((a) => a.accountName)
        .where((n) => words.any(n.toLowerCase().contains))
        .firstOrNull;
    final byPayment = switch (payment) {
      ReceiptPayment.card => find(['giro', 'kreditkarte', 'karte', 'bank']),
      ReceiptPayment.cash => find(['bar', 'cash', 'geldbörse', 'portemonnaie']),
      ReceiptPayment.unknown => null,
    };
    if (byPayment != null) return byPayment;
    final recent = [...history.where((t) => t.transactionType == TransactionType.expense)]..sort((a, b) => b.date.compareTo(a.date));
    final last = recent.map((t) => t.account).where((a) => accounts.any((x) => x.accountName == a)).firstOrNull;
    return last ?? (accounts.isEmpty ? null : accounts.first.accountName);
  }

  static List<String> _tokens(String s) => s
      .toLowerCase()
      .replaceAll(RegExp(r'\(.*?\)'), ' ')
      .replaceAll(RegExp(r'\d+([.,]\d+)?\s*(kg|g|ml|l)\b'), ' ')
      .replaceAll(RegExp(r'[^a-zäöüß ]'), ' ')
      .split(' ')
      .where((t) => t.length >= 3)
      .toList();

  static const _filler = {'bio', 'natur', 'frisch', 'gut', 'stk', 'pck'};

  /// Wie gut passt der (oft abgekürzte) Bon-Text zu [name]? 0 = gar nicht, ab 1,5 ein Treffer.
  static double nameScore(String receiptName, String name) {
    final tokens = _tokens(receiptName)..removeWhere(_filler.contains);
    final ft = _tokens(name);
    if (tokens.isEmpty || ft.isEmpty) return 0;
    var score = 0.0;
    for (final t in tokens) {
      if (ft.contains(t)) {
        score += 2;
      } else if (ft.any((x) => x.startsWith(t) || (t.length >= 5 && t.startsWith(x)))) {
        score += 1.5;
      }
    }
    // Der erste Begriff eines Lebensmittels ist meist das Wichtigste („Rote Linsen“ → linsen reicht nicht allein)
    if (score > 0 && tokens.any((t) => ft.first.startsWith(t) || t.startsWith(ft.first))) score += 0.5;
    return score;
  }

  /// Lebensmittel zum (oft abgekürzten) Bon-Text: „HAFERFL. 500G“ → „Haferflocken“.
  Food? matchFood(String receiptName, List<Food> foods) {
    Food? best;
    var bestScore = 0.0;
    for (final f in foods) {
      final score = nameScore(receiptName, f.name);
      if (score > bestScore || (score == bestScore && best != null && score > 0 && f.name.length < best.name.length)) {
        best = f;
        bestScore = score;
      }
    }
    return bestScore >= 1.5 ? best : null;
  }
}
