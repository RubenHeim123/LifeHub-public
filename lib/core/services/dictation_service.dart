import 'package:flutter/foundation.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

/// Die eigentliche Spracherkennung (im Test ersetzbar).
abstract class SpeechEngine {
  /// `false`, wenn keine Erkennung verfügbar ist oder das Mikrofon nicht erlaubt wurde.
  /// [onEnd] meldet jedes Ende einer Aufnahme (Stille, Fehler, Stopp).
  Future<bool> init({required VoidCallback onEnd});
  Future<void> listen(void Function(String text, bool isFinal) onResult);
  Future<void> stop();

  /// Hört gerade zu (späte Ende-Meldungen einer vorigen Aufnahme lassen sich so erkennen).
  bool get isListening;
}

/// Android/iOS-Spracherkennung über `speech_to_text`, deutsch.
class DeviceSpeechEngine implements SpeechEngine {
  final _speech = SpeechToText();
  bool _ready = false;
  VoidCallback? _onEnd;

  @override
  Future<bool> init({required VoidCallback onEnd}) async {
    _onEnd = onEnd;
    // Fragt beim ersten Mal nach der Mikrofon-Berechtigung.
    _ready = _ready ||
        await _speech.initialize(
          onStatus: (status) {
            if (status == SpeechToText.doneStatus || status == SpeechToText.notListeningStatus) _onEnd?.call();
          },
          onError: (_) => _onEnd?.call(),
        );
    return _ready;
  }

  @override
  Future<void> listen(void Function(String text, bool isFinal) onResult) => _speech.listen(
        onResult: (SpeechRecognitionResult r) => onResult(r.recognizedWords, r.finalResult),
        listenOptions: SpeechListenOptions(
          localeId: 'de_DE',
          partialResults: true,
          cancelOnError: true,
          pauseFor: const Duration(seconds: 3),
        ),
      );

  @override
  Future<void> stop() => _speech.stop();

  @override
  bool get isListening => _speech.isListening;
}

/// Diktieren in Eingabefelder. Die Erkennung des Geräts gibt nach ca. 2–3 s Stille auf –
/// solange noch nichts erkannt wurde, hört der Dienst bis [waitForSpeech] weiter zu
/// (wer nach dem Antippen kurz überlegt, verliert sonst das Diktat).
class DictationService {
  DictationService({SpeechEngine? engine, this.waitForSpeech = const Duration(seconds: 10), DateTime Function()? clock})
      : _engine = engine ?? DeviceSpeechEngine(),
        _clock = clock ?? DateTime.now;

  final SpeechEngine _engine;
  final Duration waitForSpeech;
  final DateTime Function() _clock;

  void Function(String text, bool isFinal)? _onResult;
  VoidCallback? _onDone;
  DateTime? _startedAt;
  bool _heard = false;
  bool _stopping = false;
  bool _active = false;
  bool _ending = false;

  /// Startet das Zuhören. [onResult] liefert Zwischentexte und zum Schluss den fertigen Text
  /// (`isFinal`). [onDone] meldet das Ende (Pause nach dem Sprechen, Fehler, [stop]).
  /// `false`, wenn keine Spracherkennung verfügbar ist oder das Mikrofon nicht erlaubt wurde.
  Future<bool> start({required void Function(String text, bool isFinal) onResult, VoidCallback? onDone}) async {
    _onResult = onResult;
    _onDone = onDone;
    _heard = false;
    _stopping = false;
    _startedAt = _clock();
    try {
      if (!await _engine.init(onEnd: _onEngineEnd)) return false;
      _active = true;
      await _listen();
      return true;
    } catch (e) {
      debugPrint('Spracherkennung nicht verfügbar: $e');
      _active = false;
      return false;
    }
  }

  Future<void> _listen() => _engine.listen((text, isFinal) {
        if (text.trim().isNotEmpty) _heard = true;
        _onResult?.call(text, isFinal);
      });

  Future<void> stop() async {
    _stopping = true;
    try {
      await _engine.stop();
    } catch (_) {}
    _finish();
  }

  /// Ende einer Aufnahme: noch nichts gehört und Zeit übrig → weiter zuhören, sonst fertig.
  ///
  /// Das Gerät meldet ein Ende oft mehrfach (Fehler „keine Sprache“, Status „notListening“,
  /// „done“), teils erst, wenn die nächste Aufnahme schon läuft. Darum kurz abwarten und nur
  /// handeln, wenn wirklich nicht mehr zugehört wird.
  Future<void> _onEngineEnd() async {
    if (!_active || _ending) return;
    _ending = true;
    try {
      await Future<void>.delayed(const Duration(milliseconds: 300));
      if (!_active || _engine.isListening) return;
      final waited = _clock().difference(_startedAt ?? _clock());
      if (!_heard && !_stopping && waited < waitForSpeech) {
        try {
          await _listen();
        } catch (_) {
          await Future<void>.delayed(const Duration(milliseconds: 300));
          await _listen(); // Erkennung war noch nicht frei – ein zweiter Versuch
        }
        return;
      }
      _finish();
    } catch (e) {
      debugPrint('Diktat beendet: $e');
      _finish();
    } finally {
      _ending = false;
    }
  }

  void _finish() {
    if (!_active && _onDone == null) return;
    _active = false;
    final done = _onDone;
    _onDone = null;
    done?.call();
  }
}
