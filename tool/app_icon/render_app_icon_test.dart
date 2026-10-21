// Erzeugt die Quellbilder des App-Icons aus HubLogoPainter.
// Aufruf:  flutter test tool/app_icon/render_app_icon_test.dart
// danach:  dart run flutter_launcher_icons  (setzt das Monochrom-Icon in ic_launcher.xml nicht – siehe unten)
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:frontend/core/ui/app_logo.dart';

Future<void> _render(String path, HubLogoPainter painter, {int size = 1024}) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  painter.paint(canvas, Size.square(size.toDouble()));
  final image = await recorder.endRecording().toImage(size, size);
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  File(path)
    ..createSync(recursive: true)
    ..writeAsBytesSync(bytes!.buffer.asUint8List());
}

void main() {
  test('render app icon sources', () async {
    const dir = 'assets/icons';
    // Vollbild (iOS, ältere Android-Versionen): mit Hintergrund
    await _render('$dir/app_icon.png', const HubLogoPainter());
    // Adaptive Icon: Vordergrund innerhalb der Safe Zone, Hintergrund als Farbe
    await _render('$dir/app_icon_foreground.png', const HubLogoPainter(background: false, scale: 0.62));
    // Android 13: einfarbiges Themensymbol
    await _render('$dir/app_icon_monochrome.png', const HubLogoPainter(background: false, scale: 0.62, monochrome: Colors.white));
    // flutter_launcher_icons 0.13 kennt kein Monochrom-Icon – direkt in die Android-Ressourcen
    const densities = {'mdpi': 108, 'hdpi': 162, 'xhdpi': 216, 'xxhdpi': 324, 'xxxhdpi': 432};
    for (final e in densities.entries) {
      await _render('android/app/src/main/res/drawable-${e.key}/ic_launcher_monochrome.png',
          const HubLogoPainter(background: false, scale: 0.62, monochrome: Colors.white),
          size: e.value);
    }
    expect(File('$dir/app_icon.png').existsSync(), isTrue);
  });
}
