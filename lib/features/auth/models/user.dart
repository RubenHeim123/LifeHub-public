class UserModel {
  final int uid;
  final String? email;
  final String? password;
  final String? displayName;
  final int? age;
  final String? phonenumber;
  final DateTime? createdTime;
  final int experiencePoints;
  final bool isBiometricEnabled;
  
  /// XP, die nötig sind, um von [level] auf das nächste Level aufzusteigen.
  /// Progressiv: Level 1→2 = 100, 2→3 = 150, 3→4 = 200 …
  static int xpForLevelUp(int level) => 100 + 50 * (level - 1);

  /// (Level, XP innerhalb des aktuellen Levels)
  (int, int) get _levelProgress {
    var remaining = experiencePoints < 0 ? 0 : experiencePoints;
    var lvl = 1;
    while (remaining >= xpForLevelUp(lvl)) {
      remaining -= xpForLevelUp(lvl);
      lvl++;
    }
    return (lvl, remaining);
  }

  int get level => _levelProgress.$1;
  int get xpIntoLevel => _levelProgress.$2;
  int get xpForNextLevel => xpForLevelUp(level);

  UserModel({
    required this.uid,
    this.email,
    this.password,
    this.displayName,
    this.age,
    this.phonenumber,
    this.createdTime,
    this.experiencePoints = 0,
    this.isBiometricEnabled = false,
  });

  UserModel copyWith({
    String? email,
    String? displayName,
    int? age,
    String? phonenumber,
    int? experiencePoints,
    bool? isBiometricEnabled,
  }) {
    return UserModel(
      uid: uid,
      email: email ?? this.email,
      password: password,
      displayName: displayName ?? this.displayName,
      age: age ?? this.age,
      phonenumber: phonenumber ?? this.phonenumber,
      createdTime: createdTime,
      experiencePoints: experiencePoints ?? this.experiencePoints,
      isBiometricEnabled: isBiometricEnabled ?? this.isBiometricEnabled,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'uid': uid,
      'email': email,
      'password': password,
      'display_name': displayName,
      'age': age,
      'phonenumber': phonenumber,
      'created_time': createdTime?.toIso8601String(),
      'experiencePoints': experiencePoints,
      'isBiometricEnabled': isBiometricEnabled ? 1 : 0,
    };
  }

  factory UserModel.fromMap(Map<String, dynamic> map) {
    return UserModel(
      uid: map['uid'],
      email: map['email'],
      password: map['password'],
      displayName: map['display_name'],
      age: map['age'],
      phonenumber: map['phonenumber'],
      createdTime: map['created_time'] != null ? DateTime.parse(map['created_time'].toString()) : null,
      experiencePoints: map['experiencePoints'] as int? ?? 0,
      isBiometricEnabled: map['isBiometricEnabled'] == 1,
    );
  }
}

class LoginModel {
  final String email;
  final String password;
  LoginModel({required this.email, required this.password});
}
