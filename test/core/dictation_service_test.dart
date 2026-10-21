import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:frontend/core/services/dictation_service.dart';

/// Erkennung, deren Aufnahmen der Test einzeln beendet.
class _Engine implements SpeechEngine {
  bool available = true;
  int listens = 0;
  @override
  bool isListening = false;
  VoidCallback? _onEnd;
  void Function(String, bool)? _onResult;

  @override
  Future<bool> init({required VoidCallback onEnd}) async {
    _onEnd = onEnd;
    return available;
  }

  @override
  Future<void> listen(void Function(String, bool) onResult) async {
    listens++;
    isListening = true;
    _onResult = onResult;
  }

  @override
  Future<void> stop() async {}

  void say(String text, {bool isFinal = true}) => _onResult!(text, isFinal);
  void end() {
    isListening = false;
    _onEnd!();
  }

  /// Späte Ende-Meldung der vorigen Aufnahme, während die nächste schon läuft.
  void lateEnd() => _onEnd!();
}

void main() {
  late _Engine engine;
  late DateTime now;
  late DictationService dictation;
  final results = <(String, bool)>[];
  late int done;

  setUp(() {
    engine = _Engine();
    now = DateTime(2026, 10, 11, 13, 0);
    dictation = DictationService(engine: engine, clock: () => now);
    results.clear();
    done = 0;
  });

  Future<bool> start() => dictation.start(onResult: (t, f) => results.add((t, f)), onDone: () => done++);
  Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 400));

  test('silence right after tapping does not end the dictation – it keeps listening until something is said', () async {
    expect(await start(), isTrue);
    now = now.add(const Duration(milliseconds: 2500));
    engine.end(); // Gerät gibt nach 2,5 s Stille auf (NO_SPEECH)
    engine.end(); // Status „done“ und Fehler kommen beide
    await settle();
    expect(engine.listens, 2); // genau einmal neu gestartet
    expect(done, 0);

    engine.say('heute war ein guter tag');
    engine.end();
    await settle();
    expect(results.last, ('heute war ein guter tag', true));
    expect(done, 1);
    expect(engine.listens, 2); // nach dem Sprechen wird nicht weiter gehört
  });

  test('after the waiting time without speech the dictation ends', () async {
    await start();
    now = now.add(const Duration(seconds: 11));
    engine.end();
    await settle();
    expect(done, 1);
    expect(engine.listens, 1);
  });

  test('tapping stop ends at once, a late end from the device changes nothing', () async {
    await start();
    await dictation.stop();
    expect(done, 1);
    engine.end();
    await settle();
    expect(done, 1);
    expect(engine.listens, 1);
  });

  test('without recognition or microphone permission start reports false', () async {
    engine.available = false;
    expect(await start(), isFalse);
    expect(engine.listens, 0);
  });

  test('a late end message of the previous recording does not stop the new one', () async {
    await start();
    now = now.add(const Duration(seconds: 3));
    engine.end();
    await settle();
    expect(engine.listens, 2);
    engine.lateEnd(); // „done“ der ersten Aufnahme kommt erst jetzt
    await settle();
    expect(done, 0);
    expect(engine.listens, 2); // die laufende Aufnahme bleibt, kein Doppelstart

    now = now.add(const Duration(seconds: 3));
    engine.end(); // nach 6 s immer noch still → weiter
    await settle();
    expect(engine.listens, 3);
    expect(done, 0);
  });
}
