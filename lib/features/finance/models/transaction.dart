import 'package:frontend/features/finance/models/transaction_type.dart';

class Transaction {
  final DateTime date;
  final double amount;
  final String category;
  final String description;
  final String account;
  final TransactionType transactionType;
  final int userid;
  final int? id;
  final String? imagePath;

  Transaction({
    required this.date,
    required this.amount,
    required this.category,
    required this.description,
    required this.account,
    required this.transactionType,
    required this.userid,
    this.id,
    this.imagePath,
  });

  bool get isTransfer => category == kTransferCategory;

  /// Betrag mit Vorzeichen (Ausgaben negativ).
  double get signedAmount => amount * transactionType.sign;

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'date': date.toIso8601String(),
      'amount': amount,
      'category': category,
      'description': description,
      'account': account,
      'transactionType': transactionType.dbValue,
      'userid': userid,
      'imagePath': imagePath,
    };
  }

  factory Transaction.fromMap(Map<String, dynamic> map) {
    return Transaction(
      id: map['id'],
      date: DateTime.parse(map['date']),
      amount: (map['amount'] as num).toDouble(),
      category: map['category'],
      description: map['description'] ?? '',
      account: map['account'],
      transactionType: TransactionType.fromDb(map['transactionType']),
      userid: map['userid'],
      imagePath: map['imagePath'],
    );
  }
}
