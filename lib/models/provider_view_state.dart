enum ConnectionStatus {
  cached,
  refreshing,
  connected,
  unavailable,
  noKey,
  error,
}

class ProviderViewState {
  const ProviderViewState({
    required this.id,
    required this.name,
    this.balance,
    this.dailyUsage = 0,
    this.dailyDisplayUsage,
    this.monthlyUsage = 0,
    this.monthlyDisplayUsage,
    this.status = ConnectionStatus.cached,
    this.message = '缓存数据',
  });
  final String id;
  final String name;
  final double? balance;
  final double dailyUsage;

  /// Null means the configured display policy intentionally hides this metric.
  final double? dailyDisplayUsage;
  final double monthlyUsage;

  /// Null means the configured display policy intentionally hides this metric.
  final double? monthlyDisplayUsage;
  final ConnectionStatus status;
  final String message;

  ProviderViewState copyWith({
    double? balance,
    bool clearBalance = false,
    double? dailyUsage,
    double? dailyDisplayUsage,
    bool clearDailyDisplayUsage = false,
    double? monthlyUsage,
    double? monthlyDisplayUsage,
    bool clearMonthlyDisplayUsage = false,
    ConnectionStatus? status,
    String? message,
  }) => ProviderViewState(
    id: id,
    name: name,
    balance: clearBalance ? null : balance ?? this.balance,
    dailyUsage: dailyUsage ?? this.dailyUsage,
    dailyDisplayUsage: clearDailyDisplayUsage
        ? null
        : dailyDisplayUsage ?? this.dailyDisplayUsage,
    monthlyUsage: monthlyUsage ?? this.monthlyUsage,
    monthlyDisplayUsage: clearMonthlyDisplayUsage
        ? null
        : monthlyDisplayUsage ?? this.monthlyDisplayUsage,
    status: status ?? this.status,
    message: message ?? this.message,
  );
}
