## 0.4.3

* **FIX**: Add missing `fatal` method to `Logger` class
* **CHORE**: Update logger exports to include the `Logger` class
* **CHORE**: Remove the `PlatformLogger` export

## 0.4.2

* **CHORE**: Export `ILogger` as public to allow custom mixin creation outside the library.
* **FIX**: Release endpoints on disable to prevent resource leaks.

## 0.4.1

* **FEAT**: Add compile-time environment-based logging configuration.
* **REFACTOR**: Simplify log level representation.
* **REFACTOR**: Enhance log formatting and color handling.
* **FIX**: Replace hardcoded log level with environment-based constant.

## 0.4.0

* **FEAT**: Initial release of the package.
