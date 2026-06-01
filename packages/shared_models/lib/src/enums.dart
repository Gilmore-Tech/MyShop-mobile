/// Driver availability status
enum DriverStatus {
  offline,
  online,
  busy;

  bool get isOnline => this == DriverStatus.online;
  bool get isOffline => this == DriverStatus.offline;
  bool get isBusy => this == DriverStatus.busy;
}

/// Payment method types
enum PaymentMethod {
  momo,
  cash,
  card;
}
