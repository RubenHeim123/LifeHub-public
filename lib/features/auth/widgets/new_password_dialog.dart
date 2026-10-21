import 'package:flutter/material.dart';

import 'package:frontend/core/ui/app_actions.dart';
import 'package:frontend/features/auth/models/user.dart';
import 'package:frontend/features/auth/services/auth.dart';

/// Fordert ein neues Passwort an, wenn das gespeicherte aus einer früheren
/// App-Version stammt und nicht mehr geprüft werden kann. Liefert `true`, wenn gesetzt.
Future<bool> showNewPasswordDialog(BuildContext context, {required AuthService auth, required UserModel user}) async {
  final result = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _NewPasswordDialog(auth: auth, user: user),
  );
  return result ?? false;
}

class _NewPasswordDialog extends StatefulWidget {
  final AuthService auth;
  final UserModel user;
  const _NewPasswordDialog({required this.auth, required this.user});

  @override
  State<_NewPasswordDialog> createState() => _NewPasswordDialogState();
}

class _NewPasswordDialogState extends State<_NewPasswordDialog> {
  final _formKey = GlobalKey<FormState>();
  final _password = TextEditingController();
  final _repeat = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _password.dispose();
    _repeat.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _busy = true);
    final navigator = Navigator.of(context);
    final ok = await runGuarded(context, () => widget.auth.setPasswordForOutdatedAccount(widget.user, _password.text));
    if (ok == null) {
      if (mounted) setState(() => _busy = false);
      return;
    }
    navigator.pop(ok);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Neues Passwort festlegen'),
      content: Form(
        key: _formKey,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('Dein Passwort stammt aus einer früheren Version der App. '
              'Bitte lege ein neues fest, damit du dich auch nach dem Abmelden wieder anmelden kannst.'),
          const SizedBox(height: 16),
          TextFormField(
            controller: _password,
            obscureText: true,
            decoration: const InputDecoration(labelText: 'Neues Passwort'),
            validator: (v) => (v == null || v.length < 6) ? 'Mindestens 6 Zeichen' : null,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _repeat,
            obscureText: true,
            decoration: const InputDecoration(labelText: 'Neues Passwort wiederholen'),
            validator: (v) => v != _password.text ? 'Passwörter stimmen nicht überein' : null,
          ),
        ]),
      ),
      actions: [
        TextButton(onPressed: _busy ? null : () => Navigator.of(context).pop(false), child: const Text('Später')),
        ElevatedButton(onPressed: _busy ? null : _submit, child: const Text('Speichern')),
      ],
    );
  }
}
