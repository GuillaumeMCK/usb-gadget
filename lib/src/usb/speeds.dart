/// USB speed levels.
///
/// Defines the different USB speed modes that affect endpoint configuration,
/// packet sizes, and polling intervals.
enum USBSpeed {
  /// Full-Speed (USB 1.1, 12 Mbps).
  ///
  /// Original USB speed supporting:
  /// - Control: 8/16/32/64 byte packets
  /// - Bulk: 8/16/32/64 byte packets
  /// - Interrupt: 1-64 byte packets, 1ms polling
  /// - Isochronous: 1-1023 byte packets, 1ms polling
  fullSpeed,

  /// High-Speed (USB 2.0, 480 Mbps).
  ///
  /// Enhanced speed supporting:
  /// - Control: 64 byte packets
  /// - Bulk: 512 byte packets
  /// - Interrupt: 1-1024 byte packets, 125μs-4096ms
  /// - Isochronous: 1-1024 byte packets, up to 3 per microframe
  highSpeed,

  /// SuperSpeed (USB 3.0/3.1, 5-10 Gbps).
  ///
  /// High performance supporting:
  /// - All transfer types: 512 or 1024 byte packets
  /// - Burst transfers for improved throughput
  /// - Stream support for bulk endpoints
  superSpeed,

  /// SuperSpeedPlus (USB 3.2, 10+ Gbps).
  ///
  /// Highest speed supporting same features as SuperSpeed
  /// with doubled bandwidth through multi-lane operation.
  superSpeedPlus;

  /// True if this is Full-Speed.
  bool get isFullSpeed => this == fullSpeed;

  /// True if this is High-Speed.
  bool get isHighSpeed => this == highSpeed;

  /// True if this is SuperSpeed or faster.
  bool get isSuperSpeed => this == superSpeed || this == superSpeedPlus;

  /// True if this is SuperSpeedPlus.
  bool get isSuperSpeedPlus => this == superSpeedPlus;
}
