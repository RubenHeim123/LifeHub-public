import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:frontend/core/ui/icon_collection.dart';
import 'package:frontend/core/ui/theme.dart';

/// Kopfbereich der Finanz-Formulare (Konto, Kategorie, Transaktion …).
class FormHeader extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Widget? trailing;
  final Widget? bottom;

  const FormHeader({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.trailing,
    this.bottom,
  });

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [c.accent, c.accent.withValues(alpha: 0.85)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(24)),
      ),
      child: Column(children: [
        Row(children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
            child: Icon(icon, size: 32, color: c.accentText),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: c.onAccent)),
              const SizedBox(height: 6),
              Text(subtitle, style: TextStyle(color: c.onAccent.withValues(alpha: 0.8))),
            ]),
          ),
          if (trailing != null) DefaultTextStyle.merge(style: TextStyle(color: c.onAccent), child: trailing!),
        ]),
        if (bottom != null) ...[
          const SizedBox(height: 16),
          DefaultTextStyle.merge(style: TextStyle(color: c.onAccent), child: bottom!),
        ],
      ]),
    );
  }
}

/// Karte mit Icon und Beschriftung für ein Formularfeld.
class FormFieldCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final Widget child;

  const FormFieldCard({super.key, required this.icon, required this.label, required this.child});

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: AppTheme.cardDecoration(context),
      child: Row(children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: c.accent.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(10)),
          child: Icon(icon, color: c.accentText, size: 22),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: Theme.of(context).textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            child,
          ]),
        ),
      ]),
    );
  }
}

/// Eingabe ohne eigenen Rahmen – die [FormFieldCard] ist der Rahmen.
const InputDecoration bareInputDecoration = InputDecoration(
  border: InputBorder.none,
  enabledBorder: InputBorder.none,
  focusedBorder: InputBorder.none,
  filled: false,
  isDense: true,
  contentPadding: EdgeInsets.zero,
);

/// Speichern / Abbrechen / (beim Bearbeiten) Löschen.
class FormActions extends StatelessWidget {
  final bool isNew;
  final bool busy;
  final VoidCallback onSave;
  final VoidCallback? onDelete;

  const FormActions({super.key, required this.isNew, required this.onSave, this.onDelete, this.busy = false});

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(12));
    final save = ElevatedButton.icon(
      icon: busy
          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
          : const Icon(Icons.save),
      label: Text(isNew ? 'Hinzufügen' : 'Speichern'),
      style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14), shape: shape),
      onPressed: busy ? null : onSave,
    );
    final cancel = OutlinedButton(
      onPressed: busy ? null : () => Navigator.of(context).pop(),
      style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20), shape: shape),
      child: const Text('Abbrechen'),
    );
    final delete = !isNew && onDelete != null
        ? OutlinedButton.icon(
            onPressed: busy ? null : onDelete,
            icon: Icon(Icons.delete, color: c.negative),
            label: Text('Löschen', style: TextStyle(color: c.negative)),
            style: OutlinedButton.styleFrom(
              side: BorderSide(color: c.negative),
              padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
              shape: shape,
            ),
          )
        : null;
    if (delete == null) {
      return Row(children: [Expanded(child: save), const SizedBox(width: 12), cancel]);
    }
    return LayoutBuilder(builder: (context, constraints) {
      // Drei Knöpfe passen auf schmalen Handys mit großer Schrift nicht in eine Zeile:
      // dann Speichern oben, Abbrechen und Löschen darunter.
      if (constraints.maxWidth >= 420) {
        return Row(children: [Expanded(child: save), const SizedBox(width: 12), cancel, const SizedBox(width: 12), delete]);
      }
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        save,
        const SizedBox(height: 10),
        Row(children: [Expanded(child: cancel), const SizedBox(width: 12), Expanded(child: delete)]),
      ]);
    });
  }
}

/// Icon-Auswahl für Konten, Kategorien und Habits aus [iconCollection]. [controller] hält den Icon-Namen
/// (Schlüssel der Sammlung), [onPicked] bekommt Codepoint und Schriftfamilie des gewählten Icons.
class IconPickerField extends StatelessWidget {
  final TextEditingController controller;
  final void Function(int codePoint, String fontFamily) onPicked;
  final String label;

  const IconPickerField({super.key, required this.controller, required this.onPicked, this.label = 'Icon auswählen'});

  Future<void> _pick(BuildContext context) async {
    final name = await showDialog<String>(context: context, builder: (_) => _IconPickerDialog(selected: controller.text));
    if (name == null) return;
    final icon = iconCollection[name]!;
    controller.text = name;
    onPicked(icon.codePoint, icon.fontFamily ?? 'MaterialIcons');
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return FormFieldCard(
      icon: Icons.category_outlined,
      label: label,
      child: ValueListenableBuilder<TextEditingValue>(
        valueListenable: controller,
        builder: (context, value, _) {
          final icon = iconCollection[value.text];
          return InkWell(
            onTap: () => _pick(context),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(children: [
                Icon(icon ?? Icons.apps, color: c.accentText),
                const SizedBox(width: 12),
                Expanded(child: Text(icon == null ? 'Icon wählen' : 'Icon ändern')),
                Icon(Icons.chevron_right_rounded, color: c.dim),
              ]),
            ),
          );
        },
      ),
    );
  }
}

class _IconPickerDialog extends StatefulWidget {
  final String selected;
  const _IconPickerDialog({required this.selected});

  @override
  State<_IconPickerDialog> createState() => _IconPickerDialogState();
}

class _IconPickerDialogState extends State<_IconPickerDialog> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final words = _query.toLowerCase().split(RegExp(r'\s+')).where((w) => w.isNotEmpty);
    final names = [
      for (final name in iconCollection.keys)
        if (words.every(name.replaceAll('_', ' ').contains)) name,
    ];
    return AlertDialog(
      title: const Text('Wähle ein Icon'),
      content: SizedBox(
        width: double.maxFinite,
        height: 360,
        child: Column(children: [
          TextField(
            decoration: const InputDecoration(prefixIcon: Icon(Icons.search_rounded), hintText: 'Icon suchen (englisch, z. B. home)'),
            onChanged: (v) => setState(() => _query = v),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: names.isEmpty
                ? Center(child: Text('Kein Icon gefunden', style: TextStyle(color: c.muted)))
                : GridView.count(
                    crossAxisCount: 5,
                    children: [
                      for (final name in names)
                        IconButton(
                          tooltip: name.replaceAll('_', ' '),
                          isSelected: name == widget.selected,
                          color: name == widget.selected ? c.accentText : null,
                          icon: Icon(iconCollection[name]),
                          onPressed: () => Navigator.of(context).pop(name),
                        ),
                    ],
                  ),
          ),
        ]),
      ),
      actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Abbrechen'))],
    );
  }
}

class DateField extends StatelessWidget {
  final String label;
  final DateTime? value;
  final ValueChanged<DateTime> onChanged;
  final bool required;
  final DateTime? firstDate;
  final IconData icon;

  /// Wenn gesetzt, erscheint bei gewähltem Datum ein Knopf zum Entfernen.
  final VoidCallback? onCleared;

  const DateField({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.required = true,
    this.firstDate,
    this.icon = Icons.calendar_today,
    this.onCleared,
  });

  @override
  Widget build(BuildContext context) {
    final text = value == null ? '' : DateFormat('dd.MM.yyyy').format(value!);
    final field = FormFieldCard(
      icon: icon,
      label: label,
      child: GestureDetector(
        onTap: () async {
          final picked = await showDatePicker(
            context: context,
            initialDate: value ?? DateTime.now(),
            firstDate: firstDate ?? DateTime(2000),
            lastDate: DateTime(2301),
          );
          if (picked != null) onChanged(picked);
        },
        child: AbsorbPointer(
          child: TextFormField(
            // Key erzwingt neuen Feldzustand, wenn sich das Datum von außen ändert.
            key: ValueKey(text),
            initialValue: text,
            readOnly: true,
            decoration: bareInputDecoration.copyWith(hintText: required ? null : 'Optional'),
            validator: required ? (_) => value == null ? '$label erforderlich' : null : null,
          ),
        ),
      ),
    );
    if (onCleared == null || value == null) return field;
    return Stack(children: [
      field,
      Positioned(
        right: 4,
        top: 4,
        child: IconButton(tooltip: '$label entfernen', icon: const Icon(Icons.close_rounded, size: 18), onPressed: onCleared),
      ),
    ]);
  }
}
