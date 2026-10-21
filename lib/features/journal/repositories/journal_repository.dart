import 'package:shared_preferences/shared_preferences.dart';

import 'package:frontend/core/database/database.dart';
import 'package:frontend/core/models/dates.dart';
import 'package:frontend/core/services/notification_service.dart';
import 'package:frontend/features/journal/models/journal_entry.dart';

class JournalRepository {
  JournalRepository({DatabaseService? db, NotificationService? notifications})
      : _db = db ?? DatabaseService.instance,
        _notifications = notifications ?? NotificationService();

  final DatabaseService _db;
  final NotificationService _notifications;

  Future<JournalEntry?> getEntry(int uid, DateTime day) async {
    final db = await _db.database;
    final rows = await db.query('journal_entries',
        where: 'userid = ? AND date = ? AND is_deleted = 0', whereArgs: [uid, JournalEntry.dayKey(day)], limit: 1);
    return rows.isEmpty ? null : JournalEntry.fromMap(rows.first);
  }

  /// Neueste zuerst; [search] sucht in Text und Antworten (ohne Groß-/Kleinschreibung).
  Future<List<JournalEntry>> getEntries(int uid, {String search = ''}) async {
    final db = await _db.database;
    final q = search.trim().toLowerCase();
    final rows = await db.query('journal_entries',
        where: 'userid = ? AND is_deleted = 0${q.isEmpty ? '' : ' AND (LOWER(text) LIKE ? OR LOWER(answers) LIKE ?)'}',
        whereArgs: [uid, if (q.isNotEmpty) ...['%$q%', '%$q%']],
        orderBy: 'date DESC');
    return rows.map(JournalEntry.fromMap).toList();
  }

  /// Speichert den Eintrag des Tages. Gibt es für den Tag schon einen, wird dieser
  /// aktualisiert – auch wenn [entry] ihn nicht kennt (z. B. zweimal „Neu“ am selben Tag).
  /// Gibt die ID zurück.
  Future<int> saveEntry(JournalEntry entry) async {
    final db = await _db.database;
    return db.transaction((txn) async {
      final existing = await txn.query('journal_entries',
          columns: ['id'],
          where: 'userid = ? AND date = ? AND is_deleted = 0 AND id != ?',
          whereArgs: [entry.userid, JournalEntry.dayKey(entry.date), entry.id ?? -1],
          limit: 1);
      final data = {...entry.toMap()..remove('id'), 'last_changed': syncStamp()};
      if (existing.isNotEmpty) {
        final id = existing.first['id'] as int;
        await txn.update('journal_entries', data, where: 'id = ?', whereArgs: [id]);
        // Der bisher bearbeitete Eintrag wurde auf diesen Tag verschoben: das alte Original entfällt.
        if (entry.id != null) {
          await txn.update('journal_entries', {'is_deleted': 1, 'last_changed': syncStamp()}, where: 'id = ?', whereArgs: [entry.id]);
        }
        return id;
      }
      if (entry.id != null) {
        await txn.update('journal_entries', data, where: 'id = ?', whereArgs: [entry.id]);
        return entry.id!;
      }
      return txn.insert('journal_entries', data);
    });
  }

  Future<void> deleteEntry(int id) async {
    final db = await _db.database;
    await db.update('journal_entries', {'is_deleted': 1, 'last_changed': syncStamp()}, where: 'id = ?', whereArgs: [id]);
  }

  Future<void> restoreEntry(int id) => _db.restoreRow('journal_entries', id);

  /// Stimmung der letzten [days] Tage bis einschließlich [today], ältester zuerst (`null` = kein Eintrag).
  Future<List<(DateTime, Mood?)>> moodSeries(int uid, {int days = 30, DateTime? today}) async {
    final end = dateOnly(today ?? DateTime.now());
    final start = addDays(end, -(days - 1));
    final db = await _db.database;
    final rows = await db.query('journal_entries',
        columns: ['date', 'mood'],
        where: 'userid = ? AND is_deleted = 0 AND date >= ? AND date <= ?',
        whereArgs: [uid, JournalEntry.dayKey(start), JournalEntry.dayKey(end)]);
    final byDay = {for (final r in rows) r['date'] as String: Mood.fromValue(r['mood'] as int?)};
    return [
      for (var i = 0; i < days; i++)
        (addDays(start, i), byDay[JournalEntry.dayKey(addDays(start, i))]),
    ];
  }

  // ─── Tägliche Erinnerung ────────────────────────────────────────────────

  static String _reminderKey(int uid) => 'journal_reminder_$uid';
  static int _reminderId(int uid) => NotificationService.journalIdOffset + uid;

  /// Uhrzeit der Erinnerung als (Stunde, Minute), `null` = aus.
  Future<(int, int)?> getReminder(int uid) async {
    final prefs = await SharedPreferences.getInstance();
    final parts = prefs.getString(_reminderKey(uid))?.split(':');
    if (parts == null || parts.length != 2) return null;
    final h = int.tryParse(parts[0]), m = int.tryParse(parts[1]);
    return h == null || m == null ? null : (h, m);
  }

  /// Setzt die Erinnerung (oder schaltet sie mit `null` aus) und plant sie sofort.
  Future<void> setReminder(int uid, (int, int)? time) async {
    final prefs = await SharedPreferences.getInstance();
    if (time == null) {
      await prefs.remove(_reminderKey(uid));
    } else {
      await prefs.setString(_reminderKey(uid), '${time.$1}:${time.$2.toString().padLeft(2, '0')}');
    }
    await refreshReminder(uid);
  }

  /// Plant die Erinnerung nach der gespeicherten Uhrzeit neu (z. B. nach der Anmeldung).
  Future<void> refreshReminder(int uid) async {
    final time = await getReminder(uid);
    await _notifications.cancelNotification(_reminderId(uid));
    if (time == null) return;
    await _notifications.scheduleDaily(
      id: _reminderId(uid),
      title: 'Journal',
      body: 'Wie war dein Tag? Nimm dir zwei Minuten für dein Journal.',
      hour: time.$1,
      minute: time.$2,
    );
  }
}
