import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';

import 'package:frontend/app/theme_mode.dart';
import 'package:frontend/core/database/database.dart';
import 'package:frontend/core/di/app_providers.dart';
import 'package:frontend/core/ui/dictation_overlay.dart';
import 'package:frontend/core/ui/theme.dart';
import 'package:frontend/features/auth/screens/wrapper.dart';

class MyApp extends StatelessWidget {
  const MyApp({super.key, this.database});

  /// Überschreibt die Standard-Datenbank (z. B. in Tests).
  final DatabaseService? database;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: appProviders(database ?? DatabaseService.instance),
      child: ValueListenableBuilder<ThemeMode>(
        valueListenable: themeModeNotifier,
        builder: (context, mode, _) {
          return MaterialApp(
            debugShowCheckedModeBanner: false,
            title: 'LifeHub',
            theme: AppTheme.lightTheme,
            darkTheme: AppTheme.darkTheme,
            themeMode: mode,
            // Deutsche Texte und Formate in Systemdialogen (Datum/Uhrzeit: „Abbrechen“, TT.MM.JJJJ)
            locale: const Locale('de', 'DE'),
            supportedLocales: const [Locale('de', 'DE')],
            localizationsDelegates: GlobalMaterialLocalizations.delegates,
            // Mikrofon über der Tastatur für alle Eingabefelder
            builder: (context, child) => DictationOverlay(child: child!),
            home: const Wrapper(),
          );
        },
      ),
    );
  }
}
