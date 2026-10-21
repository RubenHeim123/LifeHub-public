import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Farben der Lebensbereiche im Logo (Heute, Planen, Fitness, Style, Finanzen).
const kLogoSegmentColors = [
  Color(0xFF5ED99E), // Heute – Akzentgrün
  Color(0xFFBDADFF), // Planen – Violett (Termine)
  Color(0xFFF2AF48), // Fitness – Amber
  Color(0xFFFF9189), // Style – Koralle
  Color(0xFF6EC6FF), // Finanzen – Blau
];

const kLogoBackground = Color(0xFF0E0F11);
const kLogoCenter = Color(0xFFF3F3F0);

/// Das LifeHub-Logo: ein Hub aus fünf farbigen Lebensbereichen um einen hellen Mittelpunkt.
/// [monochrome] zeichnet alles in einer Farbe (Android-13-Themensymbol).
class HubLogoPainter extends CustomPainter {
  final bool background;
  final Color? monochrome;

  /// Anteil der Fläche, den der Ring einnimmt (für Adaptive Icons kleiner, wegen der Safe Zone).
  final double scale;

  const HubLogoPainter({this.background = true, this.monochrome, this.scale = 1});

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    final center = Offset(size.width / 2, size.height / 2);
    if (background) {
      final rect = Offset.zero & size;
      canvas.drawRect(
        rect,
        Paint()
          ..shader = const RadialGradient(
            colors: [Color(0xFF1C1E22), kLogoBackground],
            radius: 0.75,
          ).createShader(rect),
      );
    }
    final ring = s * 0.31 * scale;
    final stroke = s * 0.12 * scale;
    const gap = 0.22; // Abstand zwischen den Segmenten (rad)
    const sweep = 2 * math.pi / 5;
    final arcRect = Rect.fromCircle(center: center, radius: ring);
    for (var i = 0; i < 5; i++) {
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.butt
        ..color = monochrome ?? kLogoSegmentColors[i];
      final start = -math.pi / 2 + i * sweep + gap / 2;
      canvas.drawArc(arcRect, start, sweep - gap, false, paint);
    }
    // Speichen zum Mittelpunkt – der „Hub“
    final spoke = Paint()
      ..color = (monochrome ?? kLogoCenter).withValues(alpha: monochrome == null ? 0.18 : 0.5)
      ..strokeWidth = s * 0.025 * scale
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < 5; i++) {
      final a = -math.pi / 2 + i * sweep + sweep / 2;
      canvas.drawLine(
        center + Offset(math.cos(a), math.sin(a)) * (s * 0.11 * scale),
        center + Offset(math.cos(a), math.sin(a)) * (ring - stroke / 2 - s * 0.03 * scale),
        spoke,
      );
    }
    canvas.drawCircle(center, s * 0.1 * scale, Paint()..color = monochrome ?? kLogoCenter);
  }

  @override
  bool shouldRepaint(HubLogoPainter old) => old.background != background || old.monochrome != monochrome || old.scale != scale;
}

/// Das Logo als Widget, z. B. auf dem Anmeldebildschirm.
class AppLogo extends StatelessWidget {
  final double size;
  const AppLogo({super.key, this.size = 72});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(size * 0.24),
      child: SizedBox.square(dimension: size, child: const CustomPaint(painter: HubLogoPainter())),
    );
  }
}
