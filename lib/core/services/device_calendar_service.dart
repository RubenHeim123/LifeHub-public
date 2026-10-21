import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

/// Ein Kalender am Handy (Google, Samsung, lokal …).
class DeviceCalendar {
  final String id;
  final String name;

  /// Konto, z. B. „max@example.com“.
  final String account;
  final int color;
  final bool writable;
  const DeviceCalendar({required this.id, required this.name, this.account = '', this.color = 0xFF4CAF50, this.writable = false});

  /// „privat · max@example.com“ – das Konto nur, wenn es etwas anderes sagt als der Name.
  String get label => account.isEmpty || account == name ? name : '$name · $account';
}

/// Ein Termin aus dem Handy-Kalender – nur zum Anzeigen, wird nicht in LifeHub gespeichert.
/// Serien sind schon aufgelöst: jedes Vorkommen ist ein eigener Eintrag.
class ExternalEvent {
  final String eventId;
  final String title;
  final DateTime start;
  final DateTime end;
  final bool allDay;
  final String? location;
  final String? description;
  final String calendarId;
  final String calendarName;
  final int color;
  const ExternalEvent({
    required this.eventId,
    required this.title,
    required this.start,
    required this.end,
    this.allDay = false,
    this.location,
    this.description,
    required this.calendarId,
    this.calendarName = '',
    this.color = 0xFF4CAF50,
  });

  /// Kalendertag des Beginns (ganztägige Termine liegen am Handy in UTC).
  DateTime get day => DateTime(start.year, start.month, start.day);
}

/// Ein LifeHub-Termin, wie er in den Handy-Kalender geschrieben wird.
class DeviceEventDraft {
  final String title;
  final String? description;
  final DateTime start;
  final DateTime end;
  final bool allDay;

  /// Wiederholung als iCalendar-Regel, z. B. „FREQ=WEEKLY;INTERVAL=1;BYDAY=FR“.
  final String? rrule;
  const DeviceEventDraft({required this.title, this.description, required this.start, required this.end, this.allDay = false, this.rrule});
}

/// Zugriff auf den Kalender des Handys. Im Test wird eine eigene Implementierung per Provider eingesetzt.
/// Fehler werden geloggt; Lesen liefert dann eine leere Liste, damit die App weiterläuft.
class DeviceCalendarService {
  const DeviceCalendarService();

  static const _channel = MethodChannel('lifehub/device_calendar');

  bool get _supported => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  Future<bool> hasAccess() async {
    if (!_supported) return false;
    try {
      return await Permission.calendarFullAccess.isGranted;
    } catch (e) {
      debugPrint('Kalender-Berechtigung: $e');
      return false;
    }
  }

  /// Fragt beim ersten Mal nach der Berechtigung. `false`, wenn abgelehnt oder nicht unterstützt.
  Future<bool> requestAccess() async {
    if (!_supported) return false;
    try {
      return (await Permission.calendarFullAccess.request()).isGranted;
    } catch (e) {
      debugPrint('Kalender-Berechtigung: $e');
      return false;
    }
  }

  Future<List<DeviceCalendar>> calendars() async {
    if (!await hasAccess()) return const [];
    try {
      final rows = await _channel.invokeListMethod<Map<Object?, Object?>>('calendars') ?? const [];
      return [
        for (final r in rows)
          DeviceCalendar(
            id: r['id'] as String,
            name: r['name'] as String? ?? '',
            account: r['account'] as String? ?? '',
            color: r['color'] as int? ?? 0xFF4CAF50,
            writable: r['writable'] as bool? ?? false,
          ),
      ];
    } catch (e) {
      debugPrint('Kalender lesen: $e');
      return const [];
    }
  }

  /// Alle Vorkommen in den Kalendern [calendarIds] zwischen [from] und [to].
  Future<List<ExternalEvent>> eventsBetween(Set<String> calendarIds, DateTime from, DateTime to) async {
    if (calendarIds.isEmpty || !await hasAccess()) return const [];
    try {
      final rows = await _channel.invokeListMethod<Map<Object?, Object?>>('events', {
            'calendarIds': calendarIds.toList(),
            'from': from.millisecondsSinceEpoch,
            'to': to.millisecondsSinceEpoch,
          }) ??
          const [];
      return [
        for (final r in rows)
          _event(r),
      ];
    } catch (e) {
      debugPrint('Kalendertermine lesen: $e');
      return const [];
    }
  }

  static ExternalEvent _event(Map<Object?, Object?> r) {
    final allDay = r['allDay'] as bool? ?? false;
    DateTime at(Object? ms) {
      final t = DateTime.fromMillisecondsSinceEpoch(ms as int, isUtc: allDay);
      // Ganztägig: UTC-Mitternacht → derselbe Kalendertag in Ortszeit
      return allDay ? DateTime(t.year, t.month, t.day) : t;
    }

    return ExternalEvent(
      eventId: r['eventId'] as String,
      title: r['title'] as String? ?? '',
      start: at(r['begin']),
      end: at(r['end']),
      allDay: allDay,
      location: r['location'] as String?,
      description: r['description'] as String?,
      calendarId: r['calendarId'] as String,
      calendarName: r['calendarName'] as String? ?? '',
      color: r['color'] as int? ?? 0xFF4CAF50,
    );
  }

  /// Eigener Kalender [name] am Handy (wird bei Bedarf angelegt). Liefert seine ID.
  Future<String?> ensureCalendar(String name, int color) =>
      _channel.invokeMethod<String>('ensureCalendar', {'name': name, 'color': color});

  /// Termin in [calendarId] anlegen bzw. ändern ([eventId]). Liefert die ID im Handy-Kalender.
  Future<String?> upsertEvent(String calendarId, DeviceEventDraft e, {String? eventId}) {
    final start = e.allDay ? DateTime.utc(e.start.year, e.start.month, e.start.day) : e.start;
    final end = e.allDay ? DateTime.utc(e.end.year, e.end.month, e.end.day) : e.end;
    return _channel.invokeMethod<String>('upsertEvent', {
      'calendarId': calendarId,
      'eventId': eventId,
      'title': e.title,
      'description': e.description,
      'start': start.millisecondsSinceEpoch,
      'end': end.millisecondsSinceEpoch,
      'allDay': e.allDay,
      'rrule': e.rrule,
    });
  }

  Future<void> deleteEvent(String eventId) => _channel.invokeMethod<bool>('deleteEvent', {'eventId': eventId});

  Future<void> deleteCalendar(String calendarId) => _channel.invokeMethod<bool>('deleteCalendar', {'calendarId': calendarId});
}
