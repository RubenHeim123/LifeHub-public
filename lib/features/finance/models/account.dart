class Account {
  final String accountName;
  final int accountUserid;
  final String accountFontFamily;
  final String accountIconName;
  final int accountCodePoint;
  final double accountAmount;
  final int? id;
  Account({
    this.id,
    required this.accountName,
    required this.accountUserid,
    required this.accountFontFamily,
    required this.accountIconName,
    required this.accountCodePoint,
    required this.accountAmount,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'accountName': accountName,
      'accountUserid': accountUserid,
      'accountCodePoint': accountCodePoint,
      'accountFontFamily': accountFontFamily,
      'accountIconName': accountIconName,
      'accountAmount': accountAmount,
    };
  }

  factory Account.fromMap(Map<String, dynamic> map) {
    return Account(
      id: map['id'],
      accountName: map['accountName'],
      accountUserid: map['accountUserid'],
      accountCodePoint: map['accountCodePoint'],
      accountFontFamily: map['accountFontFamily'],
      accountIconName: map['accountIconName'],
      accountAmount: (map['accountAmount'] as num).toDouble(),
    );
  }
}
