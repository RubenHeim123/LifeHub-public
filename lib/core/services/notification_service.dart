import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

/// Lokale Erinnerungen. Fehler (fehlende Berechtigung, Plugin nicht bereit …) werden
/// geloggt, brechen aber nie den aufrufenden Speichervorgang ab.
class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  /// Für Tests: eigene Instanz, deren Methoden überschrieben werden können.
  @visibleForTesting
  NotificationService.forTesting();

  // Getrennte ID-Bereiche, damit sich Erinnerungen verschiedener Quellen nicht überschreiben.
  // Termine nutzen ihre ID direkt.
  static const int todoIdOffset = 10000;
  static const int budgetIdOffset = 20000;
  static const int inventoryIdOffset = 30000;
  static const int journalIdOffset = 40000; // + Nutzer-ID: tägliche Journal-Erinnerung
  static const int contactIdOffset = 50000; // + 2 × Notiz-ID (+1 fürs Nachfragen am Tag danach)

  static const String _channelId = 'lifehub_channel';

  final FlutterLocalNotificationsPlugin _notificationsPlugin = FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  AndroidFlutterLocalNotificationsPlugin? get _android =>
      _notificationsPlugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();

  Future<void> init() async {
    try {
      tz.initializeTimeZones();
      // Ohne das rechnet `tz.local` in UTC: eine tägliche Erinnerung „21:00“ käme dann um 23:00 MESZ.
      try {
        tz.setLocalLocation(tz.getLocation((await FlutterTimezone.getLocalTimezone()).identifier));
      } catch (e) {
        debugPrint('Zeitzone nicht ermittelbar, nutze UTC: $e');
      }

      const AndroidInitializationSettings initializationSettingsAndroid =
          AndroidInitializationSettings('@mipmap/ic_launcher');

      const DarwinInitializationSettings initializationSettingsIOS = DarwinInitializationSettings(
        requestAlertPermission: true,
        requestBadgePermission: true,
        requestSoundPermission: true,
      );

      const InitializationSettings initializationSettings = InitializationSettings(
        android: initializationSettingsAndroid,
        iOS: initializationSettingsIOS,
      );

      await _notificationsPlugin.initialize(
        initializationSettings,
        onDidReceiveNotificationResponse: (details) {
          // Handle notification tap
        },
      );
      _initialized = true;
      await _removeOutdatedChannels();
    } catch (e) {
      debugPrint('NotificationService.init fehlgeschlagen: $e');
    }
  }

  /// Entfernt Kanäle früherer App-Versionen, damit in den Android-Einstellungen
  /// nur noch der aktuelle Kanal erscheint.
  Future<void> _removeOutdatedChannels() async {
    final android = _android;
    if (android == null) return;
    for (final channel in await android.getNotificationChannels() ?? const <AndroidNotificationChannel>[]) {
      if (channel.id != _channelId) await android.deleteNotificationChannel(channel.id);
    }
  }

  /// Android 13+: Benachrichtigungen müssen erlaubt werden. Bewusst getrennt von [init],
  /// damit der Berechtigungsdialog den App-Start nicht blockiert.
  Future<void> requestPermissions() async {
    try {
      await _android?.requestNotificationsPermission();
    } catch (e) {
      debugPrint('Benachrichtigungs-Berechtigung fehlgeschlagen: $e');
    }
  }

  Future<void> scheduleNotification({
    required int id,
    required String title,
    required String body,
    required DateTime scheduledDate,
  }) async {
    if (!_initialized || scheduledDate.isBefore(DateTime.now())) return;

    try {
      // Ab Android 12 sind exakte Alarme ohne Berechtigung verboten (SecurityException).
      // Ohne sie weichen wir auf ungefähre Alarme aus – für eine Erinnerung reicht das.
      final canExact = await _android?.canScheduleExactNotifications() ?? true;

      await _notificationsPlugin.zonedSchedule(
        id,
        title,
        body,
        tz.TZDateTime.from(scheduledDate, tz.local),
        const NotificationDetails(
          android: AndroidNotificationDetails(
            _channelId,
            'LifeHub Benachrichtigungen',
            importance: Importance.max,
            priority: Priority.high,
          ),
          iOS: DarwinNotificationDetails(),
        ),
        androidScheduleMode:
            canExact ? AndroidScheduleMode.exactAllowWhileIdle : AndroidScheduleMode.inexactAllowWhileIdle,
      );
    } catch (e) {
      debugPrint('Erinnerung konnte nicht geplant werden: $e');
    }
  }

  /// Nächstes [hour]:[minute] Ortszeit nach [now] (heute, sonst morgen).
  static DateTime nextDaily(DateTime now, int hour, int minute) {
    final today = DateTime(now.year, now.month, now.day, hour, minute);
    return today.isAfter(now) ? today : DateTime(now.year, now.month, now.day + 1, hour, minute);
  }

  /// Wiederholt sich jeden Tag um [hour]:[minute] (z. B. die Journal-Erinnerung).
  Future<void> scheduleDaily({required int id, required String title, required String body, required int hour, required int minute}) async {
    if (!_initialized) return;
    try {
      final next = tz.TZDateTime.from(nextDaily(DateTime.now(), hour, minute), tz.local);
      final canExact = await _android?.canScheduleExactNotifications() ?? true;
      await _notificationsPlugin.zonedSchedule(
        id,
        title,
        body,
        next,
        const NotificationDetails(
          android: AndroidNotificationDetails(_channelId, 'LifeHub Benachrichtigungen', importance: Importance.max, priority: Priority.high),
          iOS: DarwinNotificationDetails(),
        ),
        androidScheduleMode: canExact ? AndroidScheduleMode.exactAllowWhileIdle : AndroidScheduleMode.inexactAllowWhileIdle,
        matchDateTimeComponents: DateTimeComponents.time,
      );
    } catch (e) {
      debugPrint('Tägliche Erinnerung konnte nicht geplant werden: $e');
    }
  }

  Future<void> cancelNotification(int id) async {
    if (!_initialized) return;
    try {
      await _notificationsPlugin.cancel(id);
    } catch (e) {
      debugPrint('Erinnerung konnte nicht entfernt werden: $e');
    }
  }

  Future<void> cancelAllNotifications() async {
    if (!_initialized) return;
    try {
      await _notificationsPlugin.cancelAll();
    } catch (e) {
      debugPrint('Erinnerungen konnten nicht entfernt werden: $e');
    }
  }
}
