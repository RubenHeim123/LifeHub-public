import 'dart:io';
import 'dart:typed_data';

import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';

import 'package:frontend/features/receipts/services/receipt_scanner.dart';

/// Ein aufgenommenes Essens- bzw. Verpackungsfoto (JPEG, verkleinert) samt Pfad.
class FoodPhoto {
  final String path;
  final Uint8List bytes;
  const FoodPhoto(this.path, this.bytes);
}

/// Foto für die Ernährung aufnehmen bzw. aus der Galerie wählen und (für Nährwerttabellen) den
/// Text auf dem Gerät erkennen. In Tests wird eine eigene Implementierung per Provider eingesetzt.
class FoodPhotoScanner {
  const FoodPhotoScanner();

  /// `null`, wenn abgebrochen. Verkleinert, damit die KI-Schätzung schnell und günstig bleibt.
  Future<FoodPhoto?> pick({bool fromGallery = false}) async {
    final photo = await ImagePicker().pickImage(
      source: fromGallery ? ImageSource.gallery : ImageSource.camera,
      imageQuality: 80,
      maxWidth: 1280,
    );
    if (photo == null) return null;
    return FoodPhoto(photo.path, await photo.readAsBytes());
  }

  /// Erkannte Textzeilen (Wörter wie beim Kassenzettel zu Zeilen zusammengesetzt).
  Future<List<String>> readLines(FoodPhoto photo) async {
    final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
    try {
      return ReceiptScanner.rowsFromText(await recognizer.processImage(InputImage.fromFilePath(photo.path)));
    } finally {
      await recognizer.close();
    }
  }

  /// Aufgenommene Datei wieder löschen (das Foto wird nicht dauerhaft gespeichert).
  Future<void> discard(FoodPhoto photo) async {
    try {
      await File(photo.path).delete();
    } catch (_) {}
  }
}
