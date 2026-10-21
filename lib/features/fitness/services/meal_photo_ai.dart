import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

import 'package:frontend/core/models/app_exceptions.dart';

/// Von der KI geschätzte Mahlzeit auf einem Foto (Werte für die ganze geschätzte Menge).
class MealEstimate {
  final String name;
  final double grams;
  final double kcal, protein, carbs, fat;
  final List<String> components;
  final String? note;

  const MealEstimate({
    required this.name,
    required this.grams,
    required this.kcal,
    required this.protein,
    required this.carbs,
    required this.fat,
    this.components = const [],
    this.note,
  });

  factory MealEstimate.fromJson(Map<String, dynamic> m) {
    double n(String k) => (m[k] as num?)?.toDouble() ?? 0;
    return MealEstimate(
      name: (m['name'] as String?)?.trim().isNotEmpty == true ? (m['name'] as String).trim() : 'Mahlzeit',
      grams: n('grams'),
      kcal: n('kcal'),
      protein: n('protein_g'),
      carbs: n('carbs_g'),
      fat: n('fat_g'),
      components: [for (final c in (m['components'] as List? ?? const [])) c.toString()],
      note: (m['note'] as String?)?.trim().isEmpty == true ? null : m['note'] as String?,
    );
  }
}

/// Anthropic-API-Schlüssel für die Foto-Schätzung – nur im sicheren Speicher des Geräts,
/// nie in der Datenbank oder im Export.
class AiKeyStore {
  const AiKeyStore({FlutterSecureStorage? storage}) : _storage = storage ?? const FlutterSecureStorage();
  final FlutterSecureStorage _storage;
  static const _key = 'anthropic_api_key';

  Future<String?> read() async {
    final v = await _storage.read(key: _key);
    return v == null || v.trim().isEmpty ? null : v.trim();
  }

  Future<void> save(String key) => _storage.write(key: _key, value: key.trim());
  Future<void> clear() => _storage.delete(key: _key);
}

/// Schätzt Gericht, Menge und Nährwerte aus einem Essensfoto mit Claude (Bildeingabe, strukturierte
/// JSON-Antwort). Braucht Internet und einen eigenen API-Schlüssel ([AiKeyStore]).
class MealPhotoAi {
  MealPhotoAi({AiKeyStore keys = const AiKeyStore(), http.Client? client})
      : _keys = keys,
        _client = client ?? http.Client();

  final AiKeyStore _keys;
  final http.Client _client;

  static final _endpoint = Uri.parse('https://api.anthropic.com/v1/messages');
  static const model = 'claude-opus-5-5';

  static const _schema = {
    'type': 'object',
    'additionalProperties': false,
    'required': ['name', 'grams', 'kcal', 'protein_g', 'carbs_g', 'fat_g', 'components', 'note'],
    'properties': {
      'name': {'type': 'string', 'description': 'Kurzer deutscher Name des Gerichts'},
      'grams': {'type': 'number', 'description': 'Geschätzte Gesamtmenge auf dem Foto in Gramm'},
      'kcal': {'type': 'number'},
      'protein_g': {'type': 'number'},
      'carbs_g': {'type': 'number'},
      'fat_g': {'type': 'number'},
      'components': {'type': 'array', 'items': {'type': 'string'}, 'description': 'Erkannte Bestandteile mit geschätzter Menge'},
      'note': {'type': 'string', 'description': 'Kurzer Hinweis zur Unsicherheit, sonst leer'},
    },
  };

  static const _prompt = 'Schätze für das Essen auf diesem Foto: Name des Gerichts, die gesamte sichtbare Menge in '
      'Gramm sowie Kalorien, Eiweiß, Kohlenhydrate und Fett für genau diese Menge. Liste die erkannten Bestandteile '
      'mit geschätzter Menge auf. Ist kein Essen zu sehen, setze name auf "Kein Essen erkannt" und alle Zahlen auf 0.';

  /// Liefert die Schätzung oder wirft eine [UserFacingException] mit verständlicher Meldung.
  Future<MealEstimate> estimate(Uint8List jpeg) async {
    final key = await _keys.read();
    if (key == null) {
      throw const UserFacingException('Kein API-Schlüssel für die KI-Schätzung – bitte im Profil unter „KI-Schätzung (Fotos)“ eintragen.');
    }
    final http.Response response;
    try {
      response = await _client
          .post(
            _endpoint,
            headers: {
              'content-type': 'application/json',
              'x-api-key': key,
              'anthropic-version': '2023-06-01',
              'anthropic-beta': 'server-side-fallback-2026-07-01',
            },
            body: jsonEncode({
              'model': model,
              'max_tokens': 2048,
              'fallbacks': 'default',
              // Einfache Schätzung: wenig Nachdenken, schnelle und günstige Antwort
              'output_config': {
                'effort': 'low',
                'format': {'type': 'json_schema', 'schema': _schema},
              },
              'messages': [
                {
                  'role': 'user',
                  'content': [
                    {
                      'type': 'image',
                      'source': {'type': 'base64', 'media_type': 'image/jpeg', 'data': base64Encode(jpeg)},
                    },
                    {'type': 'text', 'text': _prompt},
                  ],
                },
              ],
            }),
          )
          .timeout(const Duration(seconds: 60));
    } on TimeoutException {
      throw const UserFacingException('Die KI-Schätzung hat zu lange gedauert – bitte noch einmal versuchen.');
    } on SocketException {
      throw const UserFacingException('Keine Internetverbindung – die KI-Schätzung braucht Internet.');
    } on http.ClientException {
      throw const UserFacingException('Keine Internetverbindung – die KI-Schätzung braucht Internet.');
    }

    if (response.statusCode == 401 || response.statusCode == 403) {
      throw const UserFacingException('Der API-Schlüssel wurde abgelehnt – bitte im Profil prüfen.');
    }
    if (response.statusCode == 429) {
      throw const UserFacingException('Zu viele Anfragen – bitte kurz warten und noch einmal versuchen.');
    }
    if (response.statusCode != 200) {
      throw UserFacingException('Die KI-Schätzung ist fehlgeschlagen (Fehler ${response.statusCode}).');
    }

    try {
      final body = jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
      if (body['stop_reason'] == 'refusal') {
        throw const UserFacingException('Das Foto konnte nicht ausgewertet werden.');
      }
      final text = [
        for (final block in (body['content'] as List? ?? const []))
          if (block is Map && block['type'] == 'text') block['text'] as String,
      ].join();
      return MealEstimate.fromJson(jsonDecode(text) as Map<String, dynamic>);
    } on UserFacingException {
      rethrow;
    } catch (_) {
      throw const UserFacingException('Die Antwort der KI war unvollständig – bitte noch einmal versuchen.');
    }
  }

  /// Prüft den Schlüssel mit einer winzigen Anfrage (für „Testen“ im Profil). `null` = in Ordnung,
  /// sonst die Fehlermeldung.
  Future<String?> checkKey(String key) async {
    try {
      final response = await _client
          .post(
            _endpoint,
            headers: {'content-type': 'application/json', 'x-api-key': key.trim(), 'anthropic-version': '2023-06-01'},
            body: jsonEncode({
              'model': model,
              'max_tokens': 16,
              'output_config': {'effort': 'low'},
              'messages': [
                {'role': 'user', 'content': 'Antworte nur mit OK.'},
              ],
            }),
          )
          .timeout(const Duration(seconds: 30));
      if (response.statusCode == 200) return null;
      if (response.statusCode == 401 || response.statusCode == 403) return 'Der Schlüssel wurde abgelehnt.';
      return 'Fehler ${response.statusCode}';
    } catch (_) {
      return 'Keine Verbindung';
    }
  }
}
