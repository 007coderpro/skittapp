import 'package:flutter/foundation.dart';

/// Yksinkertainen logger
class Logger {
  final String tag;

  Logger(this.tag);

  void debug(String message) {
    if (kDebugMode) {
      print('[$tag] DEBUG: $message');
    }
  }

  void info(String message) {
    print('[$tag] INFO: $message');
  }

  void warning(String message) {
    print('[$tag] WARNING: $message');
  }

  void error(String message, [Object? error, StackTrace? stackTrace]) {
    print('[$tag] ERROR: $message');
    if (error != null) {
      print('  Error: $error');
    }
    if (stackTrace != null) {
      print('  StackTrace: $stackTrace');
    }
  }
}
