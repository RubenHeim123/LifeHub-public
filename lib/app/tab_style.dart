import 'package:flutter/material.dart';

import 'package:frontend/app/app_tabs.dart';

/// Beschriftung, Icons und Farbe eines Tabs – an einer Stelle für Leiste und Seitenkopf.
/// Jede Farbe gibt es hell (Pastell, für den dunklen Modus) und tief (für den hellen Modus).
class TabStyle {
  final String label;
  final IconData icon;
  final IconData activeIcon;
  final Color pastel;
  final Color deep;
  const TabStyle(this.label, this.icon, this.activeIcon, this.pastel, this.deep);

  /// Farbe als Schrift/Icon auf dem Hintergrund (Seitenkopf).
  Color tone({required bool dark}) => dark ? pastel : deep;

  /// Fläche der aktiven Pille in der Leiste und das Icon darauf.
  Color pill({required bool dark}) => dark ? pastel : deep;
  Color onPill({required bool dark}) => dark ? const Color(0xFF0E0F11) : Colors.white;

  Color toneOf(BuildContext context) => tone(dark: Theme.of(context).brightness == Brightness.dark);
}

extension AppTabStyle on AppTab {
  TabStyle get style => switch (this) {
        AppTab.today => const TabStyle('Heute', Icons.wb_sunny_outlined, Icons.wb_sunny_rounded, Color(0xFF5ED99E), Color(0xFF00804C)),
        AppTab.plan => const TabStyle('Planen', Icons.checklist_rounded, Icons.checklist_rounded, Color(0xFFBDADFF), Color(0xFF6451AC)),
        AppTab.food => const TabStyle('Essen', Icons.restaurant_outlined, Icons.restaurant_rounded, Color(0xFFF2AF48), Color(0xFFA65A00)),
        AppTab.training =>
          const TabStyle('Training', Icons.fitness_center_outlined, Icons.fitness_center_rounded, Color(0xFFFF9189), Color(0xFFB3473F)),
        AppTab.money => const TabStyle(
            'Geld', Icons.account_balance_wallet_outlined, Icons.account_balance_wallet_rounded, Color(0xFF6EC6FF), Color(0xFF1F6FB2)),
        AppTab.more => const TabStyle('Mehr', Icons.grid_view_outlined, Icons.grid_view_rounded, Color(0xFF4FD1C5), Color(0xFF1A7A71)),
      };
}
