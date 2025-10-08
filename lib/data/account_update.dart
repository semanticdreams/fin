class AccountUpdate {
  const AccountUpdate({
    this.id,
    required this.accountId,
    required this.previousBalance,
    required this.newBalance,
    required this.updatedAt,
  });

  final int? id;
  final int accountId;
  final double previousBalance;
  final double newBalance;
  final DateTime updatedAt;

  AccountUpdate copyWith({
    int? id,
    int? accountId,
    double? previousBalance,
    double? newBalance,
    DateTime? updatedAt,
  }) {
    return AccountUpdate(
      id: id ?? this.id,
      accountId: accountId ?? this.accountId,
      previousBalance: previousBalance ?? this.previousBalance,
      newBalance: newBalance ?? this.newBalance,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  factory AccountUpdate.fromMap(Map<String, Object?> map) {
    return AccountUpdate(
      id: map['id'] as int?,
      accountId: map['account_id'] as int,
      previousBalance: (map['previous_balance'] as num).toDouble(),
      newBalance: (map['new_balance'] as num).toDouble(),
      updatedAt: DateTime.parse(map['updated_at'] as String),
    );
  }

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'id': id,
      'account_id': accountId,
      'previous_balance': previousBalance,
      'new_balance': newBalance,
      'updated_at': updatedAt.toIso8601String(),
    };
  }
}
