enum UsagePeriod { daily, monthly }

class ProviderUsage {
  const ProviderUsage({
    this.date,
    this.month,
    this.lastBalance,
    this.dailyUsage = 0,
    this.monthlyUsage = 0,
  });

  final String? date;
  final String? month;
  final double? lastBalance;
  final double dailyUsage;
  final double monthlyUsage;

  ProviderUsage withDailyUsage(double amount) => ProviderUsage(
    date: date,
    month: month,
    lastBalance: lastBalance,
    dailyUsage: _manualAmount(amount),
    monthlyUsage: monthlyUsage,
  );

  ProviderUsage withMonthlyUsage(double amount) => ProviderUsage(
    date: date,
    month: month,
    lastBalance: lastBalance,
    dailyUsage: dailyUsage,
    monthlyUsage: _manualAmount(amount),
  );

  ProviderUsage recordBalance(double balance, DateTime now) {
    final today = _date(now);
    final currentMonth = today.substring(0, 7);
    var daily = date == today ? dailyUsage : 0.0;
    var monthly = month == currentMonth ? monthlyUsage : 0.0;
    if (lastBalance != null && balance < lastBalance!) {
      final spent = _money(lastBalance! - balance);
      daily = _money(daily + spent);
      monthly = _money(monthly + spent);
    }
    return ProviderUsage(
      date: today,
      month: currentMonth,
      lastBalance: balance,
      dailyUsage: daily,
      monthlyUsage: monthly,
    );
  }

  Map<String, Object?> toJson() => {
    'date': date,
    'month': month,
    'last_balance': lastBalance,
    'daily_cumulative': dailyUsage,
    'monthly_cumulative': monthlyUsage,
  };

  factory ProviderUsage.fromJson(Map<String, Object?> json) => ProviderUsage(
    date: json['date'] is String ? json['date'] as String : null,
    month: json['month'] is String ? json['month'] as String : null,
    lastBalance: _number(json['last_balance']),
    dailyUsage: _nonNegative(json['daily_cumulative']),
    monthlyUsage: _nonNegative(json['monthly_cumulative']),
  );

  static String _date(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
  static double _money(double value) => (value * 100).round() / 100;
  static double? _number(Object? value) => value is num
      ? value.toDouble()
      : value is String
      ? double.tryParse(value)
      : null;
  static double _manualAmount(double value) {
    if (!value.isFinite || value < 0) {
      throw ArgumentError.value(
        value,
        'amount',
        'must be a finite non-negative value',
      );
    }
    return _money(value);
  }

  static double _nonNegative(Object? value) {
    final number = _number(value) ?? 0;
    return number < 0 ? 0 : number;
  }
}
