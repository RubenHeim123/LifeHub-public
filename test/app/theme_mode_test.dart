import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:frontend/app/theme_mode.dart';

void main() {
  test('the chosen theme is stored and restored; unknown values fall back to system', () async {
    SharedPreferences.setMockInitialValues({});
    await saveThemePref(ThemeMode.dark);
    themeModeNotifier.value = ThemeMode.light;
    await loadThemePref();
    expect(themeModeNotifier.value, ThemeMode.dark);

    SharedPreferences.setMockInitialValues({'themeMode': 'pink'});
    await loadThemePref();
    expect(themeModeNotifier.value, ThemeMode.system);
  });
}
