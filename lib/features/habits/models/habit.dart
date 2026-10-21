import 'dart:convert';

class Habit {
  final int? id;
  final String name;
  final String frequency;
  final int userid;
  final int colorValue;
  final int iconCodePoint;
  final String iconFontFamily;
  final List<int> selectedDays; // 1 = Montag, 7 = Sonntag

  Habit({
    this.id,
    required this.name,
    this.frequency = 'daily',
    required this.userid,
    this.colorValue = 4280391411,
    this.iconCodePoint = 58249,
    this.iconFontFamily = 'MaterialIcons',
    this.selectedDays = const [1, 2, 3, 4, 5, 6, 7],
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'frequency': frequency,
      'userid': userid,
      'colorValue': colorValue,
      'iconCodePoint': iconCodePoint,
      'iconFontFamily': iconFontFamily,
      'selectedDays': jsonEncode(selectedDays),
    };
  }

  factory Habit.fromMap(Map<String, dynamic> map) {
    List<int> parsedDays = [1, 2, 3, 4, 5, 6, 7]; // Fallback to all days
    try {
      if (map['selectedDays'] != null) {
        parsedDays = List<int>.from(jsonDecode(map['selectedDays']));
      } else if (map['frequency'] == 'Wöchentlich') {
          // Backward compatibility fallback for old weekly
          parsedDays = [DateTime.now().weekday]; 
      }
    } catch (e) {
      // Keep default if parsing fails
    }

    return Habit(
      id: map['id'],
      name: map['name'],
      frequency: map['frequency'] ?? 'daily', // Add default to prevent null error if missing
      userid: map['userid'],
      colorValue: map['colorValue'] ?? 4280391411,
      iconCodePoint: map['iconCodePoint'] ?? 58249,
      iconFontFamily: map['iconFontFamily'] ?? 'MaterialIcons',
      selectedDays: parsedDays,
    );
  }
}

