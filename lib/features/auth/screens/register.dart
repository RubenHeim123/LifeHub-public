import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:frontend/core/ui/app_actions.dart';
import 'package:frontend/features/auth/services/auth.dart';
import 'package:frontend/app/home_shell.dart';
import 'package:frontend/core/ui/app_logo.dart';
import 'package:frontend/core/ui/theme.dart';

class Register extends StatefulWidget {
  final Function toggleView;
  const Register({required this.toggleView, super.key});

  @override
  State<Register> createState() => _RegisterState();
}

class _RegisterState extends State<Register> {
  late final AuthService _auth = context.read<AuthService>();
  final _formKey = GlobalKey<FormState>();

  String email = '';
  String password = '';
  String error = '';
  bool _isLoading = false;
  bool _obscurePassword = true;

  Future<void> _register() async {
    if (_formKey.currentState!.validate()) {
      setState(() { _isLoading = true; error = ''; });
      try {
        await _auth.registerWithEmailAndPassword(email.trim(), password);
        if (mounted) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (context) => HomeShell(email: email.trim())),
          );
        }
      } catch (e) {
        final message = e is AccountExistsException ? e.toString() : 'Registrierung fehlgeschlagen: ${errorText(e)}';
        if (mounted) setState(() { error = message; _isLoading = false; });
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
                    Text('Konto erstellen', style: theme.textTheme.headlineMedium),
                    const SizedBox(height: 6),
                    Text('Leg ein Konto an, um loszulegen', style: theme.textTheme.bodySmall),
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
                  validator: (val) {
                    final v = (val ?? '').trim();
                    if (v.isEmpty) return 'Bitte gib deine E-Mail-Adresse ein';
                    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(v)) return 'Das sieht nicht nach einer E-Mail-Adresse aus';
                    return null;
                  },
                  onChanged: (val) => setState(() => email = val),
                ),
                const SizedBox(height: 16),
                // ─── Password ─────────────────────────────────────────────────
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
                // ─── Register Button ─────────────────────────────────────────
                ElevatedButton(
                  onPressed: _isLoading ? null : _register,
                  child: _isLoading
                      ? SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: c.onAccent))
                      : const Text('Registrieren', style: TextStyle(fontSize: 16)),
                ),
                const SizedBox(height: 20),
                // ─── Sign In Link ─────────────────────────────────────────────
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text('Bereits ein Konto? ', style: theme.textTheme.bodySmall),
                    TextButton(
                      onPressed: () => widget.toggleView(),
                      child: Text('Anmelden', style: TextStyle(color: c.accentText, fontWeight: FontWeight.bold)),
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
