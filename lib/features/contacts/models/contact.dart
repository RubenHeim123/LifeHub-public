import 'package:frontend/core/models/dates.dart';

/// Eine Person im Kontaktverzeichnis. Ein Geburtstag legt einen jährlichen Kalendereintrag an
/// ([appointmentId]).
class Contact {
  final int? id;
  final int userid;
  final String name;
  final String? nickname;
  final String? relation;
  final String? phone;
  final String? email;
  final String? address;
  final DateTime? birthday;
  final String? notes;
  final int? appointmentId;

  const Contact({
    this.id,
    required this.userid,
    required this.name,
    this.nickname,
    this.relation,
    this.phone,
    this.email,
    this.address,
    this.birthday,
    this.notes,
    this.appointmentId,
  });

  /// „LM“ für „Lena Müller“, „L“ für „Lena“.
  String get initials {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    String first(String p) => String.fromCharCode(p.runes.first);
    return (parts.length == 1 ? first(parts.first) : first(parts.first) + first(parts.last)).toUpperCase();
  }

  /// Nächster Geburtstag ab [now] (heute zählt), am 29.2. in anderen Jahren der 28.2.
  DateTime? nextBirthday(DateTime now) {
    final b = birthday;
    if (b == null) return null;
    final today = dateOnly(now);
    DateTime inYear(int y) {
      final d = DateTime(y, b.month, b.day);
      return d.month == b.month ? d : DateTime(y, b.month + 1, 0);
    }

    final thisYear = inYear(today.year);
    return thisYear.isBefore(today) ? inYear(today.year + 1) : thisYear;
  }

  /// Tage bis zum nächsten Geburtstag (0 = heute).
  int? daysUntilBirthday(DateTime now) {
    final next = nextBirthday(now);
    return next == null ? null : daysBetween(dateOnly(now), next);
  }

  /// Alter am nächsten Geburtstag.
  int? ageAtNextBirthday(DateTime now) {
    final next = nextBirthday(now);
    return next == null ? null : next.year - birthday!.year;
  }

  Contact copyWith({int? id, int? appointmentId, bool clearAppointment = false}) => Contact(
        id: id ?? this.id,
        userid: userid,
        name: name,
        nickname: nickname,
        relation: relation,
        phone: phone,
        email: email,
        address: address,
        birthday: birthday,
        notes: notes,
        appointmentId: clearAppointment ? null : appointmentId ?? this.appointmentId,
      );

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'userid': userid,
        'name': name.trim(),
        'nickname': _opt(nickname),
        'relation': _opt(relation),
        'phone': _opt(phone),
        'email': _opt(email),
        'address': _opt(address),
        'birthday': birthday == null ? null : dateOnly(birthday!).toIso8601String(),
        'notes': _opt(notes),
        'appointmentId': appointmentId,
      };

  factory Contact.fromMap(Map<String, dynamic> m) => Contact(
        id: m['id'] as int?,
        userid: m['userid'] as int,
        name: m['name'] as String? ?? '',
        nickname: m['nickname'] as String?,
        relation: m['relation'] as String?,
        phone: m['phone'] as String?,
        email: m['email'] as String?,
        address: m['address'] as String?,
        birthday: m['birthday'] == null ? null : DateTime.tryParse(m['birthday'] as String),
        notes: m['notes'] as String?,
        appointmentId: m['appointmentId'] as int?,
      );
}

String? _opt(String? s) => (s == null || s.trim().isEmpty) ? null : s.trim();

/// Eine Notiz zu einer Person, optional mit Datum („hat Mittwoch einen Arzttermin“). Datierte
/// Notizen erinnern am Tag um 9 Uhr und mit [followUp] am Tag danach ans Nachfragen.
class ContactNote {
  final int? id;
  final int userid;
  final int contactId;
  final String text;
  final DateTime? date;
  final bool followUp;
  final bool done;
  final DateTime created;

  /// Name der Person – nur bei Abfragen über alle Kontakte (Heute) gefüllt.
  final String? contactName;

  const ContactNote({
    this.id,
    required this.userid,
    required this.contactId,
    required this.text,
    this.date,
    this.followUp = false,
    this.done = false,
    required this.created,
    this.contactName,
  });

  ContactNote copyWith({int? id, bool? done, String? text, DateTime? date, bool clearDate = false, bool? followUp}) => ContactNote(
        id: id ?? this.id,
        userid: userid,
        contactId: contactId,
        text: text ?? this.text,
        date: clearDate ? null : date ?? this.date,
        followUp: followUp ?? this.followUp,
        done: done ?? this.done,
        created: created,
        contactName: contactName,
      );

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'userid': userid,
        'contactId': contactId,
        'text': text.trim(),
        'date': date == null ? null : dateOnly(date!).toIso8601String(),
        'followUp': followUp && date != null ? 1 : 0,
        'done': done ? 1 : 0,
        'created': created.toIso8601String(),
      };

  factory ContactNote.fromMap(Map<String, dynamic> m) => ContactNote(
        id: m['id'] as int?,
        userid: m['userid'] as int,
        contactId: m['contactId'] as int,
        text: m['text'] as String? ?? '',
        date: m['date'] == null ? null : DateTime.tryParse(m['date'] as String),
        followUp: m['followUp'] == 1,
        done: m['done'] == 1,
        created: DateTime.tryParse(m['created'] as String? ?? '') ?? DateTime(2000),
        contactName: m['contactName'] as String?,
      );
}
