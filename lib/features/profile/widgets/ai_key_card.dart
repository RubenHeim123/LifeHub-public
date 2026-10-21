import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:frontend/core/ui/app_actions.dart';
import 'package:frontend/core/ui/app_ui.dart';
import 'package:frontend/core/ui/theme.dart';
import 'package:frontend/features/fitness/services/meal_photo_ai.dart';

/// Profil: Anthropic-API-Schlüssel für „Gericht fotografieren (KI-Schätzung)“ eintragen, testen, entfernen.
class AiKeyCard extends StatefulWidget {
  const AiKeyCard({super.key});

  @override
  State<AiKeyCard> createState() => _AiKeyCardState();
}

class _AiKeyCardState extends State<AiKeyCard> {
  late final AiKeyStore _keys = context.read<AiKeyStore>();
  final _field = TextEditingController();
  bool? _hasKey;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _keys.read().then((k) {
      if (mounted) setState(() => _hasKey = k != null);
    });
  }

  @override
  void dispose() {
    _field.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final key = _field.text.trim();
    if (key.isEmpty) return;
    setState(() => _busy = true);
    final problem = await context.read<MealPhotoAi>().checkKey(key);
    if (!mounted) return;
    setState(() => _busy = false);
    if (problem != null) {
      showAppSnack(context, 'Schlüssel nicht gespeichert: $problem', error: true);
      return;
    }
    await _keys.save(key);
    _field.clear();
    if (!mounted) return;
    setState(() => _hasKey = true);
    showAppSnack(context, 'Schlüssel geprüft und gespeichert');
  }

  Future<void> _remove() async {
    await _keys.clear();
    if (mounted) setState(() => _hasKey = false);
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final t = Theme.of(context).textTheme;
    return AppCard(
      padding: const EdgeInsets.all(14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.auto_awesome_rounded, color: c.accentText),
          const SizedBox(width: 10),
          Expanded(child: Text('KI-Schätzung (Fotos)', style: t.titleSmall)),
          if (_hasKey == true) Text('eingerichtet', style: t.labelMedium?.copyWith(color: c.positive)),
        ]),
        const SizedBox(height: 6),
        Text(
          'Für „Gericht fotografieren“ in der Ernährung. Das Foto wird an Anthropic (Claude) geschickt; '
          'je Foto entstehen kleine Kosten auf deinem eigenen API-Konto. Der Schlüssel bleibt nur auf diesem Gerät.',
          style: t.bodySmall?.copyWith(color: c.muted),
        ),
        const SizedBox(height: 10),
        if (_hasKey == true)
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(onPressed: _remove, icon: const Icon(Icons.key_off_rounded), label: const Text('Schlüssel entfernen')),
          )
        else ...[
          TextField(
            controller: _field,
            obscureText: true,
            autocorrect: false,
            decoration: const InputDecoration(labelText: 'Anthropic-API-Schlüssel', hintText: 'sk-ant-…'),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.icon(
              onPressed: _busy ? null : _save,
              icon: _busy ? const SizedBox.square(dimension: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.check_rounded),
              label: const Text('Testen und speichern'),
            ),
          ),
        ],
      ]),
    );
  }
}
