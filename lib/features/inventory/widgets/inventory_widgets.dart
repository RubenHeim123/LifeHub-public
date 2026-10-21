import 'dart:io';

import 'package:flutter/material.dart';

import 'package:frontend/core/ui/theme.dart';
import 'package:frontend/features/inventory/models/inventory_item.dart';

/// Kurztext zum Ablauf: „heute“, „morgen“, „noch 5 Tage“, „seit 2 Tagen abgelaufen“.
String expiryText(InventoryItem item, {DateTime? now}) {
  final d = item.daysUntilExpiry(now);
  if (d == null) return '';
  if (d < -1) return 'seit ${-d} Tagen abgelaufen';
  if (d == -1) return 'seit gestern abgelaufen';
  if (d == 0) return 'läuft heute ab';
  if (d == 1) return 'läuft morgen ab';
  return 'noch $d Tage';
}

/// Alter kompakt: „3 Tage“, „5 Mon.“, „2 J.“.
String ageText(int days) {
  if (days < 31) return '$days ${days == 1 ? 'Tag' : 'Tage'}';
  if (days < 365) return '${days ~/ 30} Mon.';
  final years = days / 365;
  return '${years.toStringAsFixed(years < 10 ? 1 : 0).replaceAll('.0', '').replaceAll('.', ',')} J.';
}

/// Farbiges Ablauf-Badge: rot abgelaufen, orange bald, sonst neutral.
class ExpiryBadge extends StatelessWidget {
  final InventoryItem item;
  const ExpiryBadge(this.item, {super.key});

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final text = expiryText(item);
    if (text.isEmpty) return const SizedBox.shrink();
    final color = item.isExpired() ? c.negative : (item.expiresSoon() ? c.streak : c.muted);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(8)),
      child: Text(text, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: color)),
    );
  }
}

IconData inventoryIcon(InventoryItem item) {
  final category = item.category ?? '';
  return switch (item.kind) {
    InventoryKind.drink => category.contains('Kaffee') ? Icons.coffee_rounded : Icons.local_drink_rounded,
    InventoryKind.clothing => switch (category) {
        'Schuhe' => Icons.snowshoeing_rounded,
        'Jacken' => Icons.dry_cleaning_rounded,
        'Sportkleidung' => Icons.sports_rounded,
        _ => Icons.checkroom_rounded,
      },
    InventoryKind.food => switch (category) {
        'Obst & Gemüse' => Icons.eco_rounded,
        'Milchprodukte' => Icons.egg_alt_rounded,
        'Fleisch & Fisch' => Icons.set_meal_rounded,
        'Brot & Backwaren' => Icons.bakery_dining_rounded,
        'Tiefkühl' => Icons.ac_unit_rounded,
        'Snacks' => Icons.cookie_rounded,
        _ => Icons.kitchen_rounded,
      },
    InventoryKind.accessory => switch (category) {
        'Uhren' => Icons.watch_rounded,
        'Taschen' => Icons.work_outline_rounded,
        'Brillen' => Icons.visibility_rounded,
        _ => Icons.diamond_outlined,
      },
    InventoryKind.care => category == 'Parfüm' ? Icons.local_florist_rounded : Icons.spa_rounded,
    InventoryKind.other => Icons.inventory_2_rounded,
  };
}

/// Foto des Eintrags oder – ohne Foto – ein Icon passend zur Kategorie.
class InventoryThumb extends StatelessWidget {
  final InventoryItem item;
  final File? image;
  final double size;
  const InventoryThumb({super.key, required this.item, this.image, this.size = 44});

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return ClipRRect(
      borderRadius: BorderRadius.circular(size * 0.28),
      child: SizedBox(
        width: size,
        height: size,
        child: image != null
            ? Image.file(image!, fit: BoxFit.cover)
            : ColoredBox(color: c.cardAlt, child: Icon(inventoryIcon(item), color: c.muted, size: size * 0.5)),
      ),
    );
  }
}
