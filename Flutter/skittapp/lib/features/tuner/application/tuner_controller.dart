import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import '../../../core/audio/audio_recorder.dart';
import '../../../core/ipc/python_bridge.dart';

/// Ei UI:ta – vain putki audiosta Pythonille. Voit lukea viimeisimmän tilan UI:ssa.
class TunerController extends ChangeNotifier {
  final AudioRecorderService recorder;
  final PythonBridge bridge;

  StreamSubscription<Uint8List>? _sub;
  bool _busy = false;

  // Viimeisin tulos (placeholder)
  double? lastF0;
  double lastRms = 0.0;
  double lastConfidence = 0.0;
  String? lastNote;
  double? lastCents;

  TunerController({required this.recorder, required this.bridge});

  Future<void> start() async {
    await bridge.start();
    await recorder.start();
    _sub = recorder.frames.listen((frame) async {
      if (_busy) return;        // pudota jos pyyntö kesken (latenssin minimoimiseksi)
      _busy = true;
      try {
        final res = await bridge.processFrame(frame, sampleRate: recorder.sampleRate);
        if (res != null) {
          lastF0 = res.f0;
          lastRms = res.rms;
          lastConfidence = res.confidence;
          lastNote = res.note;
          lastCents = res.cents;
          notifyListeners();
        }
      } catch (_) {
        // swallow or log
      } finally {
        _busy = false;
      }
    });
  }

  Future<void> stop() async {
    await _sub?.cancel();
    await recorder.stop();
    await bridge.stop();
  }

  @override
  void dispose() {
    stop();
    super.dispose();
  }
}

