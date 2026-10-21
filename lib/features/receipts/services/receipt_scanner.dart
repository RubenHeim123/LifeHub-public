import 'dart:io';
import 'dart:ui' show Rect;

import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';

import 'package:frontend/core/services/image_store.dart';

/// Ergebnis einer Aufnahme: gespeichertes Foto (relativer Pfad im [ReceiptImageStore]) und die erkannten Zeilen.
class ReceiptScan {
  final String? imagePath;
  final List<String> lines;
  const ReceiptScan({this.imagePath, required this.lines});
}

/// Fotos der Kassenzettel (an der Buchung als Beleg).
class ReceiptImageStore extends ImageStore {
  ReceiptImageStore({super.baseDir, super.bundle}) : super('receipt_images');
}

/// Kassenzettel fotografieren (oder aus der Galerie wählen) und den Text auf dem Gerät erkennen
/// (ML Kit, funktioniert offline). In Tests wird eine eigene Implementierung per Provider eingesetzt.
class ReceiptScanner {
  ReceiptScanner({ReceiptImageStore? images}) : _images = images ?? ReceiptImageStore();

  final ReceiptImageStore _images;

  /// `null`, wenn die Aufnahme abgebrochen wurde.
  Future<ReceiptScan?> scan({bool fromGallery = false}) async {
    final photo = await ImagePicker().pickImage(
      source: fromGallery ? ImageSource.gallery : ImageSource.camera,
      imageQuality: 85,
      maxWidth: 2200,
    );
    if (photo == null) return null;
    final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
    try {
      final text = await recognizer.processImage(InputImage.fromFilePath(photo.path));
      return ReceiptScan(imagePath: await _images.importFile(photo.path), lines: rowsFromText(text));
    } finally {
      await recognizer.close();
      try {
        await File(photo.path).delete();
      } catch (_) {}
    }
  }

  /// ML Kit liefert Textblöcke spaltenweise (Artikel links, Preise rechts). Für den Bon werden die
  /// Wörter wieder zu Zeilen zusammengesetzt: gleiche Höhe → eine Zeile, links nach rechts.
  static List<String> rowsFromText(RecognizedText text) => rowsFromBoxes([
        for (final block in text.blocks)
          for (final line in block.lines)
            for (final element in line.elements) (element.text, element.boundingBox),
      ]);

  /// Reine Zeilenbildung aus (Text, Rahmen) – auch ohne ML Kit testbar.
  static List<String> rowsFromBoxes(List<(String, Rect)> words) {
    if (words.isEmpty) return const [];
    final sorted = [...words]..sort((a, b) => a.$2.center.dy.compareTo(b.$2.center.dy));
    final rows = <List<(String, Rect)>>[];
    for (final w in sorted) {
      final row = rows.isEmpty ? null : rows.last;
      if (row != null) {
        final height = row.first.$2.height;
        final dy = (w.$2.center.dy - row.first.$2.center.dy).abs();
        if (dy < height * 0.55) {
          row.add(w);
          continue;
        }
      }
      rows.add([w]);
    }
    return [
      for (final row in rows) (row..sort((a, b) => a.$2.left.compareTo(b.$2.left))).map((w) => w.$1).join(' '),
    ];
  }
}
