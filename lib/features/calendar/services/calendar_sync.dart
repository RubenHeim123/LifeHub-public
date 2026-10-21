import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:frontend/core/models/repeat.dart';
import 'package:frontend/core/services/device_calendar_service.dart';
import 'package:frontend/features/calendar/models/appointment.dart';

/// Was der Nutzer zur Kalender-Verbindung eingestellt hat (pro Gerät, deshalb in den SharedPreferences).
class CalendarSyncSettings {
  /// Termine aus dem Handy-Kalender in LifeHub anzeigen.
  final bool read;

  /// Welche Handy-Kalender angezeigt werden.
  final Set<String> calendarIds;

  /// LifeHub-Termine in den Handy-Kalender „LifeHub“ schreiben – dessen ID, sonst `null`.
  final String? writeCalendarId;

  const CalendarSyncSettings({this.read = false, this.calendarIds = const {}, this.writeCalendarId});

  bool get write => writeCalendarId != null;
}

/// Verbindet LifeHub mit dem Kalender des Handys – in beide Richtungen:
/// Handy-Termine werden live gelesen und angezeigt (nie gespeichert), LifeHub-Termine landen in
/// einem eigenen Handy-Kalender „LifeHub“ (Google-Kalender bleiben unberührt). Erinnerungen bleiben
/// bei LifeHub, die Handy-Termine haben keine – sonst käme jede Erinnerung doppelt.
class CalendarSync {
  CalendarSync({DeviceCalendarService device = const DeviceCalendarService()}) : _device = device;

  final DeviceCalendarService _device;
  DeviceCalendarService get device => _device;

  static const calendarName = 'LifeHub';
  static const calendarColor = 0xFF2E9E6B;

  static String _key(int uid, String name) => 'calendarSync.$uid.$name';

  /// Gespeicherte Einstellungen – ohne lesbaren Speicher gilt „aus“ (die App läuft dann einfach ohne Handy-Kalender).
  Future<CalendarSyncSettings> settings(int uid) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return CalendarSyncSettings(
        read: prefs.getBool(_key(uid, 'read')) ?? false,
        calendarIds: (prefs.getStringList(_key(uid, 'calendars')) ?? const []).toSet(),
        writeCalendarId: prefs.getString(_key(uid, 'writeCalendar')),
      );
    } catch (e) {
      debugPrint('Kalender-Einstellungen lesen: $e');
      return const CalendarSyncSettings();
    }
  }

  /// Handy-Termine anzeigen (ja/nein) und aus welchen Kalendern.
  Future<void> saveRead(int uid, {required bool read, required Set<String> calendarIds}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key(uid, 'read'), read);
    await prefs.setStringList(_key(uid, 'calendars'), calendarIds.toList()..sort());
  }

  /// Handy-Kalender, die zur Auswahl stehen (ohne den eigenen „LifeHub“).
  Future<List<DeviceCalendar>> selectableCalendars(int uid) async {
    final own = (await settings(uid)).writeCalendarId;
    return [for (final c in await _device.calendars()) if (c.id != own && c.name != calendarName) c];
  }

  /// Handy-Termine im Zeitraum – leer, wenn ausgeschaltet oder keine Berechtigung.
  Future<List<ExternalEvent>> events(int uid, DateTime from, DateTime to) async {
    final s = await settings(uid);
    if (!s.read) return const [];
    final ids = {...s.calendarIds}..remove(s.writeCalendarId);
    return _device.eventsBetween(ids, from, to);
  }

  /// Schreiben einschalten: legt den Kalender „LifeHub“ an. Liefert seine ID (`null` = nicht möglich).
  Future<String?> enableWrite(int uid) async {
    if (!await _device.requestAccess()) return null;
    final id = await _device.ensureCalendar(calendarName, calendarColor);
    if (id == null) return null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key(uid, 'writeCalendar'), id);
    return id;
  }

  /// Schreiben ausschalten: der Kalender „LifeHub“ verschwindet samt Terminen vom Handy.
  Future<void> disableWrite(int uid) async {
    final s = await settings(uid);
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key(uid, 'writeCalendar'));
    if (s.writeCalendarId == null) return;
    try {
      await _device.deleteCalendar(s.writeCalendarId!);
    } catch (e) {
      debugPrint('Kalender „$calendarName“ entfernen: $e');
    }
  }

  /// So sieht [a] im Handy-Kalender aus.
  static DeviceEventDraft draftFor(Appointment a) {
    final start = a.allDay ? DateTime(a.date.year, a.date.month, a.date.day) : a.date;
    final end = a.allDay ? DateTime(start.year, start.month, start.day + 1) : start.add(Duration(minutes: a.durationMinutes));
    return DeviceEventDraft(
      title: a.title,
      description: a.description,
      start: start,
      end: end,
      allDay: a.allDay,
      rrule: rruleFor(a.repeat, a.date),
    );
  }

  static const _byDay = ['MO', 'TU', 'WE', 'TH', 'FR', 'SA', 'SU'];

  /// Wiederholung als iCalendar-Regel („FREQ=WEEKLY;INTERVAL=2;BYDAY=MO,FR“), `null` = einmalig.
  static String? rruleFor(Repeat r, DateTime start) {
    final n = r.interval < 1 ? 1 : r.interval;
    return switch (r.freq) {
      RepeatFreq.none => null,
      RepeatFreq.daily => 'FREQ=DAILY;INTERVAL=$n',
      RepeatFreq.weekly =>
        'FREQ=WEEKLY;INTERVAL=$n;BYDAY=${((r.weekdays.isEmpty ? {start.weekday} : r.weekdays).toList()..sort()).map((d) => _byDay[d - 1]).join(',')}',
      RepeatFreq.monthly => 'FREQ=MONTHLY;INTERVAL=$n;BYMONTHDAY=${start.day}',
      RepeatFreq.yearly => 'FREQ=YEARLY;INTERVAL=$n',
    };
  }
}
