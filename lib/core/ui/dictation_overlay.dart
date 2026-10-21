import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:frontend/core/services/dictation_service.dart';
import 'package:frontend/core/ui/app_actions.dart';
import 'package:frontend/core/ui/theme.dart';

/// Mikrofon-Knopf über der Tastatur für **jedes** fokussierte Eingabefeld der App.
/// Diktierter Text wird an der Cursorposition eingefügt – wie getippt, also mit
/// Formattern, `onChanged` und Validierung. Passwort- und schreibgeschützte Felder bleiben aus.
///
/// Wird einmal über `MaterialApp.builder` um den Navigator gelegt.
class DictationOverlay extends StatefulWidget {
  final Widget child;
  const DictationOverlay({super.key, required this.child});

  /// Der Mikrofon-Knopf (für Tests).
  static const micKey = Key('dictation-mic');

  /// Platz über der Tastatur, den der Knopf belegt.
  static const barHeight = 64.0;

  @override
  State<DictationOverlay> createState() => _DictationOverlayState();
}

class _DictationOverlayState extends State<DictationOverlay> {
  EditableTextState? _field;
  EditableTextState? _target; // Feld, in das gerade diktiert wird
  bool _listening = false;
  String _partial = '';
  bool _heard = false; // in diesem Diktat schon etwas eingefügt

  @override
  void initState() {
    super.initState();
    FocusManager.instance.addListener(_onFocusChange);
  }

  @override
  void dispose() {
    FocusManager.instance.removeListener(_onFocusChange);
    if (_listening) context.read<DictationService>().stop();
    super.dispose();
  }

  void _onFocusChange() {
    final state = FocusManager.instance.primaryFocus?.context?.findAncestorStateOfType<EditableTextState>();
    final field = state != null && state.mounted && !state.widget.obscureText && !state.widget.readOnly ? state : null;
    if (field != _field && mounted) setState(() => _field = field);
  }

  Future<void> _toggle() async {
    final dictation = context.read<DictationService>();
    if (_listening) {
      await dictation.stop();
      return;
    }
    final target = _field;
    if (target == null) return;
    setState(() {
      _target = target;
      _listening = true;
      _partial = '';
      _heard = false;
    });
    final ok = await dictation.start(
      onResult: (text, isFinal) {
        if (!mounted) return;
        if (isFinal) {
          _insert(text);
        } else {
          setState(() => _partial = text);
        }
      },
      onDone: () {
        if (!mounted) return;
        _insert(_partial); // ohne Endergebnis gestoppt: den letzten Zwischenstand übernehmen
        setState(() {
          _listening = false;
          _target = null;
        });
        if (!_heard) showAppSnack(context, 'Nichts verstanden – tippe aufs Mikrofon und sprich noch einmal.');
      },
    );
    if (!ok && mounted) {
      setState(() {
        _listening = false;
        _target = null;
      });
      showAppSnack(context, 'Diktieren ist nicht verfügbar – bitte den Mikrofon-Zugriff erlauben.', error: true);
    }
  }

  /// Fügt [text] an der Cursorposition ein (bzw. ersetzt die Markierung), mit passenden Leerzeichen.
  void _insert(String text) {
    final target = _target;
    var words = text.trim();
    setState(() => _partial = '');
    if (target == null || !target.mounted || words.isEmpty) return;
    _heard = true;

    final value = target.textEditingValue;
    final sel = value.selection.isValid ? value.selection : TextSelection.collapsed(offset: value.text.length);
    final before = value.text.substring(0, sel.start);
    final after = value.text.substring(sel.end);
    final sentenceStart = before.trim().isEmpty || RegExp(r'[.!?]\s*$').hasMatch(before);
    if (sentenceStart) words = words[0].toUpperCase() + words.substring(1);
    if (before.isNotEmpty && !RegExp(r'\s$').hasMatch(before)) words = ' $words';
    if (after.isNotEmpty && !RegExp(r'^[\s.,!?]').hasMatch(after)) words = '$words ';

    target.userUpdateTextEditingValue(
      TextEditingValue(
        text: before + words + after,
        selection: TextSelection.collapsed(offset: before.length + words.length),
      ),
      SelectionChangedCause.keyboard,
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final show = _field != null || _listening;
    final mq = MediaQuery.of(context);
    // Ohne Tastatur liegt unten die System-Navigationsleiste (mit Tastatur ist `padding.bottom` 0).
    final bottomBar = mq.padding.bottom;
    return Stack(children: [
      // Solange der Knopf da ist, gilt er als Teil der Tastatur: Inhalte, das aktive Feld und
      // schwebende Knöpfe rücken darüber, statt verdeckt zu werden. Der MediaQuery bleibt immer
      // im Baum, damit der Navigator darunter seinen Zustand behält.
      MediaQuery(
        data: mq.copyWith(viewInsets: mq.viewInsets.copyWith(bottom: mq.viewInsets.bottom + (show ? DictationOverlay.barHeight + bottomBar : 0))),
        child: widget.child,
      ),
      if (show)
        Positioned(
          left: 12,
          right: 12,
          bottom: mq.viewInsets.bottom + bottomBar + 8,
          // Gehört zum Textfeld: Antippen nimmt dem Feld nicht den Fokus.
          child: TextFieldTapRegion(
            child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              // Eigener Semantik-Knoten: sonst landet „Diktieren“ auf dem Wurzelknoten der ganzen App.
              Semantics(
                container: true,
                button: true,
                label: _listening ? 'Diktat beenden' : 'Diktieren',
                child: Material(
                  color: _listening ? c.negative : c.accent,
                  shape: const CircleBorder(),
                  elevation: 4,
                  child: InkWell(
                    key: DictationOverlay.micKey,
                    customBorder: const CircleBorder(),
                    onTap: _toggle,
                    // Kein Tooltip: der braucht das Overlay des Navigators, und der liegt hier darunter.
                    child: SizedBox.square(
                      dimension: 48,
                      child: Icon(_listening ? Icons.stop_rounded : Icons.mic_rounded, color: c.onAccent),
                    ),
                  ),
                ),
              ),
              if (_listening) ...[
                const SizedBox(width: 8),
                Flexible(
                  child: Material(
                    color: c.card,
                    elevation: 4,
                    borderRadius: BorderRadius.circular(24),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      child: Text(
                        _partial.isEmpty ? 'Ich höre zu …' : _partial,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: _partial.isEmpty ? c.muted : c.text),
                      ),
                    ),
                  ),
                ),
              ],
            ]),
          ),
        ),
    ]);
  }
}
