import 'package:flutter/material.dart';
import 'package:frontend/core/ui/app_actions.dart';
import 'package:provider/provider.dart';
import 'package:frontend/features/auth/services/auth.dart';
import 'package:frontend/app/home_shell.dart';
import 'package:frontend/core/ui/app_logo.dart';
import 'package:frontend/core/ui/theme.dart';

class SignIn extends StatefulWidget {
  final Function toggleView;
  const SignIn({required this.toggleView, super.key});

  @override
  State<SignIn> createState() => _SignInState();
}

class _SignInState extends State<SignIn> {
  late final AuthService _auth = context.read<AuthService>();
  final _formKey = GlobalKey<FormState>();

  String email = '';
  String password = '';
  String error = '';
  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _canCheckBiometrics = false;
  @override
  void initState() {
    super.initState();
    _checkBiometrics();
  }


  Future<void> _checkBiometrics() async {
    final canCheck = await _auth.isBiometricsEnabled();
    if (mounted) setState(() => _canCheckBiometrics = canCheck);
    if (canCheck) {
      // Proactively trigger biometrics if enabled
      WidgetsBinding.instance.addPostFrameCallback((_) => _handleBiometricAuth());
    }
  }

  Future<void> _handleBiometricAuth() async {
    final user = await _auth.authenticateWithBiometrics();
    if (!mounted) return;
    if (user?.email != null) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => HomeShell(email: user!.email!)),
      );
    } else {
      setState(() => error = 'Biometrische Anmeldung fehlgeschlagen.');
    }
  }

  Future<void> _forgotPassword() async {
    final navigator = Navigator.of(context);
    final newEmail = await showDialog<String>(
      context: context,
      builder: (_) => _ResetPasswordDialog(auth: _auth, initialEmail: email.trim()),
    );
    if (newEmail == null || !mounted) return;
    navigator.pushReplacement(MaterialPageRoute(builder: (context) => HomeShell(email: newEmail)));
  }

  Future<void> _signIn() async {
    if (_formKey.currentState!.validate()) {
      setState(() { _isLoading = true; error = ''; });
      try {
        final result = await _auth.signInWithEmailAndPassword(email.trim(), password);
        if (!mounted) return;
        if (result == null) {
          final outdated = await _auth.hasOutdatedPassword(email.trim());
          final exists = outdated || await _auth.accountExists(email.trim());
          if (!mounted) return;
          setState(() {
            error = outdated
                ? 'Dein Konto stammt aus einer älteren App-Version – das alte Passwort lässt sich nicht mehr prüfen. '
                    'Lege über „Passwort vergessen?“ einfach ein neues fest; deine Daten bleiben erhalten.'
                : exists
                    ? 'Das Passwort stimmt nicht. Vergessen? Dann über „Passwort vergessen?“ neu festlegen.'
                    : 'Zu dieser E-Mail gibt es kein Konto. Bitte registrieren.';
            _isLoading = false;
          });
        } else {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (context) => HomeShell(email: email.trim())),
          );
        }
      } catch (e) {
        if (mounted) setState(() { error = 'Anmeldung fehlgeschlagen: ${errorText(e)}'; _isLoading = false; });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final theme = Theme.of(context);

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 40),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 40),
                // ─── Header ─────────────────────────────────────────────────
                Column(
                  children: [
                    const AppLogo(size: 72),
                    const SizedBox(height: 20),
                    Text('Willkommen zurück', style: theme.textTheme.headlineMedium),
                    const SizedBox(height: 6),
                    Text('Melde dich an, um weiterzumachen', style: theme.textTheme.bodySmall),
                  ],
                ),
                const SizedBox(height: 44),
                // ─── Email ───────────────────────────────────────────────────
                TextFormField(
                  decoration: InputDecoration(
                    labelText: 'E-Mail',
                    prefixIcon: Icon(Icons.mail_outline, color: c.accentText),
                  ),
                  keyboardType: TextInputType.emailAddress,
                  validator: (val) => val!.isEmpty ? 'Bitte gib deine E-Mail-Adresse ein' : null,
                  onChanged: (val) => setState(() => email = val),
                ),
                const SizedBox(height: 16),
                // ─── Password ────────────────────────────────────────────────
                TextFormField(
                  decoration: InputDecoration(
                    labelText: 'Passwort',
                    prefixIcon: Icon(Icons.lock_outline, color: c.accentText),
                    suffixIcon: IconButton(
                      icon: Icon(_obscurePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                      onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                    ),
                  ),
                  obscureText: _obscurePassword,
                  validator: (val) => val!.length < 6 ? 'Das Passwort muss mindestens 6 Zeichen lang sein' : null,
                  onChanged: (val) => setState(() => password = val),
                ),
                // ─── Error ───────────────────────────────────────────────────
                if (error.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: c.negative.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: c.negative.withValues(alpha: 0.3)),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.error_outline, color: c.negative, size: 18),
                        const SizedBox(width: 8),
                        Expanded(child: Text(error, style: TextStyle(color: c.negative, fontSize: 13))),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 28),
                // ─── Sign In Button ───────────────────────────────────────────
                ElevatedButton(
                  onPressed: _isLoading ? null : _signIn,
                  child: _isLoading
                      ? SizedBox(
                          height: 20, width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2, color: c.onAccent),
                        )
                      : const Text('Anmelden', style: TextStyle(fontSize: 16)),
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(onPressed: _isLoading ? null : _forgotPassword, child: const Text('Passwort vergessen?')),
                ),
                if (_canCheckBiometrics) ...[
                  const SizedBox(height: 16),
                  Center(
                    child: InkWell(
                      onTap: _handleBiometricAuth,
                      borderRadius: BorderRadius.circular(50),
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: c.accent.withValues(alpha: 0.14),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(Icons.fingerprint, size: 40, color: c.accentText),
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 20),
                // ─── Register Link ───────────────────────────────────────────
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text('Noch kein Konto? ', style: theme.textTheme.bodySmall),
                    TextButton(
                      onPressed: () => widget.toggleView(),
                      child: Text('Registrieren', style: TextStyle(color: c.accentText, fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Neues Passwort für ein lokales Konto festlegen (bestätigt per Gerätesperre bzw. bei
/// Konten aus älteren App-Versionen direkt). Liefert die E-Mail nach erfolgreicher Änderung.
class _ResetPasswordDialog extends StatefulWidget {
  final AuthService auth;
  final String initialEmail;
  const _ResetPasswordDialog({required this.auth, required this.initialEmail});

  @override
  State<_ResetPasswordDialog> createState() => _ResetPasswordDialogState();
}

class _ResetPasswordDialogState extends State<_ResetPasswordDialog> {
  final _formKey = GlobalKey<FormState>();
  late final _email = TextEditingController(text: widget.initialEmail);
  final _password = TextEditingController();
  final _repeat = TextEditingController();
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _repeat.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final email = _email.text.trim();
    final navigator = Navigator.of(context);
    if (!await widget.auth.accountExists(email)) {
      setState(() {
        _busy = false;
        _error = 'Zu dieser E-Mail gibt es kein Konto.';
      });
      return;
    }
    final outdated = await widget.auth.hasOutdatedPassword(email);
    final confirmed = outdated ? false : await widget.auth.confirmDeviceOwner();
    final result = await widget.auth.resetPassword(email, _password.text, deviceConfirmed: confirmed == true);
    if (!mounted) return;
    if (result == ResetResult.done) {
      navigator.pop(email);
      return;
    }
    setState(() {
      _busy = false;
      _error = confirmed == null
          ? 'Dein Gerät hat keine Displaysperre – richte eine PIN oder einen Fingerabdruck ein, um das Passwort zurückzusetzen.'
          : 'Bestätigung abgebrochen oder fehlgeschlagen.';
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return AlertDialog(
      title: const Text('Neues Passwort festlegen'),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('Deine Daten liegen nur auf diesem Gerät. Zur Sicherheit bestätigst du die Änderung mit deiner Displaysperre.',
                style: TextStyle(fontSize: 13)),
            const SizedBox(height: 12),
            TextFormField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(labelText: 'Email'),
              validator: (v) => (v ?? '').trim().isEmpty ? 'Bitte E-Mail eingeben' : null,
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _password,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Neues Passwort'),
              validator: (v) => (v ?? '').length < 6 ? 'Mindestens 6 Zeichen' : null,
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _repeat,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Passwort wiederholen'),
              validator: (v) => v != _password.text ? 'Passwörter stimmen nicht überein' : null,
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: TextStyle(color: c.negative, fontSize: 13)),
            ],
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: _busy ? null : () => Navigator.of(context).pop(), child: const Text('Abbrechen')),
        ElevatedButton(onPressed: _busy ? null : _submit, child: const Text('Speichern')),
      ],
    );
  }
}
