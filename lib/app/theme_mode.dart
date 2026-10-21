import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Hell/Dunkel/System – wird im Profil geändert und in den Preferences gespeichert.
final ValueNotifier<ThemeMode> themeModeNotifier = ValueNotifier(ThemeMode.system);

const _prefKey = 'themeMode';

Future<void> loadThemePref() async {
  final prefs = await SharedPreferences.getInstance();
  themeModeNotifier.value = switch (prefs.getString(_prefKey)) {
    'dark' => ThemeMode.dark,
    'light' => ThemeMode.light,
    _ => ThemeMode.system,
  };
}

Future<void> saveThemePref(ThemeMode mode) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(_prefKey, switch (mode) {
    ThemeMode.dark => 'dark',
    ThemeMode.light => 'light',
    _ => 'system',
  });
  themeModeNotifier.value = mode;
}
