import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:frontend/core/models/app_exceptions.dart';
import 'package:frontend/features/fitness/services/meal_photo_ai.dart';

void main() {
  final photo = Uint8List.fromList([1, 2, 3]);
  const answer = {
    'name': 'Spaghetti Bolognese',
    'grams': 450,
    'kcal': 680,
    'protein_g': 32,
    'carbs_g': 85,
    'fat_g': 22,
    'components': ['300 g Spaghetti', '150 g Bolognese-Soße'],
    'note': 'Soßenmenge geschätzt',
  };

  http.Response ok(Map<String, dynamic> json) => http.Response(
        jsonEncode({
          'stop_reason': 'end_turn',
          'content': [
            {'type': 'thinking', 'thinking': ''},
            {'type': 'text', 'text': jsonEncode(json)},
          ],
        }),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );

  setUp(() => FlutterSecureStorage.setMockInitialValues({'anthropic_api_key': 'sk-ant-test'}));

  test('sends the photo with key, model and JSON schema; the answer becomes a meal estimate', () async {
    late http.Request sent;
    final ai = MealPhotoAi(client: MockClient((r) async {
      sent = r;
      return ok(answer);
    }));
    final e = await ai.estimate(photo);
    expect((e.name, e.grams, e.kcal, e.protein, e.carbs, e.fat), ('Spaghetti Bolognese', 450.0, 680.0, 32.0, 85.0, 22.0));
    expect(e.components, hasLength(2));
    expect(e.note, 'Soßenmenge geschätzt');

    expect(sent.url.toString(), 'https://api.anthropic.com/v1/messages');
    expect(sent.headers['x-api-key'], 'sk-ant-test');
    expect(sent.headers['anthropic-version'], '2023-06-01');
    final body = jsonDecode(sent.body) as Map<String, dynamic>;
    expect(body['model'], 'claude-opus-5-5');
    expect(body['output_config']['format']['type'], 'json_schema');
    final image = (body['messages'][0]['content'] as List).first as Map;
    expect((image['type'], image['source']['media_type'], image['source']['data']), ('image', 'image/jpeg', base64Encode(photo)));
  });

  test('without a key nothing is sent and the user is told where to enter it', () async {
    FlutterSecureStorage.setMockInitialValues({});
    var calls = 0;
    final ai = MealPhotoAi(client: MockClient((_) async {
      calls++;
      return ok(answer);
    }));
    await expectLater(ai.estimate(photo), throwsA(isA<UserFacingException>().having((e) => e.message, 'message', contains('Profil'))));
    expect(calls, 0);
  });

  test('rejected key, offline, refusal and a broken answer give friendly messages', () async {
    Future<String> messageFor(Future<http.Response> Function(http.Request) handler) async {
      try {
        await MealPhotoAi(client: MockClient(handler)).estimate(photo);
        return 'kein Fehler';
      } on UserFacingException catch (e) {
        return e.message;
      }
    }

    expect(await messageFor((_) async => http.Response('{}', 401)), contains('abgelehnt'));
    expect(await messageFor((_) async => throw const SocketException('offline')), contains('Internet'));
    expect(await messageFor((_) async => http.Response(jsonEncode({'stop_reason': 'refusal', 'content': []}), 200)), contains('nicht ausgewertet'));
    expect(await messageFor((_) async => http.Response(jsonEncode({'content': [{'type': 'text', 'text': '{kaputt'}]}), 200)), contains('unvollständig'));
  });

  test('the key lives in secure storage and can be removed', () async {
    FlutterSecureStorage.setMockInitialValues({});
    const keys = AiKeyStore();
    expect(await keys.read(), isNull);
    await keys.save('  sk-ant-neu  ');
    expect(await keys.read(), 'sk-ant-neu');
    await keys.clear();
    expect(await keys.read(), isNull);
  });
}
