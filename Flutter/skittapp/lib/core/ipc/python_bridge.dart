import 'dart:typed_data';

class PitchResult {
  final double? f0;          // placeholder, ei käytössä vielä
  final double confidence;   // placeholder
  final double rms;          // esimerkkikenttä testausta varten
  final String? note;        // placeholder
  final double? cents;       // placeholder

  PitchResult({
    required this.f0,
    required this.confidence,
    required this.rms,
    required this.note,
    required this.cents,
  });

  factory PitchResult.fromJson(Map<String, dynamic> j) => PitchResult(
    f0: (j['f0'] as num?)?.toDouble(),
    confidence: (j['confidence'] as num?)?.toDouble() ?? 0.0,
    rms: (j['rms'] as num?)?.toDouble() ?? 0.0,
    note: j['note'] as String?,
    cents: (j['cents'] as num?)?.toDouble(),
  );

  @override
  String toString() {
    return 'PitchResult(f0: $f0, confidence: $confidence, rms: $rms, note: $note, cents: $cents)';
  }
}

abstract class PythonBridge {
  Future<void> start();
  Future<PitchResult?> processFrame(Uint8List pcmInt16, {required int sampleRate});
  Future<void> stop();
}
