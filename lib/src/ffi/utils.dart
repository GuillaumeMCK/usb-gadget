/// Extension for converting flag lists to bitmasks.
extension FlagListExt<T extends Flag> on List<T> {
  int toBitmask() => fold(0, (acc, flag) => acc | flag.value);
}

/// Base class for enum-based flags.
abstract class Flag {
  const Flag(this.value);

  final int value;
}
