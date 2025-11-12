// lib/features/tuner/application/debug.dart
//
// Debugging utilities for pitch detection engine.
// Provides structured logging and debug data collection.

import 'dart:math' as math;

/// Debug information collected per frame during pitch detection
class PitchDebug {
  final double rms;
  final double dbfs;
  final int fftLen;
  final double binHz;
  final int bandMinIdx;
  final int bandMaxIdx;
  final int hpsOrderUsed;
  final int peakBin;
  final double peakBinInterp;
  final double f0Raw;
  final double f0Interp;
  final double fAfterSnap;   // after harmonic snap, before smoothing
  final bool octaveCorrected;
  final double hpsPeak;
  final double hpsMedian;
  final double prominence;
  final double confidence;
  final double fsCorrection; // current effective FS correction
  final double tiltAlpha;
  final double preEmphasis;
  final double levelDbGate;

  const PitchDebug({
    required this.rms,
    required this.dbfs,
    required this.fftLen,
    required this.binHz,
    required this.bandMinIdx,
    required this.bandMaxIdx,
    required this.hpsOrderUsed,
    required this.peakBin,
    required this.peakBinInterp,
    required this.f0Raw,
    required this.f0Interp,
    required this.fAfterSnap,
    required this.octaveCorrected,
    required this.hpsPeak,
    required this.hpsMedian,
    required this.prominence,
    required this.confidence,
    required this.fsCorrection,
    required this.tiltAlpha,
    required this.preEmphasis,
    required this.levelDbGate,
  });
}

/// Helper class for tracking HPS peak information
class PeakInfo {
  final double freq;
  final double value;
  const PeakInfo({required this.freq, required this.value});
}

/// Structured logger for pitch detection engine
class PitchLogger {
  bool enabled = false;          // enable structured logging
  int logEveryN = 1;             // print every N frames (1 = every frame)
  int logTopPeaks = 0;           // include top K HPS peaks (0 = disabled)
  int _frameCounter = 0;         // internal frame counter

  /// Check if logging should happen for current frame
  bool shouldLog() {
    _frameCounter++;
    return enabled && (_frameCounter % logEveryN == 0);
  }

  /// Log level gate (frame dropped due to low level)
  void logLevelGate(double dbfs, double gate, double rms) {
    print('TUNER gate: level dbfs=${dbfs.toStringAsFixed(1)} gate=${gate.toStringAsFixed(1)} rms=${rms.toStringAsFixed(4)}');
  }

  /// Log band too small (frame dropped due to insufficient frequency range)
  void logBandTooSmall(int minIdx, int maxIdx, double binHz, int fftLen) {
    print('TUNER gate: bandTooSmall minIdx=$minIdx maxIdx=$maxIdx binHz=${binHz.toStringAsFixed(3)} fftLen=$fftLen');
  }

  /// Log low confidence (frame dropped due to weak peak)
  void logLowConfidence(double confidence, double prominence, double dbfs, double binHz, int fftLen) {
    print('TUNER gate: lowConf conf=${confidence.toStringAsFixed(2)} prom=${prominence.toStringAsFixed(2)} dbfs=${dbfs.toStringAsFixed(1)} binHz=${binHz.toStringAsFixed(3)} fftLen=$fftLen');
  }

  /// Log successful pitch detection with all details
  void logSuccess({
    required double? targetHz,
    required int snapK,
    required double snapErr,
    required double f0Raw,
    required double f0Interp,
    required double fCandidate,
    required double f0Sm,
    required double rms,
    required double db,
    required double confidence,
    required double prominence,
    required int order,
    required int iGlob,
    required double binHz,
    required int fftLen,
    required double sampleRateCorrection,
    required bool octaveCorrected,
    required double tiltAlpha,
    required double preEmphasis,
    required double levelDbGate,
    required int minIdx,
    required int maxIdx,
    List<double>? hps,
  }) {
    // Compute cents UI if target is known
    double centsUi = 0.0;
    if (targetHz != null && targetHz > 0) {
      final ratio = f0Sm / targetHz;
      centsUi = 1200.0 * (math.log(ratio) / math.ln2);
    }

    final StringBuffer sb = StringBuffer();
    sb.write('TUNER: ');
    sb.write('f_tgt=${targetHz?.toStringAsFixed(2) ?? "null"} ');
    sb.write('snapK=$snapK snapErr=${snapErr.toStringAsFixed(3)} ');
    sb.write('f_raw=${f0Raw.toStringAsFixed(3)} ');
    sb.write('f_interp=${f0Interp.toStringAsFixed(3)} ');
    sb.write('f_snap=${fCandidate.toStringAsFixed(3)} ');
    sb.write('f_med=${f0Sm.toStringAsFixed(3)} ');
    sb.write('cents_ui=${centsUi.toStringAsFixed(1)} ');
    sb.write('RMS=${rms.toStringAsFixed(4)} ');
    sb.write('dBFS=${db.toStringAsFixed(1)} ');
    sb.write('conf=${confidence.toStringAsFixed(2)} ');
    sb.write('prom=${prominence.toStringAsFixed(2)} ');
    sb.write('HPSord=$order ');
    sb.write('peakBin=$iGlob ');
    sb.write('binHz=${binHz.toStringAsFixed(3)} ');
    sb.write('fftLen=$fftLen ');
    sb.write('fsCorr=${sampleRateCorrection.toStringAsFixed(6)} ');
    sb.write('octFix=${octaveCorrected ? 1 : 0} ');
    sb.write('tiltAlpha=${tiltAlpha.toStringAsFixed(2)} ');
    sb.write('preEmph=${preEmphasis.toStringAsFixed(2)} ');
    sb.write('gate=${levelDbGate.toStringAsFixed(1)} ');
    sb.write('band=[$minIdx..$maxIdx]');

    // Optional: include top HPS peaks
    if (logTopPeaks > 0 && hps != null && hps.isNotEmpty) {
      final topPeaks = _findTopPeaks(hps, logTopPeaks, minIdx, binHz);
      if (topPeaks.isNotEmpty) {
        sb.write(' peaks=[');
        sb.write(topPeaks.map((p) => '${p.freq.toStringAsFixed(1)}:${p.value.toStringAsFixed(2)}').join(','));
        sb.write(']');
      }
    }

    print(sb.toString());
  }

  /// Find top K peaks in HPS spectrum for logging
  List<PeakInfo> _findTopPeaks(List<double> hps, int k, int minIdx, double binHz) {
    if (hps.isEmpty || k <= 0) return [];
    
    final List<PeakInfo> peaks = [];
    for (int i = 0; i < hps.length; i++) {
      final freq = (minIdx + i) * binHz;
      peaks.add(PeakInfo(freq: freq, value: hps[i]));
    }
    
    // Sort by value descending
    peaks.sort((a, b) => b.value.compareTo(a.value));
    
    // Return top K
    return peaks.take(k).toList();
  }
}
