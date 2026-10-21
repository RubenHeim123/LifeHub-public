import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Eigene Bilder der App liegen im App-Ordner unter [folder].
///
/// In der Datenbank steht nur der relative Pfad: Picker-Dateien im Cache können
/// vom System gelöscht werden, und der absolute App-Pfad ändert sich auf iOS
/// nach Updates.
class ImageStore {
  ImageStore(this.folder, {Future<Directory> Function()? baseDir, AssetBundle? bundle})
      : _baseDirLoader = baseDir ?? getApplicationDocumentsDirectory,
        _bundle = bundle ?? rootBundle;

  /// Unterordner im App-Ordner, z. B. `vision_images`.
  final String folder;

  final Future<Directory> Function() _baseDirLoader;
  final AssetBundle _bundle;
  Directory? _baseDir;
  var _counter = 0;

  Future<Directory> baseDir() async => _baseDir ??= await _baseDirLoader();

  /// Absolute Datei zu einem gespeicherten (relativen) Pfad – `null`, wenn es sie nicht gibt.
  Future<File?> resolve(String? storedPath) async {
    if (storedPath == null || storedPath.isEmpty) return null;
    final file = File(p.isAbsolute(storedPath) ? storedPath : p.join((await baseDir()).path, storedPath));
    return file.existsSync() ? file : null;
  }

  Future<String> _newRelativePath(String extension) async {
    final dir = Directory(p.join((await baseDir()).path, folder));
    await dir.create(recursive: true);
    final name = '${DateTime.now().microsecondsSinceEpoch}_${_counter++}$extension';
    return p.join(folder, name);
  }

  /// Kopiert ein ausgewähltes Bild in den App-Ordner und gibt den relativen Pfad zurück.
  Future<String> importFile(String sourcePath) async {
    final relative = await _newRelativePath(p.extension(sourcePath).toLowerCase());
    await File(sourcePath).copy(p.join((await baseDir()).path, relative));
    return relative;
  }

  /// Kopiert ein mitgeliefertes Asset (z. B. Vorlagenbild) in den App-Ordner.
  Future<String> importAsset(String assetPath) async {
    final bytes = await _bundle.load(assetPath);
    final relative = await _newRelativePath(p.extension(assetPath).toLowerCase());
    await File(p.join((await baseDir()).path, relative)).writeAsBytes(bytes.buffer.asUint8List(), flush: true);
    return relative;
  }

  /// Löscht ein von hier verwaltetes Bild (Fremddateien werden nie gelöscht).
  Future<void> delete(String? storedPath) async {
    if (storedPath == null || p.isAbsolute(storedPath) || !p.isWithin(folder, storedPath)) return;
    final file = await resolve(storedPath);
    if (file != null) await file.delete();
  }
}

/// Bilder des Vision Boards (Bereichsbilder, Vorlagenbilder).
class VisionImageStore extends ImageStore {
  VisionImageStore({super.baseDir, super.bundle}) : super('vision_images');
}

/// Fotos von Inventar-Einträgen (Vorrat, Kleidung, Outfits, Wunschliste).
class InventoryImageStore extends ImageStore {
  InventoryImageStore({super.baseDir, super.bundle}) : super('inventory_images');
}
