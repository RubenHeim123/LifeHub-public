import 'package:sqflite/sqflite.dart';

import 'package:frontend/core/database/database.dart';
import 'package:frontend/core/models/app_exceptions.dart';
import 'package:frontend/core/models/dates.dart';
import 'package:frontend/core/models/repeat.dart';
import 'package:frontend/core/services/notification_service.dart';
import 'package:frontend/features/calendar/models/appointment.dart';
import 'package:frontend/features/calendar/repositories/appointment_repository.dart';
import 'package:frontend/features/contacts/models/contact.dart';

/// Kontaktverzeichnis: Personen, Notizen zu ihnen, Geburtstage als Kalendereintrag und
/// Erinnerungen an datierte Notizen.
class ContactRepository {
  ContactRepository({
    DatabaseService? db,
    AppointmentRepository? appointments,
    NotificationService? notifications,
    DateTime Function()? clock,
  })  : _db = db ?? DatabaseService.instance,
        _notifications = notifications ?? NotificationService(),
        _clock = clock ?? DateTime.now,
        _appointments = appointments ?? AppointmentRepository(db: db, notifications: notifications, clock: clock);

  final DatabaseService _db;
  final AppointmentRepository _appointments;
  final NotificationService _notifications;
  final DateTime Function() _clock;

  /// Uhrzeit der Erinnerung am Tag einer Notiz (und am Tag danach fürs Nachfragen).
  static const reminderHour = 9;

  // ─── Kontakte ─────────────────────────────────────────────────────────

  /// Alle Kontakte A–Z; [search] durchsucht Name, Spitzname, Beziehung und alle Notizen.
  Future<List<Contact>> getContacts(int uid, {String search = ''}) async {
    final db = await _db.database;
    final q = search.trim().toLowerCase();
    final like = '%$q%';
    final rows = await db.rawQuery('''
        SELECT * FROM contacts c WHERE c.userid = ? AND c.is_deleted = 0${q.isEmpty ? '' : '''
          AND (LOWER(c.name) LIKE ? OR LOWER(IFNULL(c.nickname, '')) LIKE ? OR LOWER(IFNULL(c.relation, '')) LIKE ?
            OR LOWER(IFNULL(c.notes, '')) LIKE ?
            OR EXISTS (SELECT 1 FROM contact_notes n WHERE n.contactId = c.id AND n.is_deleted = 0 AND LOWER(n.text) LIKE ?))'''}
        ORDER BY c.name COLLATE NOCASE''', [uid, if (q.isNotEmpty) ...List.filled(5, like)]);
    return rows.map(Contact.fromMap).toList();
  }

  Future<Contact?> getContact(int id) async {
    final db = await _db.database;
    final rows = await db.query('contacts', where: 'id = ? AND is_deleted = 0', whereArgs: [id]);
    return rows.isEmpty ? null : Contact.fromMap(rows.first);
  }

  /// Speichert den Kontakt und hält den jährlichen Geburtstagseintrag im Kalender aktuell.
  Future<int> saveContact(Contact contact) async {
    if (contact.name.trim().isEmpty) throw const UserFacingException('Bitte gib einen Namen ein.');
    final db = await _db.database;
    var c = contact;
    final appointmentId = c.appointmentId;
    if (c.birthday != null) {
      final birthday = Appointment(
        id: appointmentId,
        title: 'Geburtstag: ${c.name.trim()}',
        date: dateOnly(c.birthday!),
        userid: c.userid,
        allDay: true,
        repeat: Repeat.yearly,
        reminderMinutes: 0,
      );
      if (appointmentId == null) {
        c = c.copyWith(appointmentId: await _appointments.createAppointment(birthday));
      } else {
        await _appointments.updateAppointment(birthday);
      }
    } else if (appointmentId != null) {
      await _appointments.deleteAppointment(appointmentId);
      c = c.copyWith(clearAppointment: true);
    }
    final data = {...c.toMap()..remove('id'), 'last_changed': syncStamp()};
    if (c.id == null) return db.insert('contacts', data);
    await db.update('contacts', data, where: 'id = ?', whereArgs: [c.id]);
    // Neuer Name → Erinnerungen der Notizen mit neuem Titel
    for (final n in await getNotes(c.id!)) {
      await _schedule(n, c.name.trim());
    }
    return c.id!;
  }

  /// Löscht den Kontakt samt Notizen, Erinnerungen und Geburtstagseintrag. Liefert den
  /// Zeitstempel für [restoreContact].
  Future<String> deleteContact(int id) async {
    final contact = await getContact(id);
    final notes = await getNotes(id);
    final db = await _db.database;
    final at = syncStamp();
    await db.transaction((txn) async {
      await txn.update('contacts', {'is_deleted': 1, 'last_changed': at}, where: 'id = ?', whereArgs: [id]);
      await txn.update('contact_notes', {'is_deleted': 1, 'last_changed': at}, where: 'contactId = ? AND is_deleted = 0', whereArgs: [id]);
    });
    for (final n in notes) {
      await _cancel(n);
    }
    if (contact?.appointmentId != null) await _appointments.deleteAppointment(contact!.appointmentId!);
    return at;
  }

  Future<void> restoreContact(int id, String at) async {
    final db = await _db.database;
    await db.transaction((txn) async {
      await txn.update('contacts', {'is_deleted': 0, 'last_changed': syncStamp()}, where: 'id = ?', whereArgs: [id]);
      await txn.update('contact_notes', {'is_deleted': 0}, where: 'contactId = ? AND is_deleted = 1 AND last_changed = ?', whereArgs: [id, at]);
    });
    final contact = await getContact(id);
    if (contact == null) return;
    if (contact.appointmentId != null) {
      await _appointments.restoreAppointment(await _appointments.getAppointment(contact.appointmentId!));
    }
    for (final n in await getNotes(id)) {
      await _schedule(n, contact.name);
    }
  }

  /// Kontakte mit Geburtstag in den nächsten [days] Tagen (heute zählt), der nächste zuerst.
  Future<List<Contact>> upcomingBirthdays(int uid, {DateTime? now, int days = 7}) async {
    final at = now ?? _clock();
    final db = await _db.database;
    final rows = await db.query('contacts', where: 'userid = ? AND is_deleted = 0 AND birthday IS NOT NULL', whereArgs: [uid]);
    return rows.map(Contact.fromMap).where((c) => c.daysUntilBirthday(at)! <= days).toList()
      ..sort((a, b) => a.daysUntilBirthday(at)!.compareTo(b.daysUntilBirthday(at)!));
  }

  // ─── Notizen ──────────────────────────────────────────────────────────

  /// Notizen einer Person: anstehende datierte zuerst (nach Datum), dann der Rest neueste zuerst,
  /// erledigte am Ende.
  Future<List<ContactNote>> getNotes(int contactId) async {
    final db = await _db.database;
    final rows = await db.query('contact_notes', where: 'contactId = ? AND is_deleted = 0', whereArgs: [contactId]);
    final today = dateOnly(_clock());
    int rank(ContactNote n) => n.done ? 2 : (n.date != null && !n.date!.isBefore(today) ? 0 : 1);
    return rows.map(ContactNote.fromMap).toList()
      ..sort((a, b) {
        final r = rank(a).compareTo(rank(b));
        if (r != 0) return r;
        if (rank(a) == 0) return a.date!.compareTo(b.date!);
        return b.created.compareTo(a.created);
      });
  }

  Future<ContactNote> saveNote(ContactNote note) async {
    if (note.text.trim().isEmpty) throw const UserFacingException('Die Notiz ist leer.');
    final db = await _db.database;
    final data = {...note.toMap()..remove('id'), 'last_changed': syncStamp()};
    var saved = note;
    if (note.id == null) {
      saved = note.copyWith(id: await db.insert('contact_notes', data));
    } else {
      await db.update('contact_notes', data, where: 'id = ?', whereArgs: [note.id]);
    }
    await _schedule(saved, await _name(db, saved.contactId));
    return saved;
  }

  Future<ContactNote> setNoteDone(ContactNote note, bool done) => saveNote(note.copyWith(done: done));

  Future<void> deleteNote(ContactNote note) async {
    final db = await _db.database;
    await db.update('contact_notes', {'is_deleted': 1, 'last_changed': syncStamp()}, where: 'id = ?', whereArgs: [note.id]);
    await _cancel(note);
  }

  Future<void> restoreNote(ContactNote note) async {
    await _db.restoreRow('contact_notes', note.id!);
    await _schedule(note, await _name(await _db.database, note.contactId));
  }

  /// Für Heute: Notizen mit dem Datum [day] und die zum Nachfragen vom Vortag, mit Namen.
  Future<({List<ContactNote> due, List<ContactNote> followUps})> notesForDay(int uid, DateTime day) async {
    final db = await _db.database;
    final today = dateOnly(day);
    final rows = await db.rawQuery('''
        SELECT n.*, c.name AS contactName FROM contact_notes n JOIN contacts c ON c.id = n.contactId AND c.is_deleted = 0
        WHERE n.userid = ? AND n.is_deleted = 0 AND (n.date = ? OR (n.date = ? AND n.followUp = 1))
        ORDER BY c.name COLLATE NOCASE, n.id''', [uid, today.toIso8601String(), addDays(today, -1).toIso8601String()]);
    final notes = rows.map(ContactNote.fromMap).toList();
    return (
      due: notes.where((n) => n.date == today).toList(),
      followUps: notes.where((n) => n.date != today).toList(),
    );
  }

  /// Plant die Erinnerungen aller offenen datierten Notizen neu (nach der Anmeldung).
  Future<void> refreshReminders(int uid) async {
    final db = await _db.database;
    final rows = await db.rawQuery('''
        SELECT n.*, c.name AS contactName FROM contact_notes n JOIN contacts c ON c.id = n.contactId AND c.is_deleted = 0
        WHERE n.userid = ? AND n.is_deleted = 0 AND n.done = 0 AND n.date >= ?''',
        [uid, addDays(dateOnly(_clock()), -1).toIso8601String()]);
    for (final n in rows.map(ContactNote.fromMap)) {
      await _schedule(n, n.contactName ?? '');
    }
  }

  Future<String> _name(DatabaseExecutor db, int contactId) async {
    final rows = await db.query('contacts', columns: ['name'], where: 'id = ?', whereArgs: [contactId]);
    return rows.isEmpty ? '' : rows.first['name'] as String? ?? '';
  }

  static int _id(ContactNote n) => NotificationService.contactIdOffset + 2 * n.id!;

  Future<void> _cancel(ContactNote n) async {
    await _notifications.cancelNotification(_id(n));
    await _notifications.cancelNotification(_id(n) + 1);
  }

  Future<void> _schedule(ContactNote n, String name) async {
    await _cancel(n);
    final date = n.date;
    if (n.done || date == null) return;
    final now = _clock();
    final at = DateTime(date.year, date.month, date.day, reminderHour);
    if (at.isAfter(now)) {
      await _notifications.scheduleNotification(id: _id(n), title: '$name: ${n.text}', body: 'Heute', scheduledDate: at);
    }
    final followUp = DateTime(date.year, date.month, date.day + 1, reminderHour);
    if (n.followUp && followUp.isAfter(now)) {
      await _notifications.scheduleNotification(
          id: _id(n) + 1, title: 'Bei $name nachfragen', body: '${n.text} – wie war’s?', scheduledDate: followUp);
    }
  }
}
