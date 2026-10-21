import 'dart:convert';
import 'dart:isolate';
import 'dart:math';

import 'package:crypto/crypto.dart';

/// Passwort-Hashing mit PBKDF2-HMAC-SHA256 und zufälligem Salt pro Nutzer.
///
/// Gespeichertes Format: `pbkdf2_sha256$<iterationen>$<salt base64>$<hash base64>`.
/// Salt und Parameter stehen im Hash selbst, daher bleibt das Passwort auch nach
/// einer E-Mail-Änderung gültig.
class PasswordHasher {
  PasswordHasher._();

  static const String _prefix = 'pbkdf2_sha256';
  static const int _iterations = 60000;
  static const int _saltLength = 16;
  static const int _keyLength = 32;

  static Future<String> hash(String password) async {
    final random = Random.secure();
    final salt = List<int>.generate(_saltLength, (_) => random.nextInt(256));
    final key = await Isolate.run(() => _pbkdf2(utf8.encode(password), salt, _iterations, _keyLength));
    return '$_prefix\$$_iterations\$${base64.encode(salt)}\$${base64.encode(key)}';
  }

  /// Prüft [password] gegen [stored]. Unterstützt zusätzlich die sehr alten Formate
  /// (ungesalzenes SHA-256 und Klartext); sie werden beim Login umgestellt.
  static Future<bool> verify(String password, String? stored) async {
    if (stored == null || stored.isEmpty) return false;
    if (!isCurrentFormat(stored)) return _verifyLegacy(password, stored);

    final parts = stored.split('\$');
    if (parts.length != 4) return false;
    final iterations = int.tryParse(parts[1]);
    if (iterations == null) return false;
    final salt = base64.decode(parts[2]);
    final expected = base64.decode(parts[3]);
    final actual = await Isolate.run(() => _pbkdf2(utf8.encode(password), salt, iterations, expected.length));
    return _constantTimeEquals(actual, expected);
  }

  static bool isCurrentFormat(String? stored) => stored != null && stored.startsWith('$_prefix\$');

  static bool _verifyLegacy(String password, String stored) {
    final candidates = [
      sha256.convert(utf8.encode(password)).toString(),
      password, // Klartext aus sehr alten Versionen
    ];
    return candidates.any((c) => _constantTimeEquals(utf8.encode(c), utf8.encode(stored)));
  }

  static List<int> _pbkdf2(List<int> password, List<int> salt, int iterations, int keyLength) {
    final hmac = Hmac(sha256, password);
    final out = <int>[];
    for (var block = 1; out.length < keyLength; block++) {
      var u = hmac.convert([...salt, block >> 24 & 0xff, block >> 16 & 0xff, block >> 8 & 0xff, block & 0xff]).bytes;
      final t = List<int>.of(u);
      for (var i = 1; i < iterations; i++) {
        u = hmac.convert(u).bytes;
        for (var j = 0; j < t.length; j++) {
          t[j] ^= u[j];
        }
      }
      out.addAll(t);
    }
    return out.sublist(0, keyLength);
  }

  static bool _constantTimeEquals(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a[i] ^ b[i];
    }
    return diff == 0;
  }
}
