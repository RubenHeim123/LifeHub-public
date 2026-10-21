import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:frontend/core/services/notification_service.dart';
import 'package:frontend/features/auth/screens/authenticate.dart';
import 'package:frontend/features/auth/services/auth.dart';
import 'package:frontend/app/home_shell.dart';

class Wrapper extends StatefulWidget {
  const Wrapper({super.key});

  /// Meldet ab und kehrt zum Login zurück (ersetzt den gesamten Navigations-Stack).
  /// Alle geplanten Erinnerungen werden entfernt – beim nächsten Anmelden plant die App sie neu.
  static Future<void> signOut(BuildContext context) async {
    final navigator = Navigator.of(context, rootNavigator: true);
    final notifications = context.read<NotificationService>();
    await context.read<AuthService>().signOut();
    await notifications.cancelAllNotifications();
    navigator.pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const Wrapper()),
      (_) => false,
    );
  }

  @override
  State<Wrapper> createState() => _WrapperState();
}

class _WrapperState extends State<Wrapper> {
  // Einmal im State anlegen, sonst startet jeder Rebuild eine neue Abfrage.
  late final Future<String?> _email = context.read<AuthService>().getCurrentEmail();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String?>(
      future: _email,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        final email = snapshot.data;
        return email == null ? const Authenticate() : HomeShell(email: email);
      },
    );
  }
}
