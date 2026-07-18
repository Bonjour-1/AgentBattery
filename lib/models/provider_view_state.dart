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
    this.monthlyUsage = 0,
    this.status = ConnectionStatus.cached,
    this.message = '缓存数据',
  });
  final String id;
  final String name;
  final double? balance;
  final double dailyUsage;
  final double monthlyUsage;
  final ConnectionStatus status;
  final String message;

  ProviderViewState copyWith({
    double? balance,
    bool clearBalance = false,
    double? dailyUsage,
    double? monthlyUsage,
    ConnectionStatus? status,
    String? message,
  }) => ProviderViewState(
    id: id,
    name: name,
    balance: clearBalance ? null : balance ?? this.balance,
    dailyUsage: dailyUsage ?? this.dailyUsage,
    monthlyUsage: monthlyUsage ?? this.monthlyUsage,
    status: status ?? this.status,
    message: message ?? this.message,
  );
}
