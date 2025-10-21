import '../../../core/models/pitch_result.dart';

/// Tuner-näkymän tila
class TunerState {
  final bool isRecording;
  final PitchResult? currentPitch;
  final double audioLevel;
  final String? errorMessage;

  const TunerState({
    this.isRecording = false,
    this.currentPitch,
    this.audioLevel = 0.0,
    this.errorMessage,
  });

  TunerState copyWith({
    bool? isRecording,
    PitchResult? currentPitch,
    double? audioLevel,
    String? errorMessage,
  }) {
    return TunerState(
      isRecording: isRecording ?? this.isRecording,
      currentPitch: currentPitch ?? this.currentPitch,
      audioLevel: audioLevel ?? this.audioLevel,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }

  @override
  String toString() {
    return 'TunerState(isRecording: $isRecording, pitch: $currentPitch, level: $audioLevel)';
  }
}
