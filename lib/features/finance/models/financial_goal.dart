class FinancialGoal {
  final int? id;
  final String name;
  final double targetAmount;
  final String selectedAccountNames; // JSON string of account names or comma-separated
  final String colorHex;
  final String? deadline;
  final int userid;

  FinancialGoal({
    this.id,
    required this.name,
    required this.targetAmount,
    required this.selectedAccountNames,
    required this.colorHex,
    this.deadline,
    required this.userid,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'targetAmount': targetAmount,
      'selectedAccountNames': selectedAccountNames,
      'colorHex': colorHex,
      'deadline': deadline,
      'userid': userid,
    };
  }

  List<String> get accountNames =>
      selectedAccountNames.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();

  factory FinancialGoal.fromMap(Map<String, dynamic> map) {
    return FinancialGoal(
      id: map['id'],
      name: map['name'],
      targetAmount: (map['targetAmount'] as num?)?.toDouble() ?? 0,
      selectedAccountNames: map['selectedAccountNames'],
      colorHex: map['colorHex'],
      deadline: map['deadline'],
      userid: map['userid'],
    );
  }
}
