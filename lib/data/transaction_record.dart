class TransactionRecord {
  const TransactionRecord({
    this.id,
    required this.title,
    required this.createdAt,
    required this.amount,
    required this.currency,
    required this.accountId,
  });

  final int? id;
  final String title;
  final DateTime createdAt;
  final double amount;
  final String currency;
  final int accountId;

  TransactionRecord copyWith({
    int? id,
    String? title,
    DateTime? createdAt,
    double? amount,
    String? currency,
    int? accountId,
  }) {
    return TransactionRecord(
      id: id ?? this.id,
      title: title ?? this.title,
      createdAt: createdAt ?? this.createdAt,
      amount: amount ?? this.amount,
      currency: currency ?? this.currency,
      accountId: accountId ?? this.accountId,
    );
  }

  factory TransactionRecord.fromMap(Map<String, Object?> map) {
    return TransactionRecord(
      id: map['id'] as int?,
      title: map['title'] as String,
      createdAt: DateTime.parse(map['created_at'] as String),
      amount: (map['amount'] as num).toDouble(),
      currency: (map['currency'] as String).toUpperCase(),
      accountId: map['account_id'] as int,
    );
  }

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'id': id,
      'title': title,
      'created_at': createdAt.toIso8601String(),
      'amount': amount,
      'currency': currency,
      'account_id': accountId,
    };
  }
}
