import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:frontend/core/database/database.dart';
import 'package:frontend/features/auth/services/auth.dart';
import 'package:frontend/features/auth/services/password_hasher.dart';
import 'package:frontend/features/auth/models/user.dart';
import 'package:frontend/features/finance/repositories/account_repository.dart';
import 'package:frontend/features/finance/repositories/category_repository.dart';
import 'package:frontend/features/finance/repositories/user_repository.dart';

import '../../helpers/test_app.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('PasswordHasher', () {
    test('hashes with a random salt and verifies', () async {
      final a = await PasswordHasher.hash('geheim123');
      final b = await PasswordHasher.hash('geheim123');

      expect(a, isNot(b), reason: 'jeder Hash bekommt ein eigenes Salt');
      expect(a, isNot(contains('geheim123')));
      expect(await PasswordHasher.verify('geheim123', a), isTrue);
      expect(await PasswordHasher.verify('falsch', a), isFalse);
    });

    test('verifies the very old formats (unsalted SHA-256, plaintext)', () async {
      const pw = 'geheim123';
      final v1 = sha256.convert(utf8.encode(pw)).toString();

      expect(await PasswordHasher.verify(pw, v1), isTrue);
      expect(await PasswordHasher.verify(pw, pw), isTrue);
      expect(await PasswordHasher.verify('falsch', v1), isFalse);
      expect(await PasswordHasher.verify(pw, null), isFalse);
      expect(PasswordHasher.isCurrentFormat(v1), isFalse);
    });
  });

  group('AuthService', () {
    late DatabaseService db;
    late AuthService auth;
    late UserRepository users;

    setUp(() {
      FlutterSecureStorage.setMockInitialValues({});
      db = createTestDatabase();
      users = UserRepository(db: db);
      auth = AuthService(users: users, accounts: AccountRepository(db: db), categories: CategoryRepository(db: db));
    });

    tearDown(() => db.close());

    test('register seeds defaults and stores no password in secure storage', () async {
      final user = await auth.registerWithEmailAndPassword('neu@test.de', 'geheim123');

      expect(await AccountRepository(db: db).getAllAccounts(user.uid), hasLength(7));
      expect(await CategoryRepository(db: db).getAllCategories(user.uid), hasLength(33));
      expect(PasswordHasher.isCurrentFormat(user.password), isTrue);
      final stored = await const FlutterSecureStorage().readAll();
      expect(stored.values, isNot(contains('geheim123')));
      expect(await auth.getCurrentEmail(), 'neu@test.de');
    });

    test('register rejects an existing email', () async {
      await auth.registerWithEmailAndPassword('neu@test.de', 'geheim123');
      expect(() => auth.registerWithEmailAndPassword('neu@test.de', 'anderes'), throwsA(isA<AccountExistsException>()));
      expect(const AccountExistsException().toString(), contains('Passwort vergessen?'));
    });

    test('reset: outdated hash without confirmation, current hash only with device confirmation', () async {
      // Hash aus einer älteren App-Version mit unbekanntem Zusatz – nicht mehr prüfbar
      final peppered = sha256.convert(utf8.encode('geheim123-unbekannter-zusatz')).toString();
      await users.createUser(UserModel(uid: 0, email: 'alt@test.de', password: peppered));

      expect(await auth.signInWithEmailAndPassword('alt@test.de', 'geheim123'), isNull);
      expect(await auth.hasOutdatedPassword('alt@test.de'), isTrue);
      expect(await auth.accountExists('alt@test.de'), isTrue);
      expect(await auth.accountExists('fremd@test.de'), isFalse);

      expect(await auth.resetPassword('alt@test.de', 'neuesPw1', deviceConfirmed: false), ResetResult.done);
      expect(await auth.hasOutdatedPassword('alt@test.de'), isFalse);
      expect(await auth.getCurrentEmail(), 'alt@test.de');
      expect(await auth.signInWithEmailAndPassword('alt@test.de', 'neuesPw1'), isNotNull);

      // Jetzt aktuelles Format: ohne Bestätigung der Gerätesperre kein Zurücksetzen mehr
      expect(await auth.resetPassword('alt@test.de', 'anderes1', deviceConfirmed: false), ResetResult.notConfirmed);
      expect(await auth.resetPassword('alt@test.de', 'anderes1', deviceConfirmed: true), ResetResult.done);
      expect(await auth.signInWithEmailAndPassword('alt@test.de', 'anderes1'), isNotNull);
      expect(await auth.resetPassword('fremd@test.de', 'anderes1', deviceConfirmed: true), ResetResult.unknownEmail);
    });

    test('sign-in upgrades a legacy hash and survives an email change', () async {
      final legacy = sha256.convert(utf8.encode('geheim123')).toString();
      final uid = await users.createUser(UserModel(uid: 0, email: 'alt@test.de', password: legacy));

      expect(await auth.signInWithEmailAndPassword('alt@test.de', 'geheim123'), isNotNull);
      expect(PasswordHasher.isCurrentFormat((await users.getUser(uid)).password), isTrue);

      await users.updateUser((await users.getUser(uid)).copyWith(email: 'neu@test.de'));
      expect(await auth.signInWithEmailAndPassword('neu@test.de', 'geheim123'), isNotNull);
    });

    test('outdated hash: only the signed-in user can set a new password without the old one', () async {
      final uid = await users.createUser(UserModel(uid: 0, email: 'alt@test.de', password: 'unbekanntes-altes-format'));
      final user = await users.getUser(uid);
      expect(auth.needsNewPassword(user), isTrue);

      // Ohne Sitzung für dieses Konto: abgelehnt
      FlutterSecureStorage.setMockInitialValues({'email': 'jemand@anders.de'});
      expect(await auth.setPasswordForOutdatedAccount(user, 'neuesPw1'), isFalse);

      // Angemeldet: erlaubt, danach normales Login mit dem neuen Passwort
      FlutterSecureStorage.setMockInitialValues({'email': 'alt@test.de'});
      expect(await auth.setPasswordForOutdatedAccount(user, 'neuesPw1'), isTrue);
      expect(auth.needsNewPassword(await users.getUser(uid)), isFalse);
      expect(await auth.signInWithEmailAndPassword('alt@test.de', 'neuesPw1'), isNotNull);

      // Mit aktuellem Hash greift der Weg nicht mehr
      expect(await auth.setPasswordForOutdatedAccount(user, 'nochmal12'), isFalse);
    });

    test('changePassword requires the current password', () async {
      final user = await auth.registerWithEmailAndPassword('neu@test.de', 'geheim123');

      expect(await auth.changePassword(user, 'falsch', 'neuesPw1'), isFalse);
      expect(await auth.changePassword(user, 'geheim123', 'neuesPw1'), isTrue);
      expect(await auth.signInWithEmailAndPassword('neu@test.de', 'neuesPw1'), isNotNull);
      expect(await auth.signInWithEmailAndPassword('neu@test.de', 'geheim123'), isNull);
    });

    test('startup removes a plaintext password left by older versions', () async {
      FlutterSecureStorage.setMockInitialValues({'email': 'a@b.de', 'password': 'klartext'});

      expect(await auth.getCurrentEmail(), 'a@b.de');
      expect(await const FlutterSecureStorage().read(key: 'password'), isNull);
    });
  });
}
