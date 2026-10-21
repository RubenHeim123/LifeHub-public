import 'package:frontend/core/database/database.dart';
import 'package:frontend/core/models/app_exceptions.dart';
import 'package:frontend/features/learning/models/flash_card.dart';

/// Karteikarten: Stapel, Karten, fällige Karten und Bewertung beim Lernen.
class LearningRepository {
  LearningRepository({DatabaseService? db}) : _db = db ?? DatabaseService.instance;
  final DatabaseService _db;

  // ─── Stapel ───────────────────────────────────────────────────────────

  /// Alle Stapel A–Z mit Anzahl der Karten und der jetzt fälligen.
  Future<List<Deck>> getDecks(int uid, {DateTime? now}) async {
    final db = await _db.database;
    final at = (now ?? DateTime.now()).toIso8601String();
    final rows = await db.rawQuery('''
        SELECT d.*,
          (SELECT COUNT(*) FROM flash_cards c WHERE c.deckId = d.id AND c.is_deleted = 0) AS cardCount,
          (SELECT COUNT(*) FROM flash_cards c WHERE c.deckId = d.id AND c.is_deleted = 0 AND (c.due IS NULL OR c.due <= ?)) AS dueCount
        FROM flash_decks d WHERE d.userid = ? AND d.is_deleted = 0 ORDER BY d.name COLLATE NOCASE''', [at, uid]);
    return rows.map(Deck.fromMap).toList();
  }

  Future<int> saveDeck(Deck deck) async {
    final db = await _db.database;
    if (deck.name.trim().isEmpty) throw const UserFacingException('Bitte gib dem Stapel einen Namen.');
    final dup = await db.query('flash_decks',
        columns: ['id'],
        where: 'userid = ? AND is_deleted = 0 AND LOWER(TRIM(name)) = ? AND id != ?',
        whereArgs: [deck.userid, deck.name.trim().toLowerCase(), deck.id ?? -1]);
    if (dup.isNotEmpty) throw UserFacingException('Einen Stapel „${deck.name.trim()}“ gibt es schon.');
    final data = {...deck.toMap()..remove('id'), 'last_changed': syncStamp()};
    if (deck.id == null) return db.insert('flash_decks', data);
    await db.update('flash_decks', data, where: 'id = ?', whereArgs: [deck.id]);
    return deck.id!;
  }

  /// Löscht den Stapel samt Karten. Liefert den Zeitstempel für „Rückgängig“.
  Future<String> deleteDeck(int id) async {
    final db = await _db.database;
    final at = syncStamp();
    await db.transaction((txn) async {
      await txn.update('flash_decks', {'is_deleted': 1, 'last_changed': at}, where: 'id = ?', whereArgs: [id]);
      await txn.update('flash_cards', {'is_deleted': 1, 'last_changed': at}, where: 'deckId = ? AND is_deleted = 0', whereArgs: [id]);
    });
    return at;
  }

  Future<void> restoreDeck(int id, String at) async {
    final db = await _db.database;
    await db.transaction((txn) async {
      await txn.update('flash_decks', {'is_deleted': 0}, where: 'id = ?', whereArgs: [id]);
      await txn.update('flash_cards', {'is_deleted': 0}, where: 'deckId = ? AND is_deleted = 1 AND last_changed = ?', whereArgs: [id, at]);
    });
  }

  // ─── Karten ───────────────────────────────────────────────────────────

  Future<List<FlashCard>> getCards(int deckId, {String search = ''}) async {
    final db = await _db.database;
    final q = search.trim().toLowerCase();
    final rows = await db.query('flash_cards',
        where: 'deckId = ? AND is_deleted = 0${q.isEmpty ? '' : ' AND (LOWER(front) LIKE ? OR LOWER(back) LIKE ?)'}',
        whereArgs: [deckId, if (q.isNotEmpty) ...['%$q%', '%$q%']],
        orderBy: 'id');
    return rows.map(FlashCard.fromMap).toList();
  }

  Future<int> saveCard(FlashCard card) async {
    if (card.front.trim().isEmpty || card.back.trim().isEmpty) {
      throw const UserFacingException('Bitte Vorder- und Rückseite ausfüllen.');
    }
    final db = await _db.database;
    final data = {...card.toMap()..remove('id'), 'last_changed': syncStamp()};
    if (card.id == null) return db.insert('flash_cards', data);
    await db.update('flash_cards', data, where: 'id = ?', whereArgs: [card.id]);
    return card.id!;
  }

  /// Viele Karten auf einmal („Vorderseite – Rückseite“ je Zeile). Liefert die Anzahl.
  Future<int> importCards(int uid, int deckId, String text) async {
    final pairs = parseCardLines(text);
    final db = await _db.database;
    await db.transaction((txn) async {
      for (final (front, back) in pairs) {
        await txn.insert('flash_cards', FlashCard(userid: uid, deckId: deckId, front: front, back: back).toMap());
      }
    });
    return pairs.length;
  }

  Future<void> deleteCard(int id) async {
    final db = await _db.database;
    await db.update('flash_cards', {'is_deleted': 1, 'last_changed': syncStamp()}, where: 'id = ?', whereArgs: [id]);
  }

  Future<void> restoreCard(int id) => _db.restoreRow('flash_cards', id);

  // ─── Lernen ───────────────────────────────────────────────────────────

  /// Jetzt fällige Karten (neue zuletzt, sonst die am längsten fälligen zuerst), optional nur eines Stapels.
  Future<List<FlashCard>> dueCards(int uid, {int? deckId, DateTime? now}) async {
    final db = await _db.database;
    final at = (now ?? DateTime.now()).toIso8601String();
    final rows = await db.rawQuery('''
        SELECT c.* FROM flash_cards c JOIN flash_decks d ON d.id = c.deckId AND d.is_deleted = 0
        WHERE c.userid = ? AND c.is_deleted = 0 AND (c.due IS NULL OR c.due <= ?)${deckId == null ? '' : ' AND c.deckId = ?'}
        ORDER BY c.due IS NULL, c.due, c.id''', [uid, at, if (deckId != null) deckId]);
    return rows.map(FlashCard.fromMap).toList();
  }

  Future<int> dueCount(int uid, {DateTime? now}) async => (await dueCards(uid, now: now)).length;

  /// Bewertung speichern; liefert die Karte mit neuem Termin.
  Future<FlashCard> review(FlashCard card, Rating rating, {DateTime? now}) async {
    final next = scheduleNext(card, rating, now ?? DateTime.now());
    await saveCard(next);
    return next;
  }
}
