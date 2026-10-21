import 'package:flutter_test/flutter_test.dart';

import 'package:frontend/core/database/database.dart';
import 'package:frontend/core/models/app_exceptions.dart';
import 'package:frontend/features/learning/models/flash_card.dart';
import 'package:frontend/features/learning/repositories/learning_repository.dart';

import '../../helpers/test_app.dart';

void main() {
  late DatabaseService db;
  late LearningRepository repo;
  late int uid;
  final now = DateTime(2026, 10, 20, 18);

  setUp(() async {
    db = createTestDatabase();
    repo = LearningRepository(db: db);
    uid = (await createTestUser(db)).uid;
  });
  tearDown(() => db.close());

  test('decks: unique names, counts of cards and due cards', () async {
    final id = await repo.saveDeck(Deck(userid: uid, name: 'Spanisch'));
    await expectLater(repo.saveDeck(Deck(userid: uid, name: ' spanisch ')), throwsA(isA<UserFacingException>()));
    expect(await repo.importCards(uid, id, 'el perro – der Hund\nla casa – das Haus\nel gato – die Katze'), 3);

    var deck = (await repo.getDecks(uid, now: now)).single;
    expect((deck.name, deck.cardCount, deck.dueCount), ('Spanisch', 3, 3));

    final first = (await repo.dueCards(uid, now: now)).first;
    await repo.review(first, Rating.good, now: now);
    deck = (await repo.getDecks(uid, now: now)).single;
    expect(deck.dueCount, 2); // morgen wieder dran
    expect((await repo.getDecks(uid, now: DateTime(2026, 10, 21, 8))).single.dueCount, 3);
  });

  test('due order: overdue reviews first, new cards after; "again" comes back in 10 minutes', () async {
    final id = await repo.saveDeck(Deck(userid: uid, name: 'Erdkunde'));
    await repo.importCards(uid, id, 'Hauptstadt Frankreich – Paris\nHauptstadt Spanien – Madrid');
    var due = await repo.dueCards(uid, now: now);
    final again = await repo.review(due.first, Rating.again, now: now);
    expect(await repo.dueCount(uid, now: now), 1);
    due = await repo.dueCards(uid, now: now.add(const Duration(minutes: 11)));
    expect(due.first.id, again.id); // fällige Wiederholung vor neuer Karte
  });

  test('cards: search, edit, delete with restore; deleting a deck takes its cards along, undo brings them back', () async {
    final id = await repo.saveDeck(Deck(userid: uid, name: 'Bio'));
    await repo.importCards(uid, id, 'Mitochondrium – Kraftwerk der Zelle\nRibosom – Proteinsynthese');
    final card = (await repo.getCards(id, search: 'kraftwerk')).single;
    await repo.saveCard(card.copyWith(back: 'Kraftwerk der Zelle (ATP)'));
    expect((await repo.getCards(id, search: 'atp')).single.id, card.id);
    await expectLater(repo.saveCard(card.copyWith(back: '  ')), throwsA(isA<UserFacingException>()));

    await repo.deleteCard(card.id!);
    expect(await repo.getCards(id), hasLength(1));
    await repo.restoreCard(card.id!);
    expect(await repo.getCards(id), hasLength(2));

    final at = await repo.deleteDeck(id);
    expect(await repo.getDecks(uid), isEmpty);
    expect(await repo.dueCards(uid, now: now), isEmpty);
    await repo.restoreDeck(id, at);
    expect((await repo.getDecks(uid, now: now)).single.cardCount, 2);
  });
}
