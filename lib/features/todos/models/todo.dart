import 'package:frontend/core/models/repeat.dart';

class Todo {
  final int? id;
  final String title;
  final String? description;

  /// Fälligkeit; eine Uhrzeit ungleich 0:00 ist die Erinnerungszeit.
  final DateTime? dueDate;
  final bool isCompleted;
  final int userid;

  /// Schritt eines Ziel-Plans, zu dem die Aufgabe gehört (optional).
  final int? goalStepId;

  /// Wiederholung, z. B. „jeden Freitag“ oder „alle 2 Wochen“. Beim Abhaken entsteht das
  /// nächste Vorkommen als neue Aufgabe; erledigte bleiben als Verlauf stehen.
  final Repeat repeat;

  /// Erstes Datum der Serie – Bezugspunkt für Intervalle wie „alle 2 Wochen“.
  final DateTime? repeatStart;

  /// ID der ersten Aufgabe der Serie (alle Vorkommen teilen sie).
  final int? seriesId;

  Todo({
    this.id,
    required this.title,
    this.description,
    this.dueDate,
    this.isCompleted = false,
    required this.userid,
    this.goalStepId,
    this.repeat = Repeat.none,
    this.repeatStart,
    this.seriesId,
  });

  bool get repeats => !repeat.isNone && dueDate != null;

  /// Nächstes Vorkommen nach diesem (gleiche Uhrzeit), `null` ohne Wiederholung.
  DateTime? get nextDue {
    final due = dueDate;
    if (!repeats || due == null) return null;
    final next = repeat.nextAfter(repeatStart ?? due, due);
    return next == null ? null : DateTime(next.year, next.month, next.day, due.hour, due.minute);
  }

  Todo copyWith({
    bool? isCompleted,
    DateTime? dueDate,
    int? seriesId,
    bool clearId = false,
  }) =>
      Todo(
        id: clearId ? null : id,
        title: title,
        description: description,
        dueDate: dueDate ?? this.dueDate,
        isCompleted: isCompleted ?? this.isCompleted,
        userid: userid,
        goalStepId: goalStepId,
        repeat: repeat,
        repeatStart: repeatStart,
        seriesId: seriesId ?? this.seriesId,
      );

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'description': description,
      'dueDate': dueDate?.toIso8601String(),
      'isCompleted': isCompleted ? 1 : 0,
      'userid': userid,
      'goalStepId': goalStepId,
      'repeat': repeat.toDb(),
      'repeatStart': repeatStart?.toIso8601String(),
      'seriesId': seriesId,
    };
  }

  factory Todo.fromMap(Map<String, dynamic> map) {
    return Todo(
      id: map['id'],
      title: map['title'],
      description: map['description'],
      dueDate: map['dueDate'] != null ? DateTime.parse(map['dueDate']) : null,
      isCompleted: map['isCompleted'] == 1,
      userid: map['userid'],
      goalStepId: map['goalStepId'] as int?,
      repeat: Repeat.fromDb(map['repeat']),
      repeatStart: map['repeatStart'] != null ? DateTime.parse(map['repeatStart']) : null,
      seriesId: map['seriesId'] as int?,
    );
  }
}
