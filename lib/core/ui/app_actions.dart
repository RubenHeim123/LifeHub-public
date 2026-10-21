import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_slidable/flutter_slidable.dart';

import 'package:frontend/core/ui/theme.dart';

// ─── Einheitliche Bedienung ────────────────────────────────────────────────
// Neu: AppFab unten rechts · Öffnen/Bearbeiten: Tippen oder nach links wischen ·
// Löschen: nach links wischen, mit „Rückgängig“ · Zusatzaktion: nach rechts wischen ·
// Fehler: Snackbar statt stiller Ausnahme.

/// Höhe der schwebenden Navigation der Startseite (Leiste + Abstand zum Rand).
const double kNavBarHeight = 66;
const double kNavBarMargin = 12;

/// Gibt die Höhe der schwebenden Navigation an die Tab-Seiten weiter. Flutter entfernt beim
/// FAB eines inneren Scaffolds den unteren Abstand – der [AppFab] liest die Höhe deshalb hier.
class NavBarInset extends InheritedWidget {
  final double height;
  const NavBarInset({super.key, required this.height, required super.child});

  /// Platz, den die Navigation unten belegt – inklusive Systemleiste (Gestennavigation).
  static double heightFor(BuildContext context) =>
      kNavBarHeight + math.max(MediaQuery.viewPaddingOf(context).bottom, kNavBarMargin);

  @override
  bool updateShouldNotify(NavBarInset oldWidget) => oldWidget.height != height;
}

/// Höhe, die die schwebende Navigation unten belegt (0 auf gepushten Seiten ohne Navigation).
double navInset(BuildContext context) =>
    context.dependOnInheritedWidgetOfExactType<NavBarInset>()?.height ?? 0;

/// Unterer Abstand für Listen: Navigation bzw. Systemleiste + Platz für den [AppFab].
double navClearance(BuildContext context) =>
    math.max(navInset(context), MediaQuery.paddingOf(context).bottom) + 96;

/// Innenabstand jeder Listen-Seite (Tab oder aufgeklappt): 20 dp seitlich, unten Platz für Navigation
/// bzw. Systemleiste und den [AppFab].
EdgeInsets pagePadding(BuildContext context) => EdgeInsets.fromLTRB(20, 12, 20, navClearance(context));

/// Innenabstand von Detail- und Formularseiten ohne Hinzufügen-Button.
EdgeInsets detailPadding(BuildContext context) => EdgeInsets.fromLTRB(20, 12, 20, 24 + MediaQuery.paddingOf(context).bottom);

/// Der eine Hinzufügen-Button unten rechts – auf Tab-Seiten über der Navigation,
/// auf gepushten Seiten an der üblichen Stelle.
class AppFab extends StatelessWidget {
  final String? label;
  final IconData icon;
  final VoidCallback? onPressed;
  final Object? heroTag;
  final String? tooltip;
  const AppFab({super.key, this.label, this.icon = Icons.add_rounded, this.onPressed, this.heroTag, this.tooltip});

  @override
  Widget build(BuildContext context) {
    final tag = heroTag ?? 'fab-${label ?? tooltip ?? icon.codePoint}';
    final fab = label == null
        ? FloatingActionButton(heroTag: tag, tooltip: tooltip, onPressed: onPressed, child: Icon(icon))
        : FloatingActionButton.extended(
            heroTag: tag,
            tooltip: tooltip,
            onPressed: onPressed,
            icon: Icon(icon),
            label: Text(label!),
          );
    return Padding(padding: EdgeInsets.only(bottom: navInset(context)), child: fab);
  }
}

/// Rückgabewert eines Editors, wenn dort „Löschen“ gewählt wurde. Die Liste löscht dann
/// mit [deleteWithUndo], damit „Rückgängig“ überall gleich funktioniert.
const kDeletedResult = 'deleted';

/// Zusatzaktion beim Wischen nach rechts (z. B. erledigt, −1, in den Vorrat).
class SwipeAction {
  final String label;
  final IconData icon;
  final VoidCallback onPressed;
  final Color? color;
  const SwipeAction({required this.label, required this.icon, required this.onPressed, this.color});
}

/// Listeneintrag mit den einheitlichen Wischaktionen: nach links Bearbeiten und Löschen,
/// nach rechts optional eine Zusatzaktion.
class SwipeTile extends StatelessWidget {
  final Object id;
  final Widget child;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;
  final SwipeAction? startAction;
  const SwipeTile({super.key, required this.id, required this.child, this.onEdit, this.onDelete, this.startAction});

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final end = [
      if (onEdit != null)
        SlidableAction(
          onPressed: (_) => onEdit!(),
          backgroundColor: c.cardAlt,
          foregroundColor: c.text,
          icon: Icons.edit_outlined,
          label: 'Bearbeiten',
        ),
      if (onDelete != null)
        SlidableAction(
          onPressed: (_) => onDelete!(),
          backgroundColor: c.negative,
          foregroundColor: Colors.white,
          icon: Icons.delete_outline,
          label: 'Löschen',
        ),
    ];
    final start = startAction;
    return Slidable(
      key: ValueKey(id),
      startActionPane: start == null
          ? null
          : ActionPane(motion: const DrawerMotion(), extentRatio: 0.3, children: [
              SlidableAction(
                onPressed: (_) => start.onPressed(),
                backgroundColor: start.color ?? c.accent,
                foregroundColor: start.color == null ? c.onAccent : Colors.white,
                icon: start.icon,
                label: start.label,
              ),
            ]),
      endActionPane: end.isEmpty
          ? null
          : ActionPane(motion: const DrawerMotion(), extentRatio: 0.27 * end.length, children: end),
      child: child,
    );
  }
}

/// Zeigt eine kurze Meldung (ersetzt eine eventuell noch sichtbare).
void showAppSnack(BuildContext context, String message, {SnackBarAction? action, bool error = false}) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;
  messenger.hideCurrentSnackBar();
  messenger.showSnackBar(SnackBar(
    content: Text(message),
    action: action,
    duration: action == null ? const Duration(seconds: 4) : const Duration(seconds: 5),
    backgroundColor: error ? AppColors.of(context).negative : null,
  ));
}

/// Lesbarer Text einer Ausnahme („Exception: …“ ohne Präfix).
String errorText(Object error) {
  final s = error.toString();
  return s.startsWith('Exception: ') ? s.substring(11) : s;
}

/// Führt [action] aus und zeigt Fehler als Snackbar statt sie zu verschlucken.
/// Liefert das Ergebnis oder `null` bei Fehler. Optional eine Erfolgsmeldung.
Future<T?> runGuarded<T>(BuildContext context, Future<T> Function() action, {String? success}) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  final errorColor = AppColors.of(context).negative;
  try {
    final result = await action();
    if (success != null && messenger != null) {
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(SnackBar(content: Text(success)));
    }
    return result;
  } catch (e, s) {
    debugPrint('Aktion fehlgeschlagen: $e\n$s');
    if (messenger != null) {
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(SnackBar(
        backgroundColor: errorColor,
        content: Text('Das hat nicht geklappt: ${errorText(e)}'),
      ));
    }
    return null;
  }
}

/// Löscht sofort und bietet 5 s lang „Rückgängig“ an. [onChanged] lädt die Ansicht neu
/// (nach dem Löschen und nach dem Wiederherstellen).
Future<void> deleteWithUndo(
  BuildContext context, {
  required String label,
  required Future<void> Function() delete,
  required Future<void> Function() restore,
  VoidCallback? onChanged,
}) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  final errorColor = AppColors.of(context).negative;
  try {
    await delete();
  } catch (e) {
    messenger?.showSnackBar(SnackBar(backgroundColor: errorColor, content: Text('Löschen fehlgeschlagen: ${errorText(e)}')));
    return;
  }
  onChanged?.call();
  if (messenger == null) return;
  messenger.hideCurrentSnackBar();
  messenger.showSnackBar(SnackBar(
    duration: const Duration(seconds: 5),
    content: Text('„$label“ gelöscht'),
    action: SnackBarAction(
      label: 'Rückgängig',
      onPressed: () async {
        try {
          await restore();
          onChanged?.call();
        } catch (e) {
          messenger.showSnackBar(SnackBar(backgroundColor: errorColor, content: Text('Wiederherstellen fehlgeschlagen: ${errorText(e)}')));
        }
      },
    ),
  ));
}

/// Öffnet ein Formular als Bottom-Sheet (kurze Formulare). Lange Formulare sind eigene Seiten.
Future<T?> showEditorSheet<T>(BuildContext context, WidgetBuilder builder) => showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: builder,
    );

/// Einheitliches Gerüst für Formulare im Bottom-Sheet: Titel, Felder, Speichern-Button.
class EditorSheet extends StatelessWidget {
  final String title;
  final List<Widget> children;
  final VoidCallback onSave;
  final String saveLabel;
  final GlobalKey<FormState>? formKey;
  const EditorSheet({
    super.key,
    required this.title,
    required this.children,
    required this.onSave,
    this.saveLabel = 'Speichern',
    this.formKey,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 16, 20, 16 + MediaQuery.viewInsetsOf(context).bottom),
      child: Form(
        key: formKey,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 16),
            ...children,
            const SizedBox(height: 20),
            ElevatedButton(onPressed: onSave, child: Text(saveLabel)),
          ]),
        ),
      ),
    );
  }
}
