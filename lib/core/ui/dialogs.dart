import 'package:flutter/material.dart';
import 'package:frontend/core/ui/app_actions.dart';
import 'package:frontend/core/ui/theme.dart';

/// Fragt nach Bestätigung für eine zerstörende Aktion. Liefert `true` nur bei "Löschen".
Future<bool> confirmDestructive(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'Löschen',
}) async {
  final c = AppColors.of(context);
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Row(children: [
        Icon(Icons.warning_amber_outlined, color: c.negative),
        const SizedBox(width: 8),
        Expanded(child: Text(title)),
      ]),
      content: Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Abbrechen')),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: c.negative, foregroundColor: Colors.white),
          onPressed: () => Navigator.of(ctx).pop(true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return confirmed ?? false;
}

/// Bestätigen, dann [action] ausführen und Ergebnis per SnackBar melden.
/// Liefert `true`, wenn gelöscht wurde. Fehler werden angezeigt statt geworfen.
Future<bool> confirmAndDelete(
  BuildContext context, {
  required String title,
  required String message,
  required Future<void> Function() action,
  String? successMessage,
}) async {
  if (!await confirmDestructive(context, title: title, message: message)) return false;
  if (!context.mounted) return false;
  final messenger = ScaffoldMessenger.of(context);
  try {
    await action();
    if (successMessage != null) messenger.showSnackBar(SnackBar(content: Text(successMessage)));
    return true;
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text('Löschen fehlgeschlagen: ${errorText(e)}')));
    return false;
  }
}

/// Ein Eingabefeld für [showTextFieldsDialog].
class DialogField {
  final String label;
  final String? initial;
  final bool required;
  const DialogField(this.label, {this.initial, this.required = false});
}

/// Dialog mit einem oder mehreren Textfeldern. Liefert die (getrimmten) Werte in der
/// Reihenfolge von [fields], leere optionale Felder als `null` – oder `null` bei Abbruch.
Future<List<String?>?> showTextFieldsDialog(
  BuildContext context, {
  required String title,
  required List<DialogField> fields,
  String confirmLabel = 'Speichern',
}) {
  return showDialog<List<String?>>(
    context: context,
    builder: (_) => _TextFieldsDialog(title: title, fields: fields, confirmLabel: confirmLabel),
  );
}

class _TextFieldsDialog extends StatefulWidget {
  final String title;
  final List<DialogField> fields;
  final String confirmLabel;
  const _TextFieldsDialog({required this.title, required this.fields, required this.confirmLabel});

  @override
  State<_TextFieldsDialog> createState() => _TextFieldsDialogState();
}

class _TextFieldsDialogState extends State<_TextFieldsDialog> {
  final _formKey = GlobalKey<FormState>();
  late final _controllers = [for (final f in widget.fields) TextEditingController(text: f.initial ?? '')];

  @override
  void dispose() {
    for (final c in _controllers) {
      c.dispose();
    }
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.of(context).pop([
      for (final c in _controllers) c.text.trim().isEmpty ? null : c.text.trim(),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: Form(
        key: _formKey,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          for (var i = 0; i < widget.fields.length; i++) ...[
            if (i > 0) const SizedBox(height: 12),
            TextFormField(
              controller: _controllers[i],
              autofocus: i == 0,
              decoration: InputDecoration(labelText: widget.fields[i].label),
              textInputAction: i == widget.fields.length - 1 ? TextInputAction.done : TextInputAction.next,
              onFieldSubmitted: i == widget.fields.length - 1 ? (_) => _submit() : null,
              validator: widget.fields[i].required
                  ? (v) => (v == null || v.trim().isEmpty) ? 'Erforderlich' : null
                  : null,
            ),
          ],
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Abbrechen')),
        ElevatedButton(onPressed: _submit, child: Text(widget.confirmLabel)),
      ],
    );
  }
}
