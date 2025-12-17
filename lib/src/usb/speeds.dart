/// USB speed levels.
///
/// Defines the different USB speed modes that affect endpoint configuration,
/// packet sizes, and polling intervals. Implements [Comparable] to allow
/// speed comparisons (faster > slower).
enum Speed implements Comparable<Speed> {
  /// USB 3.1: 10 Gbit/s.
  superSpeedPlus('super-speed-plus', 6),

  /// USB 3.0: 5 Gbit/s.
  superSpeed('super-speed', 5),

  /// USB 2.0: 480 Mbit/s.
  highSpeed('high-speed', 4),

  /// USB 1.0: 12 Mbit/s.
  fullSpeed('full-speed', 3),

  /// USB 1.0: 1.5 Mbit/s.
  lowSpeed('low-speed', 2),

  /// Unknown speed.
  unknown('UNKNOWN', 0);

  const Speed(this.value, this._priority);

  /// The string value as it appears in sysfs/configfs files.
  final String value;

  /// Priority for comparison (higher = faster).
  final int _priority;

  /// Parses a string value into a [Speed].
  ///
  /// Matches the format used in sysfs/configfs (e.g., "super-speed", "high-speed").
  /// Returns [Speed.unknown] if the string doesn't match any speed.
  static Speed fromString(String value) {
    final trimmed = value.trim();
    return Speed.values.firstWhere(
      (s) => s.value == trimmed,
      orElse: () => Speed.unknown,
    );
  }

  /// True if this is Full-Speed.
  bool get isFullSpeed => this == fullSpeed;

  /// True if this is High-Speed.
  bool get isHighSpeed => this == highSpeed;

  /// True if this is SuperSpeed or faster.
  bool get isSuperSpeed => this == superSpeed || this == superSpeedPlus;

  /// True if this is SuperSpeedPlus.
  bool get isSuperSpeedPlus => this == superSpeedPlus;

  /// True if this is Low-Speed.
  bool get isLowSpeed => this == lowSpeed;

  /// True if speed is unknown.
  bool get isUnknown => this == unknown;

  @override
  int compareTo(Speed other) => _priority.compareTo(other._priority);

  @override
  String toString() => value;
}

// Legacy alias for backwards compatibility
typedef USBSpeed = Speed;
