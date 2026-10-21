import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:frontend/core/ui/theme.dart';

/// Hinweis für eine leere Liste: Icon, Titel, Erklärung und optional ein Knopf.
class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? message;
  final Widget? action;

  const EmptyState({super.key, required this.icon, required this.title, this.message, this.action});

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 48, 24, 24),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 48, color: c.muted),
        const SizedBox(height: 12),
        Text(title, textAlign: TextAlign.center, style: t.titleMedium),
        if (message != null) ...[
          const SizedBox(height: 4),
          Text(message!, textAlign: TextAlign.center, style: t.bodyMedium?.copyWith(color: c.muted)),
        ],
        if (action != null) ...[const SizedBox(height: 16), action!],
      ]),
    );
  }
}

/// Standard-Karte des Redesigns.
class AppCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final Color? color;
  final VoidCallback? onTap;

  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.radius = AppTheme.radiusCard,
    this.color,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Material(
      color: color ?? c.card,
      // Im dunklen Modus hebt eine feine Kontur die Karte vom fast gleich dunklen Hintergrund ab
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radius),
        side: dark && color == null ? BorderSide(color: c.line) : BorderSide.none,
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          padding: padding,
          child: child,
        ),
      ),
    );
  }
}

/// Seitentitel (gleich groß wie der Tab-Titel) mit optionaler Zeile darüber, Icon und Aktionen rechts.
class ScreenHeader extends StatelessWidget {
  final String? overline;
  final String title;
  final List<Widget> actions;
  final IconData? icon;
  final Color? iconColor;

  const ScreenHeader({super.key, this.overline, required this.title, this.actions = const [], this.icon, this.iconColor});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final titleBlock = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (overline != null) ...[
          Text(overline!, style: t.bodySmall),
          const SizedBox(height: 4),
        ],
        Row(children: [
          if (icon != null) ...[
            IconTile(icon: icon!, color: iconColor ?? AppColors.of(context).accentText, size: 32, iconSize: 18),
            const SizedBox(width: 10),
          ],
          Flexible(child: Text(title, style: t.headlineSmall?.copyWith(fontWeight: FontWeight.w700, height: 1.1))),
        ]),
      ],
    );
    if (actions.isEmpty) return SizedBox(width: double.infinity, child: titleBlock);

    return LayoutBuilder(builder: (context, constraints) {
      // Schmale Geräte mit mehreren Aktionen (z. B. Filter-Chips): Aktionen in eigener
      // Zeile unter dem Titel, damit nichts überläuft. Ein einzelner Button bleibt daneben.
      if (constraints.maxWidth < 420 && actions.length > 1) {
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          titleBlock,
          const SizedBox(height: 10),
          Wrap(spacing: 8, runSpacing: 8, alignment: WrapAlignment.end, children: actions),
        ]);
      }
      return Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(child: titleBlock),
          ...actions.expand((w) => [const SizedBox(width: 8), w]),
        ],
      );
    });
  }
}

/// Erste Zeile einer Bereichsseite unter dem Tab-Titel: kurzer Stand („2 offen“) und optional Knöpfe.
class SummaryRow extends StatelessWidget {
  final String text;
  final List<Widget> actions;
  const SummaryRow(this.text, {super.key, this.actions = const []});

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 32),
      child: Row(children: [
        Expanded(child: Text(text, style: Theme.of(context).textTheme.labelLarge?.copyWith(color: c.muted))),
        ...actions,
      ]),
    );
  }
}

/// Abschnittsüberschrift ("Habits heute", "To-Dos" …).
class SectionTitle extends StatelessWidget {
  final String title;
  final String? trailing;
  final VoidCallback? onTrailingTap;

  const SectionTitle(this.title, {super.key, this.trailing, this.onTrailingTap});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Expanded(child: Text(title, style: t.titleLarge)),
          if (trailing != null)
            GestureDetector(onTap: onTrailingTap, child: Text(trailing!, style: t.bodySmall)),
        ],
      ),
    );
  }
}

/// Monospace-Label für Gruppen ("HEUTE", "DIESE WOCHE").
class GroupLabel extends StatelessWidget {
  final String label;
  final String? trailing;
  const GroupLabel(this.label, {super.key, this.trailing});

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final style = TextStyle(fontFamily: 'monospace', fontSize: 12, letterSpacing: 0.6, color: c.muted);
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
      child: Row(children: [
        Expanded(child: Text(label.toUpperCase(), style: style)),
        if (trailing != null) Text(trailing!, style: TextStyle(fontSize: 12, color: c.dim)),
      ]),
    );
  }
}

/// Runder Icon-Button (Suche, Hinzufügen …).
class RoundIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  final bool filled;
  final String? label;
  final String? tooltip;

  const RoundIconButton({super.key, required this.icon, this.onTap, this.filled = false, this.label, this.tooltip});

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final bg = filled ? c.navActive : c.card;
    final fg = filled ? c.onNavActive : c.text;
    final child = Material(
      color: bg,
      shape: const StadiumBorder(),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: Container(
          height: 44,
          constraints: const BoxConstraints(minWidth: 44),
          padding: EdgeInsets.only(left: label == null ? 0 : 12, right: label == null ? 0 : 16),
          alignment: Alignment.center,
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 22, color: fg),
            if (label != null) ...[
              const SizedBox(width: 4),
              Text(label!, style: TextStyle(color: fg, fontWeight: FontWeight.w600, fontSize: 14)),
            ],
          ]),
        ),
      ),
    );
    return tooltip == null ? child : Tooltip(message: tooltip!, child: child);
  }
}

/// Filter-Chip mit Zähler.
class AppChip extends StatelessWidget {
  final String label;
  final int? count;
  final bool selected;
  final VoidCallback? onTap;
  final IconData? trailingIcon;

  const AppChip({super.key, required this.label, this.count, this.selected = false, this.onTap, this.trailingIcon});

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final bg = selected ? c.text : c.card;
    final fg = selected ? c.bg : c.text;
    return Material(
      color: bg,
      shape: const StadiumBorder(),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        // Kein Container(alignment: …): das würde den Chip auf die volle Breite aufziehen
        // und ihn in einem Wrap in eine eigene Zeile zwingen. Center(widthFactor: 1) schrumpft auf den Inhalt.
        child: SizedBox(
          height: 36,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Center(
              widthFactor: 1,
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Flexible(
                  child: Text(label,
                      maxLines: 1,
                      softWrap: false,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: fg, fontSize: 13, fontWeight: FontWeight.w500)),
                ),
                if (count != null) ...[
                  const SizedBox(width: 6),
                  Text('$count', style: TextStyle(color: fg.withValues(alpha: 0.6), fontSize: 11, fontFamily: 'monospace')),
                ],
                if (trailingIcon != null) ...[
                  const SizedBox(width: 2),
                  Icon(trailingIcon, size: 18, color: fg),
                ],
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

/// Abhak-Box (eckig für To-Dos, rund für Habits).
class AppCheck extends StatelessWidget {
  final bool checked;
  final VoidCallback? onTap;
  final double size;
  final bool round;
  final Color? color;
  final bool emphasize; // z. B. "heute" hervorheben

  const AppCheck({
    super.key,
    required this.checked,
    this.onTap,
    this.size = 24,
    this.round = false,
    this.color,
    this.emphasize = false,
  });

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final col = color ?? c.accent;
    final borderColor = checked || emphasize ? col : c.line;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: checked ? col : Colors.transparent,
          borderRadius: BorderRadius.circular(round ? size / 2 : 8),
          border: Border.all(color: borderColor, width: emphasize && !checked ? 2 : 1.5),
        ),
        child: checked ? Icon(Icons.check_rounded, size: size * 0.72, color: c.onAccent) : null,
      ),
    );
  }
}

/// Dünner Fortschrittsbalken.
class AppProgressBar extends StatelessWidget {
  final double value;
  final Color? color;
  final Color? track;
  final double height;

  const AppProgressBar({super.key, required this.value, this.color, this.track, this.height = 6});

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return ClipRRect(
      borderRadius: BorderRadius.circular(height / 2),
      child: SizedBox(
        height: height,
        child: Stack(children: [
          Positioned.fill(child: ColoredBox(color: track ?? c.line)),
          AnimatedFractionallySizedBox(
            duration: const Duration(milliseconds: 400),
            curve: Curves.easeOut,
            widthFactor: value.clamp(0.0, 1.0),
            child: Container(
              decoration: BoxDecoration(color: color ?? c.accent, borderRadius: BorderRadius.circular(height / 2)),
            ),
          ),
        ]),
      ),
    );
  }
}

/// Tages-Score-Ring.
class ScoreRing extends StatelessWidget {
  final double progress;
  final double size;
  final double stroke;
  final Color color;
  final Color track;
  final Widget? child;

  const ScoreRing({
    super.key,
    required this.progress,
    required this.color,
    required this.track,
    this.size = 112,
    this.stroke = 10,
    this.child,
  });

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(end: progress.clamp(0.0, 1.0)),
      duration: const Duration(milliseconds: 500),
      curve: Curves.easeOut,
      builder: (_, v, __) => SizedBox(
        width: size,
        height: size,
        child: CustomPaint(
          painter: _RingPainter(v, color, track, stroke),
          child: Center(child: child),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  final double v;
  final Color color, track;
  final double stroke;
  _RingPainter(this.v, this.color, this.track, this.stroke);

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final r = rect.deflate(stroke / 2);
    final base = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..color = track;
    canvas.drawArc(r, 0, math.pi * 2, false, base);
    if (v <= 0) return;
    final fg = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..color = color;
    canvas.drawArc(r, -math.pi / 2, math.pi * 2 * v, false, fg);
  }

  @override
  bool shouldRepaint(covariant _RingPainter o) => o.v != v || o.color != color || o.track != track;
}

/// Farbige Icon-Kachel.
class IconTile extends StatelessWidget {
  final IconData icon;
  final Color color;
  final Color? background;
  final double size;
  final double iconSize;

  const IconTile({super.key, required this.icon, required this.color, this.background, this.size = 38, this.iconSize = 22});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: background ?? color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(size * 0.32),
      ),
      child: Icon(icon, color: color, size: iconSize),
    );
  }
}

/// Glas-Hintergrund für schwebende Leisten.
class FrostedPill extends StatelessWidget {
  final Widget child;
  final double height;
  final EdgeInsetsGeometry padding;
  const FrostedPill({super.key, required this.child, this.height = 66, this.padding = const EdgeInsets.symmetric(horizontal: 9)});

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(height / 2),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: isDark ? 0.4 : 0.12), blurRadius: 30, offset: const Offset(0, 10))],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(height / 2),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
          child: Container(height: height, color: c.navBg, padding: padding, child: child),
        ),
      ),
    );
  }
}

/// Einheitliches Euro-Format ("8.412,50 €").
String formatEuro(double v, {int decimals = 0, bool sign = false}) {
  final abs = v.abs();
  final fixed = abs.toStringAsFixed(decimals);
  final parts = fixed.split('.');
  final intPart = parts[0].replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => '.');
  final dec = parts.length > 1 ? ',${parts[1]}' : '';
  final prefix = v < 0 ? '−' : (sign ? '+' : '');
  return '$prefix$intPart$dec €';
}
