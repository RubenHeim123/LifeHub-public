import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'package:frontend/core/database/database.dart';
import 'package:frontend/features/calendar/models/appointment.dart';
import 'package:frontend/features/calendar/services/calendar_sync.dart';
import 'package:frontend/core/services/notification_service.dart';

class AppointmentRepository {
  AppointmentRepository({DatabaseService? db, NotificationService? notifications, DateTime Function()? clock, CalendarSync? calendarSync})
      : _db = db ?? DatabaseService.instance,
        _notifications = notifications ?? NotificationService(),
        _clock = clock ?? DateTime.now,
        _sync = calendarSync;

  final DatabaseService _db;
  final NotificationService _notifications;
  final DateTime Function() _clock;

  /// Spiegelt Termine in den Handy-Kalender „LifeHub“, wenn das eingeschaltet ist.
  final CalendarSync? _sync;

  // ─── Handy-Kalender ───────────────────────────────────────────────────

  /// Termin in den Handy-Kalender schreiben (anlegen oder ändern). Fehler dort brechen das Speichern
  /// in LifeHub nie ab – sie werden nur geloggt.
  Future<void> _mirror(Appointment a, int id) async {
    final sync = _sync;
    if (sync == null) return;
    try {
      final calendarId = (await sync.settings(a.userid)).writeCalendarId;
      if (calendarId == null) return;
      final db = await _db.database;
      final link = (await db.query('device_calendar_links', where: 'appointmentId = ?', whereArgs: [id])).firstOrNull;
      // Verknüpfung aus einem anderen Kalender (z. B. nach Aus- und Einschalten) gilt nicht mehr
      final eventId = link != null && link['calendarId'] == calendarId ? link['eventId'] as String? : null;
      final newId = await sync.device.upsertEvent(calendarId, CalendarSync.draftFor(a), eventId: eventId);
      if (newId == null) return;
      await db.insert('device_calendar_links', {'appointmentId': id, 'calendarId': calendarId, 'eventId': newId},
          conflictAlgorithm: ConflictAlgorithm.replace);
    } catch (e) {
      debugPrint('Termin in den Handy-Kalender schreiben: $e');
    }
  }

  Future<void> _unmirror(int id) async {
    final sync = _sync;
    if (sync == null) return;
    try {
      final db = await _db.database;
      final link = (await db.query('device_calendar_links', where: 'appointmentId = ?', whereArgs: [id])).firstOrNull;
      if (link == null) return;
      await db.delete('device_calendar_links', where: 'appointmentId = ?', whereArgs: [id]);
      await sync.device.deleteEvent(link['eventId'] as String);
    } catch (e) {
      debugPrint('Termin aus dem Handy-Kalender entfernen: $e');
    }
  }

  /// Alle Termine von [uid] in den Handy-Kalender schreiben (nach dem Einschalten). Liefert die Anzahl.
  Future<int> mirrorAll(int uid) async {
    final all = await getAllAppointments(uid);
    for (final a in all) {
      await _mirror(a, a.id!);
    }
    return all.length;
  }

  /// Verknüpfungen vergessen (nach dem Ausschalten ist der Kalender „LifeHub“ samt Terminen weg).
  Future<void> forgetDeviceLinks(int uid) async {
    final db = await _db.database;
    await db.delete('device_calendar_links',
        where: 'appointmentId IN (SELECT id FROM appointments WHERE userid = ?)', whereArgs: [uid]);
  }
  /// Legt den Termin an und plant die Erinnerung. Liefert die ID.
  Future<int> createAppointment(Appointment appointment) async {
    final db = await _db.database;
    final id = await db.insert(
      'appointments',
      appointment.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    
    await _scheduleReminder(appointment, id);
    await _mirror(appointment, id);
    return id;
  }

  /// Erinnerung für das nächste Vorkommen (ersetzt eine bestehende). Bei jährlichen Einträgen
  /// wird immer nur das nächste Jahr geplant – [refreshReminders] zieht beim App-Start nach.
  Future<void> _scheduleReminder(Appointment a, int id) async {
    await _notifications.cancelNotification(id);
    final next = a.nextReminder(_clock());
    if (next == null) return;
    final minutes = a.reminderMinutes!;
    final String when;
    if (a.allDay) {
      when = switch (minutes) {
        0 => 'Heute',
        1440 => 'Morgen',
        10080 => 'In einer Woche',
        final m => 'In ${m ~/ 1440} Tagen',
      };
    } else {
      final time = '${a.date.hour.toString().padLeft(2, '0')}:${a.date.minute.toString().padLeft(2, '0')} Uhr';
      final relative = switch (minutes) {
        0 => 'Jetzt',
        1440 => 'Morgen',
        final m when m >= 60 && m % 60 == 0 => 'In ${m ~/ 60} ${m == 60 ? 'Stunde' : 'Stunden'}',
        final m => 'In $m Minuten',
      };
      when = '$relative · $time';
    }
    final years = a.yearsAt(next.occurrence);
    await _notifications.scheduleNotification(
      id: id,
      title: a.allDay ? a.title : 'Termin: ${a.title}',
      body: [
        [when, if (years != null) '$years Jahre'].join(' · '),
        if (a.description != null && a.description!.isNotEmpty) a.description!,
      ].join('\n'),
      scheduledDate: next.at,
    );
  }

  /// Plant die Erinnerungen aller kommenden und jährlichen Einträge neu (beim App-Start),
  /// damit wiederkehrende Einträge auch in den Folgejahren erinnern.
  Future<void> refreshReminders(int uid) async {
    final now = _clock();
    for (final a in await getAllAppointments(uid)) {
      if (a.reminderMinutes == null) continue;
      if (a.repeats || a.endDate.isAfter(now)) await _scheduleReminder(a, a.id!);
    }
  }

  Future<Appointment> getAppointment(int id) async {
    final db = await _db.database;
    final List<Map<String, dynamic>> maps = await db.query(
      'appointments',
      where: 'id = ?',
      whereArgs: [id],
    );
    if (maps.isNotEmpty) {
      return Appointment.fromMap(maps.first);
    } else {
      throw Exception('Appointment ID $id not found');
    }
  }

  Future<List<Appointment>> getAllAppointments(int uid) async {
    final db = await _db.database;
    final List<Map<String, dynamic>> maps = await db.query(
      'appointments',
      where: 'userid = ? AND is_deleted = 0',
      whereArgs: [uid],
      orderBy: 'date ASC',
    );
    return List.generate(maps.length, (i) {
      return Appointment.fromMap(maps[i]);
    });
  }

  Future<void> updateAppointment(Appointment appointment) async {
    final db = await _db.database;
    final Map<String, dynamic> data = appointment.toMap();
    data['last_changed'] = syncStamp();
    await db.update(
      'appointments',
      data,
      where: 'id = ?',
      whereArgs: [appointment.id],
    );
    
    if (appointment.id != null) {
      await _scheduleReminder(appointment, appointment.id!);
      await _mirror(appointment, appointment.id!);
    }
  }

  /// Macht ein gelöschtes Element wieder sichtbar und plant die Erinnerung neu.
  Future<void> restoreAppointment(Appointment appointment) async {
    await _db.restoreRow('appointments', appointment.id!);
    await _scheduleReminder(appointment, appointment.id!);
    await _mirror(appointment, appointment.id!);
  }

  Future<void> deleteAppointment(int id) async {
    final db = await _db.database;
    await db.update(
      'appointments',
      {
        'is_deleted': 1,
        'last_changed': syncStamp(),
      },
      where: 'id = ?',
      whereArgs: [id],
    );
    await _notifications.cancelNotification(id);
    await _unmirror(id);
  }
}
