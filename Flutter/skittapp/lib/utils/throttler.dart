import 'dart:async';

/// Throttler rajoittaa funktion kutsutaajuutta
class Throttler {
  final Duration delay;
  Timer? _timer;
  bool _isReady = true;

  Throttler({required this.delay});

  /// Suorita funktio throttlattuna
  void run(void Function() action) {
    if (_isReady) {
      action();
      _isReady = false;
      
      _timer?.cancel();
      _timer = Timer(delay, () {
        _isReady = true;
      });
    }
  }

  /// Peruuta odottavat timerit
  void dispose() {
    _timer?.cancel();
  }
}
