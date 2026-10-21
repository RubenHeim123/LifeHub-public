import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';

import 'package:frontend/features/auth/services/default_user_data.dart';
import 'package:frontend/features/auth/services/password_hasher.dart';
import 'package:frontend/features/auth/models/user.dart';
import 'package:frontend/features/finance/repositories/account_repository.dart';
import 'package:frontend/features/finance/repositories/category_repository.dart';
import 'package:frontend/features/finance/repositories/user_repository.dart';

/// Anmeldung, Registrierung und Sitzung.
///
/// Im Secure Storage liegen nur E-Mail-Adressen, nie Passwörter:
/// - [_sessionKey]: angemeldeter Nutzer (fehlt → Login-Screen)
/// - [_biometricEmailKey]: Nutzer, der per Fingerabdruck angemeldet werden darf
class AuthService {
  AuthService({
    UserRepository? users,
    AccountRepository? accounts,
    CategoryRepository? categories,
    FlutterSecureStorage? storage,
    LocalAuthentication? localAuth,
  })  : _users = users ?? UserRepository(),
        _accounts = accounts ?? AccountRepository(),
        _categories = categories ?? CategoryRepository(),
        _storage = storage ?? const FlutterSecureStorage(),
        _localAuth = localAuth ?? LocalAuthentication();

  final UserRepository _users;
  final AccountRepository _accounts;
  final CategoryRepository _categories;
  final FlutterSecureStorage _storage;
  final LocalAuthentication _localAuth;

  static const _sessionKey = 'email';
  static const _legacyPasswordKey = 'password';
  static const _biometricEnabledKey = 'use_biometrics';
  static const _biometricEmailKey = 'biometric_email';

  /// Meldet an und gibt den Nutzer zurück, oder `null` bei falschen Daten.
  /// Hashes im alten Format werden dabei auf das aktuelle Format umgestellt.
  Future<UserModel?> signInWithEmailAndPassword(String email, String password) async {
    final user = await _users.getUserFromEmail(email);
    if (user == null) return null;
    if (!await PasswordHasher.verify(password, user.password)) return null;

    if (!PasswordHasher.isCurrentFormat(user.password)) {
      await _users.updatePasswordHash(user.uid, await PasswordHasher.hash(password));
    }
    await _startSession(email);
    return user;
  }

  /// Gibt es ein Konto zu [email], dessen Passwort aus einer älteren App-Version stammt
  /// und sich nicht mehr prüfen lässt? Dann muss es über [resetPassword] neu gesetzt werden.
  Future<bool> hasOutdatedPassword(String email) async {
    final user = await _users.getUserFromEmail(email);
    return user != null && !PasswordHasher.isCurrentFormat(user.password);
  }

  Future<bool> accountExists(String email) async => await _users.getUserFromEmail(email) != null;

  /// Bestätigt per Gerätesperre (Fingerabdruck, Gesicht, PIN oder Muster), dass der Besitzer
  /// des Geräts die App bedient. `null`, wenn das Gerät keine Sperre anbietet.
  Future<bool?> confirmDeviceOwner() async {
    try {
      if (!await _localAuth.isDeviceSupported()) return null;
      return await _localAuth.authenticate(
        localizedReason: 'Bestätige, dass du es bist, um ein neues Passwort festzulegen.',
        options: const AuthenticationOptions(stickyAuth: true, biometricOnly: false),
      );
    } catch (e) {
      debugPrint('Gerätesperre nicht verfügbar: $e');
      return null;
    }
  }

  /// Setzt das Passwort eines lokalen Kontos neu. Erlaubt, wenn der Gerätebesitzer bestätigt
  /// wurde ([deviceConfirmed]) – oder ohne Bestätigung, wenn das alte Passwort aus einer früheren
  /// App-Version stammt und sich ohnehin nicht mehr prüfen lässt. Meldet danach an.
  Future<ResetResult> resetPassword(String email, String newPassword, {required bool deviceConfirmed}) async {
    final user = await _users.getUserFromEmail(email);
    if (user == null) return ResetResult.unknownEmail;
    final outdated = !PasswordHasher.isCurrentFormat(user.password);
    if (!deviceConfirmed && !outdated) return ResetResult.notConfirmed;
    await _users.updatePasswordHash(user.uid, await PasswordHasher.hash(newPassword));
    await _startSession(email);
    return ResetResult.done;
  }

  /// Registriert einen neuen Nutzer mit Standardkonten und -kategorien.
  /// Wirft eine [Exception], wenn die E-Mail schon vergeben ist.
  Future<UserModel> registerWithEmailAndPassword(String email, String password) async {
    if (await _users.getUserFromEmail(email) != null) {
      throw const AccountExistsException();
    }
    final uid = await _users.createUser(
      UserModel(uid: 0, email: email, password: await PasswordHasher.hash(password), createdTime: DateTime.now()),
    );
    await _accounts.createAccounts(DefaultUserData.accounts(uid));
    await _categories.createCategories(DefaultUserData.categories(uid));
    await _startSession(email);
    return _users.getUser(uid);
  }

  /// Ändert das Passwort, wenn [currentPassword] stimmt. Gibt `false` sonst zurück.
  Future<bool> changePassword(UserModel user, String currentPassword, String newPassword) async {
    final stored = await _users.getUser(user.uid);
    if (!await PasswordHasher.verify(currentPassword, stored.password)) return false;
    await _users.updatePasswordHash(user.uid, await PasswordHasher.hash(newPassword));
    return true;
  }

  /// `true`, wenn der gespeicherte Hash aus einer früheren Version stammt und sich
  /// nicht mehr prüfen lässt – der Nutzer muss dann ein neues Passwort festlegen.
  bool needsNewPassword(UserModel user) => !PasswordHasher.isCurrentFormat(user.password);

  /// Setzt ein neues Passwort für ein Konto mit veraltetem Hash, ohne das alte zu prüfen.
  /// Nur für den angemeldeten Nutzer erlaubt: die bestehende Sitzung belegt die Identität.
  Future<bool> setPasswordForOutdatedAccount(UserModel user, String newPassword) async {
    final stored = await _users.getUser(user.uid);
    if (!needsNewPassword(stored)) return false;
    if (await _storage.read(key: _sessionKey) != stored.email) return false;
    await _users.updatePasswordHash(user.uid, await PasswordHasher.hash(newPassword));
    return true;
  }

  Future<void> _startSession(String email) async {
    await _storage.write(key: _sessionKey, value: email);
    if (await _storage.read(key: _biometricEnabledKey) == 'true') {
      await _storage.write(key: _biometricEmailKey, value: email);
    }
  }

  /// Beendet die Sitzung. Die biometrische Anmeldung bleibt eingerichtet.
  Future<void> signOut() async {
    await _storage.delete(key: _sessionKey);
    await _storage.delete(key: _legacyPasswordKey);
  }

  /// E-Mail des angemeldeten Nutzers. Entfernt dabei ein von älteren Versionen
  /// im Klartext gespeichertes Passwort.
  Future<String?> getCurrentEmail() async {
    await _storage.delete(key: _legacyPasswordKey);
    return _storage.read(key: _sessionKey);
  }

  Future<UserModel> getCurrentUser(String email) async {
    final user = await _users.getUserFromEmail(email);
    if (user == null) throw Exception('User not found');
    return user;
  }

  /// Nach einer E-Mail-Änderung im Profil Sitzung und Fingerabdruck-Zuordnung nachziehen.
  Future<void> onEmailChanged(String oldEmail, String newEmail) async {
    if (await _storage.read(key: _sessionKey) == oldEmail) {
      await _storage.write(key: _sessionKey, value: newEmail);
    }
    if (await _storage.read(key: _biometricEmailKey) == oldEmail) {
      await _storage.write(key: _biometricEmailKey, value: newEmail);
    }
  }

  /// Beim Löschen eines Nutzers auch dessen Fingerabdruck-Anmeldung entfernen.
  Future<void> forgetUser(String? email) async {
    if (email != null && await _storage.read(key: _biometricEmailKey) == email) {
      await _storage.delete(key: _biometricEmailKey);
      await _storage.delete(key: _biometricEnabledKey);
    }
    await signOut();
  }

  // ─── Biometric Authentication ──────────────────────────────────────

  /// Ist die Fingerabdruck-Anmeldung eingerichtet und auf dem Gerät verfügbar?
  Future<bool> isBiometricsEnabled() async {
    if (await _storage.read(key: _biometricEnabledKey) != 'true') return false;
    if (await _storage.read(key: _biometricEmailKey) == null) return false;
    try {
      return await _localAuth.canCheckBiometrics || await _localAuth.isDeviceSupported();
    } catch (e) {
      debugPrint('Biometrie nicht verfügbar: $e');
      return false;
    }
  }

  /// Aktiviert/deaktiviert die Fingerabdruck-Anmeldung für [email].
  Future<void> setBiometricsEnabled(bool enabled, {required String? email}) async {
    await _storage.write(key: _biometricEnabledKey, value: enabled.toString());
    if (enabled && email != null) {
      await _storage.write(key: _biometricEmailKey, value: email);
    } else {
      await _storage.delete(key: _biometricEmailKey);
    }
  }

  /// Fragt den Fingerabdruck ab und meldet bei Erfolg den hinterlegten Nutzer an.
  Future<UserModel?> authenticateWithBiometrics() async {
    try {
      final email = await _storage.read(key: _biometricEmailKey);
      if (email == null) return null;
      final ok = await _localAuth.authenticate(
        localizedReason: 'Bitte authentifiziere dich, um dich anzumelden.',
        options: const AuthenticationOptions(stickyAuth: true, biometricOnly: true),
      );
      if (!ok) return null;
      final user = await _users.getUserFromEmail(email);
      if (user != null) await _storage.write(key: _sessionKey, value: email);
      return user;
    } catch (e) {
      debugPrint('Biometric auth error: $e');
      return null;
    }
  }
}

enum ResetResult { done, unknownEmail, notConfirmed }

/// Für die E-Mail gibt es schon ein Konto.
class AccountExistsException implements Exception {
  const AccountExistsException();

  @override
  String toString() => 'Für diese E-Mail gibt es schon ein Konto. Melde dich an oder nutze „Passwort vergessen?“.';
}
