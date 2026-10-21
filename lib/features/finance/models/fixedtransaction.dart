import 'package:frontend/features/finance/models/recurrence_interval.dart';
import 'package:frontend/features/finance/models/transaction_type.dart';

class FixedTransaction {
  final DateTime startTime;
  final DateTime endTime;
  final DateTime nextTime;
  final RecurrenceInterval interval;
  final double amount;
  final String category;
  final String description;
  final String account;
  final TransactionType transactionType;
  final int userid;
  final int? id;

  FixedTransaction({
    required this.startTime,
    required this.endTime,
    required this.nextTime,
    required this.interval,
    required this.amount,
    required this.category,
    required this.description,
    required this.account,
    required this.transactionType,
    required this.userid,
    this.id,
  });

  bool get isTransfer => category == kTransferCategory;

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'start_time': startTime.toIso8601String(),
      'end_time': endTime.toIso8601String(),
      'next_time': nextTime.toIso8601String(),
      'interval': interval.dbValue,
      'amount': amount,
      'category': category,
      'description': description,
      'account': account,
      'transactionType': transactionType.dbValue,
      'userid': userid,
    };
  }

  factory FixedTransaction.fromMap(Map<String, dynamic> map) {
    return FixedTransaction(
      id: map['id'],
      startTime: DateTime.parse(map['start_time']),
      endTime: DateTime.parse(map['end_time']),
      nextTime: DateTime.parse(map['next_time']),
      interval: RecurrenceInterval.fromDbOrMonthly(map['interval']),
      amount: (map['amount'] as num).toDouble(),
      category: map['category'],
      description: map['description'] ?? '',
      account: map['account'],
      transactionType: TransactionType.fromDb(map['transactionType']),
      userid: map['userid'],
    );
  }
}
