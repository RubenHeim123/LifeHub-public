import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:frontend/core/models/dates.dart';
import 'package:frontend/core/ui/theme.dart';
import 'package:frontend/features/contacts/models/contact.dart';

/// Runder Avatar mit Initialen.
class ContactAvatar extends StatelessWidget {
  final Contact contact;
  final double size;
  const ContactAvatar({super.key, required this.contact, this.size = 40});

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: c.accent.withValues(alpha: 0.18), shape: BoxShape.circle),
      child: Text(
        contact.initials,
        style: TextStyle(color: c.accentText, fontWeight: FontWeight.w700, fontSize: size * 0.38),
        textScaler: TextScaler.noScaling, // passt sonst bei großer Schrift nicht in den Kreis
      ),
    );
  }
}

/// „heute“, „morgen“, „in 5 Tagen“ (oder `null`, wenn mehr als [within] Tage entfernt).
String? relativeDays(int days, {int within = 1 << 30}) {
  if (days > within) return null;
  return switch (days) {
    0 => 'heute',
    1 => 'morgen',
    -1 => 'gestern',
    final d when d < 0 => 'vor ${-d} Tagen',
    final d => 'in $d Tagen',
  };
}

/// „Geburtstag heute · wird 36“, „Geburtstag in 5 Tagen“ – nur bis zu [within] Tage voraus.
String? birthdayHint(Contact contact, DateTime now, {int within = 30}) {
  final days = contact.daysUntilBirthday(now);
  if (days == null || days > within) return null;
  final age = contact.ageAtNextBirthday(now)!;
  return 'Geburtstag ${relativeDays(days)}${age > 0 ? ' · wird $age' : ''}';
}

/// „Mi., 28. Okt. · in 8 Tagen“ für eine datierte Notiz.
String noteDateLabel(DateTime date, DateTime now) {
  final rel = relativeDays(daysBetween(dateOnly(now), dateOnly(date)), within: 30);
  final text = DateFormat(date.year == now.year ? 'E, d. MMM' : 'E, d. MMM y', 'de_DE').format(date);
  return rel == null ? text : '$text · $rel';
}
