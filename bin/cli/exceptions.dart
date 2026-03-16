/// Thrown when a runtime gadget operation fails (register, bind, remove).
class GadgetException implements Exception {
  const GadgetException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Thrown when a YAML config file is missing, malformed, or semantically invalid.
class ConfigException implements Exception {
  const ConfigException(this.message);

  final String message;

  @override
  String toString() => message;
}
