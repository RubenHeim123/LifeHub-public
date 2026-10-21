import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:frontend/app/app_tabs.dart';
import 'package:frontend/app/tab_style.dart';
import 'package:frontend/core/ui/theme.dart';

/// Kontrast nach WCAG 2.x.
double contrast(Color a, Color b) {
  final la = a.computeLuminance(), lb = b.computeLuminance();
  final (hi, lo) = la > lb ? (la, lb) : (lb, la);
  return (hi + 0.05) / (lo + 0.05);
}

void main() {
  test('every tab has its own color, readable in light and dark (icons ≥ 3:1)', () {
    for (final (name, c, dark) in [('hell', AppColors.light, false), ('dunkel', AppColors.dark, true)]) {
      final tones = <Color>{};
      for (final tab in AppTab.values) {
        final s = tab.style;
        final pill = s.pill(dark: dark);
        tones.add(pill);
        expect(contrast(s.onPill(dark: dark), pill), greaterThanOrEqualTo(3), reason: '${s.label} Pille ($name)');
        expect(contrast(s.tone(dark: dark), c.bg), greaterThanOrEqualTo(3), reason: '${s.label} Kopf-Icon ($name)');
        expect(s.label, isNotEmpty);
      }
      expect(tones, hasLength(AppTab.values.length), reason: 'jede Farbe nur einmal ($name)');
    }
  });
}
