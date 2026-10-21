import 'package:flutter/material.dart';
import 'package:frontend/core/ui/app_actions.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:frontend/features/auth/models/user.dart';
import 'package:frontend/features/auth/services/auth.dart';
import 'package:frontend/core/ui/dialogs.dart';
import 'package:frontend/features/auth/screens/wrapper.dart';
import 'package:frontend/features/finance/repositories/user_repository.dart';
import 'package:frontend/features/finance/screens/sync_hub_screen.dart';
import 'package:frontend/core/ui/modern_appbar.dart';
import 'package:frontend/core/ui/theme.dart';
import 'package:frontend/app/theme_mode.dart';
import 'package:frontend/features/profile/widgets/ai_key_card.dart';
import 'package:frontend/features/profile/widgets/calendar_sync_card.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key, required this.user});
  final UserModel user;

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  AppColors get c => AppColors.of(context);
  final _formKey = GlobalKey<FormState>();

  late TextEditingController _displayNameController;
  late TextEditingController _ageController;
  late TextEditingController _emailController;
  late TextEditingController _phoneNumberController;

  bool _isSaving = false;
  bool _useBiometrics = false;
  late final AuthService _authService = context.read<AuthService>();

  @override
  void initState() {
    super.initState();
    _displayNameController = TextEditingController(text: widget.user.displayName);
    _ageController = TextEditingController(text: widget.user.age?.toString());
    _emailController = TextEditingController(text: widget.user.email);
    _phoneNumberController = TextEditingController(text: widget.user.phonenumber);
    _loadBiometricPref();
  }

  Future<void> _loadBiometricPref() async {
    final enabled = await _authService.isBiometricsEnabled();
    if (mounted) setState(() => _useBiometrics = enabled);
  }

  @override
  void dispose() {
    _displayNameController.dispose();
    _ageController.dispose();
    _emailController.dispose();
    _phoneNumberController.dispose();
    super.dispose();
  }

  Future<void> _showChangePasswordDialog() async {
    final changed = await showDialog<bool>(
      context: context,
      builder: (_) => _ChangePasswordDialog(user: widget.user, auth: _authService),
    );
    if (changed == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Passwort geändert')));
    }
  }

  Future<void> _updateUser() async {
    if (_formKey.currentState!.validate()) {
      setState(() => _isSaving = true);
      final messenger = ScaffoldMessenger.of(context);
      final navigator = Navigator.of(context);
      final users = context.read<UserRepository>();
      try {
        final updatedUser = UserModel(
          uid: widget.user.uid,
          displayName: _displayNameController.text.isEmpty ? null : _displayNameController.text,
          age: _ageController.text.isEmpty ? null : int.tryParse(_ageController.text),
          email: _emailController.text.trim(),
          phonenumber: _phoneNumberController.text.isEmpty ? null : _phoneNumberController.text,
          createdTime: widget.user.createdTime,
          // Sonst würden XP und Biometrie-Einstellung beim Speichern zurückgesetzt.
          experiencePoints: widget.user.experiencePoints,
          isBiometricEnabled: widget.user.isBiometricEnabled,
        );
        final oldEmail = widget.user.email;
        if (updatedUser.email != oldEmail) {
          final existing = await users.getUserFromEmail(updatedUser.email!);
          if (existing != null && existing.uid != updatedUser.uid) {
            throw Exception('Diese E-Mail wird bereits verwendet.');
          }
        }
        await users.updateUser(updatedUser);
        if (oldEmail != null && oldEmail != updatedUser.email) {
          await _authService.onEmailChanged(oldEmail, updatedUser.email!);
        }
        messenger.showSnackBar(
          SnackBar(content: Text('Profil erfolgreich aktualisiert'), backgroundColor: c.positive),
        );
        navigator.pop(updatedUser);
      } catch (e) {
        messenger.showSnackBar(
          SnackBar(content: Text('Speichern fehlgeschlagen: ${errorText(e)}'), backgroundColor: c.negative),
        );
      } finally {
        if (mounted) setState(() => _isSaving = false);
      }
    }
  }

  Future<void> _confirmDelete(BuildContext context) async {
    final users = context.read<UserRepository>();
    final deleted = await confirmAndDelete(
      context,
      title: 'Konto löschen',
      message: 'Alle deine Daten werden gelöscht. Diese Aktion kann nicht rückgängig gemacht werden.',
      action: () async {
        await users.deleteUser(widget.user.uid);
        await _authService.forgetUser(widget.user.email);
      },
    );
    if (deleted && context.mounted) await Wrapper.signOut(context);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: ModernAppBar(
        title: 'Profil',
        customActions: [
          IconButton(
            icon: const Icon(Icons.sync_rounded),
            tooltip: 'Sichern & Synchronisieren',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => SyncHubScreen(user: widget.user)),
            ),
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            children: [
              // ─── Avatar Header ──────────────────────────────────────────────
              _buildProfileHeader(theme),
              Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // ─── Personal Info ─────────────────────────────────────────
                    _sectionLabel('Persönliche Daten', theme),
                    const SizedBox(height: 10),
                    _inputField(icon: Icons.person_outline, label: 'Name', controller: _displayNameController,
                      validator: (v) => v!.isNotEmpty && v.length < 2 ? 'Mindestens 2 Zeichen' : null),
                    _inputField(icon: Icons.cake_outlined, label: 'Alter', controller: _ageController,
                      keyboardType: TextInputType.number,
                      validator: (v) { if (v!.isNotEmpty) { final a = int.tryParse(v); if (a == null || a <= 0) return 'Ungültiges Alter'; } return null; }),
                    _inputField(icon: Icons.mail_outline, label: 'E-Mail', controller: _emailController,
                      keyboardType: TextInputType.emailAddress,
                      validator: (v) { if (v!.trim().isEmpty) return 'Bitte E-Mail-Adresse eingeben'; if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(v.trim())) return 'Ungültige E-Mail-Adresse'; return null; }),
                    _inputField(icon: Icons.phone_outlined, label: 'Telefonnummer', controller: _phoneNumberController,
                      keyboardType: TextInputType.phone,
                      validator: (v) { if (v!.isNotEmpty && !RegExp(r'^\+?1?\d{9,15}$').hasMatch(v)) return 'Ungültige Telefonnummer'; return null; }),
                    OutlinedButton.icon(
                      onPressed: _showChangePasswordDialog,
                      icon: const Icon(Icons.lock_outline),
                      label: const Text('Passwort ändern'),
                    ),
                    const SizedBox(height: 20),

                    // ─── Security ──────────────────────────────────────────────
                    _sectionLabel('Sicherheit', theme),
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                      decoration: AppTheme.cardDecoration(context),
                      child: SwitchListTile(
                        title: const Text('Biometische Anmeldung (Fingerabdruck)', style: TextStyle(fontSize: 14)),
                        secondary: Icon(Icons.fingerprint, color: c.accentText),
                        value: _useBiometrics,
                        activeColor: c.accent,
                        onChanged: (val) async {
                          setState(() => _useBiometrics = val);
                          await _authService.setBiometricsEnabled(val, email: widget.user.email);
                        },
                      ),
                    ),
                    const SizedBox(height: 20),

                    // ─── KI ─────────────────────────────────────────────────────
                    _sectionLabel('KI', theme),
                    const SizedBox(height: 10),
                    const AiKeyCard(),
                    const SizedBox(height: 20),

                    // ─── Kalender ───────────────────────────────────────────────
                    _sectionLabel('Kalender', theme),
                    const SizedBox(height: 10),
                    CalendarSyncCard(userid: widget.user.uid),
                    const SizedBox(height: 20),

                    // ─── Appearance ────────────────────────────────────────────
                    _sectionLabel('Erscheinungsbild', theme),
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.all(4),
                      decoration: AppTheme.cardDecoration(context),
                      child: ValueListenableBuilder<ThemeMode>(
                        valueListenable: themeModeNotifier,
                        builder: (context, currentMode, _) {
                          return Row(
                            children: [
                              _themeModeButton(ThemeMode.light, Icons.light_mode_outlined, 'Hell', currentMode, context),
                              _themeModeButton(ThemeMode.system, Icons.brightness_auto_outlined, 'System', currentMode, context),
                              _themeModeButton(ThemeMode.dark, Icons.dark_mode_outlined, 'Dunkel', currentMode, context),
                            ],
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 20),

                    const SizedBox(height: 24),

                    // ─── Save / Delete ─────────────────────────────────────────
                    ElevatedButton.icon(
                      onPressed: _isSaving ? null : _updateUser,
                      icon: _isSaving
                          ? SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: c.onAccent))
                          : const Icon(Icons.save_outlined),
                      label: Text(_isSaving ? 'Wird gespeichert...' : 'Profil aktualisieren'),
                    ),
                    const SizedBox(height: 10),
                    OutlinedButton.icon(
                      onPressed: () => _confirmDelete(context),
                      icon: const Icon(Icons.delete_outline),
                      label: const Text('Konto löschen'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: c.negative,
                        side: BorderSide(color: c.negative, width: 1.5),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildProfileHeader(ThemeData theme) {
    final initials = widget.user.displayName?.isNotEmpty == true
        ? widget.user.displayName!.substring(0, 1).toUpperCase()
        : widget.user.email?.substring(0, 1).toUpperCase() ?? 'U';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [c.accent, c.accent.withValues(alpha: 0.75)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(28),
          bottomRight: Radius.circular(28),
        ),
      ),
      child: Column(
        children: [
          CircleAvatar(
            radius: 44,
            backgroundColor: c.onAccent.withValues(alpha: 0.12),
            child: Text(initials, style: TextStyle(fontSize: 34, fontWeight: FontWeight.bold, color: c.onAccent)),
          ),
          const SizedBox(height: 14),
          Text(widget.user.displayName ?? 'Kein Name',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: c.onAccent)),
          const SizedBox(height: 4),
          Text(widget.user.email ?? '', style: TextStyle(fontSize: 14, color: c.onAccent.withValues(alpha: 0.75))),
          if (widget.user.createdTime != null) ...[
            const SizedBox(height: 6),
            Text('Mitglied seit ${DateFormat('MM.yyyy').format(widget.user.createdTime!)}',
                style: TextStyle(fontSize: 12, color: c.onAccent.withValues(alpha: 0.6))),
          ],
        ],
      ),
    );
  }

  Widget _sectionLabel(String label, ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Text(label, style: theme.textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w700, letterSpacing: 0.8)),
    );
  }

  Widget _inputField({
    required IconData icon,
    required String label,
    required TextEditingController controller,
    required String? Function(String?) validator,
    TextInputType? keyboardType,
    bool enabled = true,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        controller: controller,
        enabled: enabled,
        keyboardType: keyboardType,
        validator: validator,
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: Icon(icon, color: c.accentText, size: 20),
        ),
      ),
    );
  }

  Widget _themeModeButton(ThemeMode mode, IconData icon, String label, ThemeMode currentMode, BuildContext context) {
    final isSelected = currentMode == mode;
    return Expanded(
      child: GestureDetector(
        onTap: () => saveThemePref(mode),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          margin: const EdgeInsets.all(4),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: isSelected ? c.accent : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 22, color: isSelected ? c.onAccent : Theme.of(context).iconTheme.color),
              const SizedBox(height: 4),
              Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600,
                  color: isSelected ? c.onAccent : Theme.of(context).textTheme.bodySmall?.color)),
            ],
          ),
        ),
      ),
    );
  }
}

class _ChangePasswordDialog extends StatefulWidget {
  final UserModel user;
  final AuthService auth;
  const _ChangePasswordDialog({required this.user, required this.auth});

  @override
  State<_ChangePasswordDialog> createState() => _ChangePasswordDialogState();
}

class _ChangePasswordDialogState extends State<_ChangePasswordDialog> {
  final _formKey = GlobalKey<FormState>();
  final _current = TextEditingController();
  final _next = TextEditingController();
  final _repeat = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _current.dispose();
    _next.dispose();
    _repeat.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final navigator = Navigator.of(context);
    final ok = await widget.auth.changePassword(widget.user, _current.text, _next.text);
    if (ok) {
      navigator.pop(true);
    } else if (mounted) {
      setState(() {
        _busy = false;
        _error = 'Aktuelles Passwort ist falsch.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Passwort ändern'),
      content: Form(
        key: _formKey,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextFormField(
            controller: _current,
            obscureText: true,
            decoration: InputDecoration(labelText: 'Aktuelles Passwort', errorText: _error),
            validator: (v) => (v == null || v.isEmpty) ? 'Erforderlich' : null,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _next,
            obscureText: true,
            decoration: const InputDecoration(labelText: 'Neues Passwort'),
            validator: (v) => (v == null || v.length < 6) ? 'Mindestens 6 Zeichen' : null,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _repeat,
            obscureText: true,
            decoration: const InputDecoration(labelText: 'Neues Passwort wiederholen'),
            validator: (v) => v != _next.text ? 'Passwörter stimmen nicht überein' : null,
          ),
        ]),
      ),
      actions: [
        TextButton(onPressed: _busy ? null : () => Navigator.of(context).pop(false), child: const Text('Abbrechen')),
        ElevatedButton(
          onPressed: _busy ? null : _submit,
          child: _busy
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Ändern'),
        ),
      ],
    );
  }
}
