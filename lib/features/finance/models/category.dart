import 'package:frontend/features/finance/models/transaction_type.dart';

class Category {
  final String categoryName;
  final int categoryUserid;
  final String categoryFontFamily;
  final String categoryIconName;
  final int categoryCodePoint;
  final TransactionType transactionType;
  final double monthlyBudget;
  final int? id;
  Category({
    required this.transactionType,
    this.monthlyBudget = 0.0,
    this.id,
    required this.categoryName,
    required this.categoryUserid,
    required this.categoryFontFamily,
    required this.categoryCodePoint,
    required this.categoryIconName,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'categoryName': categoryName,
      'categoryUserid': categoryUserid,
      'categoryFontFamily': categoryFontFamily,
      'categoryIconName': categoryIconName,
      'categoryCodePoint': categoryCodePoint,
      'transactionType': transactionType.dbValue,
      'monthlyBudget': monthlyBudget,
    };
  }

  factory Category.fromMap(Map<String, dynamic> map) {
    return Category(
      id: map['id'],
      categoryName: map['categoryName'],
      categoryUserid: map['categoryUserid'],
      categoryFontFamily: map['categoryFontFamily'],
      categoryIconName: map['categoryIconName'],
      categoryCodePoint: map['categoryCodePoint'],
      transactionType: TransactionType.fromDb(map['transactionType']),
      monthlyBudget: map['monthlyBudget']?.toDouble() ?? 0.0,
    );
  }
}
