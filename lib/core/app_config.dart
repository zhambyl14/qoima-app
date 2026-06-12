/// Central delivery configuration.
/// To enable paid delivery: change deliveryFee to e.g. 1500.
/// No other code changes required.
class AppConfig {
  AppConfig._();

  /// Delivery fee in ₸. 0 = free delivery.
  static const double deliveryFee = 0;

  /// Whether the "Delivery" option is shown to clients at all.
  static const bool deliveryEnabled = true;
}
