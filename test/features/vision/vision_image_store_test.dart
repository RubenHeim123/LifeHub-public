import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:frontend/features/vision/repositories/vision_repository.dart';
import 'package:frontend/core/services/image_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory base;
  late VisionImageStore store;

  setUp(() {
    base = Directory.systemTemp.createTempSync('lifehub_store_');
    store = VisionImageStore(baseDir: () async => base);
  });

  test('imported files are copied into the app folder and stored relatively', () async {
    final source = File(p.join(Directory.systemTemp.createTempSync().path, 'Foto.JPG'))..writeAsBytesSync([1, 2, 3]);

    final stored = await store.importFile(source.path);

    expect(p.isAbsolute(stored), isFalse);
    expect(stored, startsWith(store.folder));
    expect(p.extension(stored), '.jpg');
    source.deleteSync(); // Original weg (z. B. Picker-Cache geleert) – Kopie bleibt
    expect((await store.resolve(stored))!.readAsBytesSync(), [1, 2, 3]);
  });

  test('every template image is a bundled asset that can be imported', () async {
    for (final (title, _, asset, _) in visionBoardTemplate) {
      if (asset == null) continue; // Bereich ohne Vorlagenbild
      final stored = await store.importAsset(asset);
      final file = await store.resolve(stored);
      expect(file, isNotNull, reason: title);
      // JPEG-Signatur
      expect(file!.readAsBytesSync().take(2), [0xFF, 0xD8], reason: asset);
    }
  });

  test('delete removes managed images but never foreign files', () async {
    final foreign = File(p.join(base.path, 'fremd.jpg'))..writeAsBytesSync([9]);
    final stored = await store.importAsset('assets/images/blauerHintergrund.jpeg');

    await store.delete(stored);
    await store.delete(foreign.path);
    await store.delete('fremd.jpg');

    expect(await store.resolve(stored), isNull);
    expect(foreign.existsSync(), isTrue);
  });

  test('resolve returns null for missing or empty paths', () async {
    expect(await store.resolve(null), isNull);
    expect(await store.resolve(''), isNull);
    expect(await store.resolve('vision_images/gibt_es_nicht.jpg'), isNull);
  });
}
