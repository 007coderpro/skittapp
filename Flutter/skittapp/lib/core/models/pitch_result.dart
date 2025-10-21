import 'package:json_annotation/json_annotation.dart';

part 'pitch_result.g.dart';

/// Tulokset f0-analyysistä Pythonilta
@JsonSerializable()
class PitchResult {
  /// Perustaajuus (Hz), null jos ei havaittu
  final double? f0;

  /// Luotettavuus [0.0, 1.0]
  final double confidence;

  /// Lähin nuotti (esim. "A4")
  final String? note;

  /// Poikkeama senteissä [-50, +50]
  final double? cents;

  PitchResult({
    required this.f0,
    required this.confidence,
    this.note,
    this.cents,
  });

  factory PitchResult.fromJson(Map<String, dynamic> json) =>
      _$PitchResultFromJson(json);

  Map<String, dynamic> toJson() => _$PitchResultToJson(this);

  @override
  String toString() {
    return 'PitchResult(f0: $f0, confidence: $confidence, note: $note, cents: $cents)';
  }
}
