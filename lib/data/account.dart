class Account {
  const Account({
    this.id,
    required this.name,
    required this.balance,
    required this.currency,
  });

  final int? id;
  final String name;
  final double balance;
  final String currency;

  Account copyWith({
    int? id,
    String? name,
    double? balance,
    String? currency,
  }) {
    return Account(
      id: id ?? this.id,
      name: name ?? this.name,
      balance: balance ?? this.balance,
      currency: currency ?? this.currency,
    );
  }

  factory Account.fromMap(Map<String, Object?> map) {
    return Account(
      id: map['id'] as int?,
      name: map['name'] as String,
      balance: (map['balance'] as num).toDouble(),
      currency: map['currency'] as String,
    );
  }

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'id': id,
      'name': name,
      'balance': balance,
      'currency': currency,
    };
  }
}
