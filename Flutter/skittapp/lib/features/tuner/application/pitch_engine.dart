// lib/features/tuner/application/pitch_engine.dart
//
// HPS pitch detector with *automatic sample-rate correction* when a target is known.
// No user calibration needed.
//
// Additions in this version:
//  • autoFsCorrect: on-frame FS correction using nearest harmonic of target
//  • fsCorrSlew: EMA smoothing of FS correction
//  • wider safe bounds for correction (0.5..1.6) to cover 32k↔48k mismatches
//  • tighter target band (0.80–1.60×) kept
//  • exposes fAfterSnap + current fsCorrection in debug

import 'dart:math' as math;
import 'dart:typed_data';

import 'debug.dart';

class PitchResult {
  final double f0;
  final double cents;
  final double confidence;
  final double rms;
  final String note;

  const PitchResult({
    required this.f0,
    required this.cents,
    required this.confidence,
    required this.rms,
    required this.note,
  });
}

class HpsPitchEngine {
  // Public params
  final int sampleRate;
  final int windowLength;
  final int hpsOrder;
  final double minF;
  final double maxF;
  final double levelDbGate;
  final int smoothCount;
  final int padPow2;
  final double preEmphasis;
  final double tiltAlpha;

  // NEW: automatic FS correction
  bool autoFsCorrect;          // enable automatic runtime FS correction
  double fsCorrSlew;           // EMA smoothing factor (0..1), e.g. 0.2
  double sampleRateCorrection; // effective FS multiplier

  // Logging system
  final PitchLogger logger = PitchLogger();

  final void Function(PitchDebug dbg)? onDebug;

  // Precomputed
  late final List<double> _hann;
  late List<double> _freqs;
  late final int _fftLen;
  late int _minIdx;
  late int _maxIdx;

  // Tiny history for smoothing
  final List<double> _f0History = <double>[];

  HpsPitchEngine({
    required this.sampleRate,
    this.windowLength = 8192,
    this.hpsOrder = 5,
    this.minF = 70.0,
    this.maxF = 500.0,
    this.levelDbGate = -35.0,
    this.smoothCount = 5,
    this.padPow2 = 2,
    this.preEmphasis = 0.97,
    this.tiltAlpha = 0.0,
    this.autoFsCorrect = false,
    this.fsCorrSlew = 0.05,
    this.sampleRateCorrection = 1.0,
    this.onDebug,
  }) {
    assert(_isPowerOfTwo(windowLength), 'windowLength must be a power of two');
    assert(smoothCount >= 1 && smoothCount <= 9 && smoothCount % 2 == 1, 'smoothCount must be odd (e.g., 3/5/7)');
    _fftLen = windowLength << padPow2;
    _hann = _makeHann(windowLength);
    _rebuildFreqs();
  }

  void setSampleRateCorrection(double corr) {
    sampleRateCorrection = corr.clamp(0.98, 1.02); // widened bounds to cover 32k↔48k
    _rebuildFreqs();
  }

  void resetSmoother() => _f0History.clear();

  PitchResult? processPcm16Le(
    Uint8List pcm16Le, {
    double? targetHz,
    bool narrowSearchToTarget = false,
    double targetHarmTol = 0.05, // tighter snap tolerance
  }) {
    final shouldLog = logger.shouldLog();

    // ----- PCM -> mono float
    final samples = _pcm16leToMonoFloat(pcm16Le);

    // ----- Fixed analysis window
    final frame = _padOrTrim(samples, windowLength);

    // ----- Level gate
    final rms = _rms(frame);
    final db = 20.0 * math.log(rms + 1e-12) / math.ln10;
    if (db < levelDbGate) {
      if (shouldLog) {
        logger.logLevelGate(db, levelDbGate, rms);
      }
      return null;
    }

    // ----- Pre-conditioning
    _dcRemove(frame);
    if (preEmphasis != 0.0) _preEmphasis(frame, preEmphasis);

    // ----- Window + zero-pad
    final buf = List<double>.filled(_fftLen, 0.0);
    for (int i = 0; i < windowLength; i++) {
      buf[i] = frame[i] * _hann[i];
    }

    // ----- rFFT magnitude
    final spec = _rfftLen(buf, _fftLen);
    final mag  = List<double>.generate(spec.length, (i) => spec[i].abs());

    // ----- Band-limit (optionally narrow around target)
    int minIdx = _minIdx;
    int maxIdx = math.min(_maxIdx, mag.length);

    if (narrowSearchToTarget && targetHz != null && targetHz > 0) {
      final fs = sampleRate * sampleRateCorrection;
      final binHz = fs / _fftLen;
      final minF = (targetHz * 0.80);
      final maxF = (targetHz * 1.60);
      final a = (minF / binHz).floor().clamp(0, mag.length - 1);
      final b = (maxF / binHz).ceil().clamp(0, mag.length);
      if (b > a + 8) { minIdx = a; maxIdx = b; }
    }

    if (maxIdx <= minIdx + 2) {
      if (shouldLog) {
        final fsEff = sampleRate * sampleRateCorrection;
        final double binHz = fsEff / _fftLen;
        logger.logBandTooSmall(minIdx, maxIdx, binHz, _fftLen);
      }
      return null;
    }
    final band = mag.sublist(minIdx, maxIdx);

    final fsEff = sampleRate * sampleRateCorrection;
    final double binHz = fsEff / _fftLen;
    _notchHumBand(band, binHz, minIdx);

    // Optional tilt comp
    if (tiltAlpha != 0.0) _tiltCompensate(band, tiltAlpha);

    // ----- HPS fold
    List<double> hps = List<double>.from(band);
    final usableOrder = _maxUsableHpsOrder(band.length);
    final order = math.min(hpsOrder, usableOrder);
    for (int p = 2; p <= order; p++) {
      final down = _downsample(band, p);
      final L = math.min(hps.length, down.length);
      for (int i = 0; i < L; i++) hps[i] *= down[i];
      if (L < hps.length) hps = hps.sublist(0, L);
      if (hps.isEmpty) return null;
    }

    // ----- Peak (global bin)
    final iLoc = _argMax(hps);
    int iGlob = minIdx + iLoc;
    final double f0Raw = _freqs[iGlob];

    // ----- Subharmonic fold (/2, /3)
    final beforeOct = iGlob;
    iGlob = _maybeOctaveFoldDown(hps, minIdx, iGlob);
    final bool octaveCorrected = (iGlob != beforeOct);

    // ----- Interpolate on ORIGINAL spectrum (not HPS) using log-parabolic fit
    // This achieves ~0.05–0.15 bin accuracy vs. HPS-based interpolation
    double binInterp = iGlob.toDouble();
    final iInBand = iGlob - minIdx;
    if (iGlob > 0 && iGlob + 1 < mag.length) {
      // log-magnitude around the coarse bin
      final lm1 = math.log(mag[iGlob - 1] + 1e-30);
      final l0  = math.log(mag[iGlob]     + 1e-30);
      final lp1 = math.log(mag[iGlob + 1] + 1e-30);
      final d   = _qintDeltaFromLogs(lm1, l0, lp1);
      binInterp = iGlob + d;
    }

    // ----- Frequency from fractional bin
    final f0Interp = _binToFreq(binInterp);

    // ----- Harmonic snap toward target (if provided)
    double fCandidate = f0Interp;
    int snapK = 1;
    double snapErr = 0.0;

    if (targetHz != null && targetHz > 0) {
      double best = fCandidate;
      double bestErr = double.infinity;
      for (int k = 1; k <= 6; k++) {
        final fk = targetHz * k;
        final err = (fCandidate - fk).abs() / fk;
        if (err < bestErr) {
          bestErr = err;
          best = fCandidate / k;
          snapK = k;
        }
      }
      if (bestErr <= targetHarmTol) {
        fCandidate = best;
        snapErr = bestErr;
      } else {
        snapK = 1;
        snapErr = 0.0;
      }
    }

    // ----- Heuristic confidence
    final median = _median(hps);
    final peakVal = hps[iInBand.clamp(0, hps.length - 1)];
    final prominence = (median > 1e-12) ? (peakVal / median) : (peakVal > 0 ? 10.0 : 0.0);
    final promScore = ((prominence - 1.0) / 9.0).clamp(0.0, 1.0);
    final levelScore = ((db - (levelDbGate)) / 20.0).clamp(0.0, 1.0);
    final confidence = (0.7 * promScore + 0.3 * levelScore).clamp(0.0, 1.0);

    if (confidence < 0.65) {
      if (shouldLog) {
        final fsEff = sampleRate * sampleRateCorrection;
        final double binHz = fsEff / _fftLen;
        logger.logLowConfidence(confidence, prominence, db, binHz, _fftLen);
      }
      return null;
    }

    // ----- Short median smoothing on f0
    _f0History.add(fCandidate);
    if (_f0History.length > smoothCount) _f0History.removeAt(0);
    final f0Sm = _median(_f0History);

    // ----- Structured logging (success case)
    if (shouldLog) {
      final fsEff = sampleRate * sampleRateCorrection;
      final double binHz = fsEff / _fftLen;
      
      logger.logSuccess(
        targetHz: targetHz,
        snapK: snapK,
        snapErr: snapErr,
        f0Raw: f0Raw,
        f0Interp: f0Interp,
        fCandidate: fCandidate,
        f0Sm: f0Sm,
        rms: rms,
        db: db,
        confidence: confidence,
        prominence: prominence,
        order: order,
        iGlob: iGlob,
        binHz: binHz,
        fftLen: _fftLen,
        sampleRateCorrection: sampleRateCorrection,
        octaveCorrected: octaveCorrected,
        tiltAlpha: tiltAlpha,
        preEmphasis: preEmphasis,
        levelDbGate: levelDbGate,
        minIdx: minIdx,
        maxIdx: maxIdx,
        hps: hps,
      );
    }

    // ----- Debug callback
    if (onDebug != null) {
      final fsEff = sampleRate * sampleRateCorrection;
      final double binHz = fsEff / _fftLen;
      onDebug!(
        PitchDebug(
          rms: rms,
          dbfs: db,
          fftLen: _fftLen,
          binHz: binHz,
          bandMinIdx: minIdx,
          bandMaxIdx: maxIdx,
          hpsOrderUsed: order,
          peakBin: iGlob,
          peakBinInterp: binInterp,
          f0Raw: f0Raw,
          f0Interp: f0Interp,
          fAfterSnap: fCandidate,
          octaveCorrected: octaveCorrected,
          hpsPeak: peakVal,
          hpsMedian: median,
          prominence: prominence,
          confidence: confidence,
          fsCorrection: sampleRateCorrection,
          tiltAlpha: tiltAlpha,
          preEmphasis: preEmphasis,
          levelDbGate: levelDbGate,
        ),
      );
    }

    // ----- Note mapping
    final noteInfo = _freqToNote(f0Sm);

    return PitchResult(
      f0: f0Sm,
      cents: noteInfo.cents,
      confidence: confidence,
      rms: rms,
      note: '${noteInfo.name}${noteInfo.octave}',
    );
  }

  /// Pressed-note mode with Targeted Harmonic Sum around fTarget.
  /// Keeps your existing FFT plumbing & gating. Returns null if below gate.
  PitchResult? processPcm16LeTargeted(
    Uint8List pcm16Le, {
    required double fTarget,
  }) {
    // ----- PCM -> mono float
    final samples = _pcm16leToMonoFloat(pcm16Le);

    // ----- Fixed analysis window
    final frame = _padOrTrim(samples, windowLength);

    // ----- Level gate
    final rms = _rms(frame);
    final db = 20.0 * math.log(rms + 1e-12) / math.ln10;
    if (db < levelDbGate) return null;

    // ----- Conditioning
    _dcRemove(frame);
    // In pressed-note mode: avoid whitening fundamentals
    if (preEmphasis > 0.0) {
      // Option A: disable fully
      // (do nothing)
    }

    // ----- Window + zero-pad
    final buf = List<double>.filled(_fftLen, 0.0);
    for (int i = 0; i < windowLength; i++) {
      buf[i] = frame[i] * _hann[i];
    }

    // ----- rFFT magnitude
    final spec = _rfftLen(buf, _fftLen);
    final mag  = List<double>.generate(spec.length, (i) => spec[i].abs());

    // ----- Band-limit to your global min/max
    final int minIdx = _minIdx;
    final int maxIdx = math.min(_maxIdx, mag.length);
    if (maxIdx - minIdx < 8) return null; // sanity

    // ----- Tight THS search ±120 cents around the pressed target
    final (double fThs, double sThs, double confThs, double usedH) =
        _thsSearchAroundTarget(mag, fTarget, centsWindow: 120.0, centsStep: 2.0);

    // ----- MPM time-domain cross-check when THS confidence is low
    if (confThs < 0.45) {
      final Float64List x = Float64List.fromList(frame);
      final (double fMpm, double str) = _mpmNearTarget(x, fTarget);
      if (fMpm > 0) {
        // choose the one with better support; otherwise average
        final double centsThs = _centsFromTo(fThs, fTarget).abs();
        final double centsMpm = _centsFromTo(fMpm, fTarget).abs();
        final bool pickMpm = (str >= 0.6 && centsMpm <= centsThs + 10.0);
        final double fBlend = pickMpm ? fMpm : (0.6 * fThs + 0.4 * fMpm);
        final double confBlend = pickMpm ? str : math.max(confThs, str * 0.8);
        return PitchResult(
          f0: fBlend,
          cents: _centsFromTo(fBlend, fTarget),
          confidence: confBlend.clamp(0.0, 1.0),
          rms: rms,
          note: '',
        );
      }
    }

    // ----- Optional: fallback to your existing HPS if THS is weak
    // (kept simple: accept THS if it used >=3 harmonics and conf >= 0.45)
    if (usedH >= 3 && confThs >= 0.45) {
      final double cents = _centsFromTo(fThs, fTarget);
      return PitchResult(
        f0: fThs,
        cents: cents,
        confidence: confThs.clamp(0.0, 1.0),
        rms: rms,
        note: '', // fill at UI: you already know which note is pressed
      );
    }

    // Fallback – run your existing (wide) path and keep it only if near target
    // NOTE: call your current processPcm16Le with narrowSearchToTarget=false
    final fallback = processPcm16Le(
      pcm16Le,
      targetHz: fTarget,
      narrowSearchToTarget: false,
    );
    if (fallback == null) return null;

    // keep fallback only if within ±120 cents; otherwise still return best THS
    if (fallback.cents.abs() <= 120.0) return fallback;

    final double cents = _centsFromTo(fThs, fTarget);
    return PitchResult(
      f0: fThs,
      cents: cents,
      confidence: confThs.clamp(0.0, 1.0),
      rms: rms,
      note: '',
    );
  }

  // ---------- internals ----------

  void _rebuildFreqs() {
    final fs = sampleRate * sampleRateCorrection;
    _freqs = _rfftfreq(_fftLen, 1.0 / fs);
    _minIdx = _searchSorted(_freqs, minF);
    _maxIdx = _searchSorted(_freqs, maxF).clamp(_minIdx + 2, _freqs.length);
  }

  // ==== THS helpers for pressed-note mode ====

  double _binHz() => _freqs.length >= 2 ? (_freqs[1] - _freqs[0]) : 0.0;

  double _localMedian(List<double> mag, int c, {int radius = 3}) {
    final int i0 = (c - radius).clamp(0, mag.length - 1);
    final int i1 = (c + radius).clamp(0, mag.length - 1);
    final List<double> tmp = mag.sublist(i0, i1 + 1)..sort();
    return tmp[tmp.length >> 1];
  }

  /// Weighted harmonic sum with optional local whitening. Returns (score, usedHarmonics).
  (double, double) _thsScore(List<double> mag, double fHz,
      {int maxHarmonics = 10, bool localWhiten = true}) {
    final double fs = sampleRate * sampleRateCorrection;
    final double ny = fs * 0.5;
    if (fHz <= 0 || fHz > ny) return (0.0, 0.0);

    final double binHz = _binHz();
    int K = (ny / fHz).floor();
    if (maxHarmonics > 0) K = K.clamp(1, maxHarmonics);
    double s = 0.0;
    int used = 0;

    for (int k = 1; k <= K; k++) {
      final double fk = k * fHz;
      final double b = fk / binHz;
      final int b0 = b.floor();
      if (b0 < 1 || b0 + 1 >= mag.length) break;
      final double frac = b - b0;
      double mk = (1.0 - frac) * mag[b0] + frac * mag[b0 + 1];

      if (localWhiten) {
        final double med = _localMedian(mag, b0, radius: 3);
        mk = mk / (med + 1e-12);
      }
      s += mk / k; // 1/k weighting
      used++;
    }
    return (used >= 3 ? s : 0.0, used.toDouble());
  }

  double _parabolicRefine(double x1, double y1, double x2, double y2, double x3, double y3) {
    final double denom = (y1 - 2.0 * y2 + y3);
    if (denom.abs() < 1e-15) return x2;
    final double delta = 0.5 * (y1 - y3) / denom;
    return x2 + delta * (x3 - x2);
  }

  double _centsFromTo(double f, double target) => 1200.0 * (math.log(f / target) / math.ln2);

  /// If best is around 0.5× or 2× of target, flip and keep if it wins by a margin.
  double _octaveGuardThs(List<double> mag, double fBest, double fTarget) {
    if (fTarget <= 0) return fBest;
    final double lo = fTarget * 0.45, hi = fTarget * 2.2;
    if (fBest < lo || fBest > hi) return fBest;

    final double margin = 0.07; // require ~7% better score
    final (double sBest, _) = _thsScore(mag, fBest);
    double candidate = fBest;

    if (fBest < fTarget * 0.75) {
      final (double s2, _) = _thsScore(mag, fBest * 2.0);
      if (s2 > sBest * (1.0 + margin)) { candidate = fBest * 2.0; }
    } else if (fBest > fTarget * 1.75) {
      final (double s2, _) = _thsScore(mag, fBest * 0.5);
      if (s2 > sBest * (1.0 + margin)) { candidate = fBest * 0.5; }
    }
    return candidate;
  }

  /// THS grid search ±120 cents around target; returns (fHz, score, conf, usedHarmonics)
  (double, double, double, double) _thsSearchAroundTarget(
      List<double> mag, double fTarget,
      {double centsWindow = 120.0, double centsStep = 2.0}) {
    assert(fTarget > 0);
    final int steps = (centsWindow / centsStep).ceil();
    final List<double> freqs = <double>[];
    final List<double> scores = <double>[];
    final List<double> usedList = <double>[];

    // multiplicative grid in cents
    for (int i = -steps; i <= steps; i++) {
      final double f = fTarget * math.pow(2.0, (i * centsStep) / 1200.0);
      final (double s, double used) = _thsScore(mag, f);
      freqs.add(f);
      scores.add(s);
      usedList.add(used);
    }

    // pick max
    int imax = 0;
    double smax = -1.0;
    for (int i = 0; i < scores.length; i++) {
      if (scores[i] > smax) { smax = scores[i]; imax = i; }
    }
    double fBest = freqs[imax];

    // local parabolic refine (THS curve), if possible
    if (imax > 0 && imax + 1 < scores.length) {
      fBest = _parabolicRefine(freqs[imax - 1], scores[imax - 1],
                               freqs[imax],     scores[imax],
                               freqs[imax + 1], scores[imax + 1]);
    }

    // octave/subharmonic guard
    fBest = _octaveGuardThs(mag, fBest, fTarget);

    // confidence from local contrast around the peak
    final int band = 5;
    double floorSum = 0.0; int floorCnt = 0;
    for (int i = math.max(0, imax - 20); i <= math.min(scores.length - 1, imax + 20); i++) {
      if ((i - imax).abs() <= band) continue;
      floorSum += scores[i];
      floorCnt++;
    }
    final double localFloor = floorCnt > 0 ? (floorSum / floorCnt) : 0.0;
    final double ratio = smax / (localFloor + 1e-9);   // ≥1
    final double conf = ((ratio - 1.0) / (ratio + 1.0)).clamp(0.0, 1.0);

    return (fBest, smax, conf, usedList[imax]);
  }

  // ==== NSDF / MPM near target ====

  int _lagFromHz(double f) {
    final double fs = sampleRate * sampleRateCorrection;
    return (fs / f).round().clamp(2, windowLength - 2);
  }

  double _parabolicAt(List<double> y, int i) {
    if (i <= 0 || i + 1 >= y.length) return i.toDouble();
    final double y1 = y[i - 1], y2 = y[i], y3 = y[i + 1];
    return i + 0.5 * (y1 - y3) / (y1 - 2.0 * y2 + y3);
  }

  /// Returns (fHz, strength) or (0, 0) if not found
  (double, double) _mpmNearTarget(Float64List x, double fTarget,
      {double centsWindow = 120.0}) {
    final double fs = sampleRate * sampleRateCorrection;
    if (fTarget <= 0) return (0.0, 0.0);

    final double fLo = fTarget * math.pow(2.0, -centsWindow / 1200.0);
    final double fHi = fTarget * math.pow(2.0,  centsWindow / 1200.0);
    int lagMin = _lagFromHz(fHi);
    int lagMax = _lagFromHz(fLo);
    lagMin = lagMin.clamp(2, windowLength - 3);
    lagMax = lagMax.clamp(lagMin + 2, windowLength - 2);

    // NSDF (MPM): 2 * sum(x[n]x[n+τ]) / (sum(x[n]^2) + sum(x[n+τ]^2))
    final int N = windowLength - lagMax - 1;
    if (N <= 16) return (0.0, 0.0);

    final List<double> nsdf = List<double>.filled(lagMax + 1, 0.0);
    double sumSq0 = 0.0;
    for (int n = 0; n < N; n++) { final double v = x[n]; sumSq0 += v * v; }

    for (int tau = lagMin; tau <= lagMax; tau++) {
      double ac = 0.0;
      double sumSq1 = 0.0;
      for (int n = 0; n < N; n++) {
        final double a = x[n];
        final double b = x[n + tau];
        ac += a * b;
        sumSq1 += b * b;
      }
      final double denom = sumSq0 + sumSq1 + 1e-12;
      nsdf[tau] = 2.0 * ac / denom;
    }

    // pick best peak
    int imax = lagMin;
    double vmax = -1.0;
    for (int i = lagMin; i <= lagMax; i++) {
      if (nsdf[i] > vmax) { vmax = nsdf[i]; imax = i; }
    }
    final double lagRef = _parabolicAt(nsdf, imax);
    final double fHz = (lagRef > 0.0) ? (fs / lagRef) : 0.0;
    return (fHz, vmax.clamp(0.0, 1.0));
  }

  static bool _isPowerOfTwo(int x) => x > 0 && (x & (x - 1)) == 0;

  static List<double> _makeHann(int n) {
    final w = List<double>.filled(n, 0.0);
    if (n <= 1) return w;
    for (int i = 0; i < n; i++) {
      w[i] = 0.5 * (1.0 - math.cos((2.0 * math.pi * i) / (n - 1)));
    }
    return w;
  }

  static List<double> _pcm16leToMonoFloat(Uint8List bytes) {
    final len = bytes.lengthInBytes ~/ 2;
    final out = List<double>.filled(len, 0.0);
    final bd = bytes.buffer.asByteData();
    for (int i = 0; i < len; i++) {
      final v = bd.getInt16(i * 2, Endian.little);
      out[i] = (v / 32768.0).clamp(-1.0, 1.0);
    }
    return out;
  }

  static List<double> _padOrTrim(List<double> x, int n) {
    if (x.length == n) return List<double>.from(x);
    if (x.length > n) return x.sublist(0, n);
    final out = List<double>.filled(n, 0.0);
    for (int i = 0; i < x.length; i++) out[i] = x[i];
    return out;
  }

  static double _rms(List<double> x) {
    double s = 0.0;
    for (final v in x) s += v * v;
    return math.sqrt(s / (x.isEmpty ? 1 : x.length));
  }

  static void _dcRemove(List<double> x) {
    double m = 0.0; for (final v in x) m += v;
    m /= (x.isEmpty ? 1 : x.length);
    for (int i = 0; i < x.length; i++) x[i] -= m;
  }

  static void _preEmphasis(List<double> x, double a) {
    double prev = x[0];
    for (int i = 1; i < x.length; i++) {
      final cur = x[i];
      x[i] = cur - a * prev;
      prev = cur;
    }
  }

  void _notchHumBand(List<double> band, double binHz, int minIdx) {
    const List<double> hums = [50.0, 60.0, 100.0, 120.0, 150.0, 180.0, 200.0];
    final int halfWidthBins = (1.0 / binHz).ceil(); // ~±1 Hz
    for (final h in hums) {
      final int i = (h / binHz).round() - minIdx;
      if (i >= 0 && i < band.length) {
        final int lo = (i - halfWidthBins).clamp(0, band.length - 1);
        final int hi = (i + halfWidthBins).clamp(0, band.length - 1);
        for (int k = lo; k <= hi; k++) {
          band[k] = 0.0;
        }
      }
    }
  }

  static List<double> _rfftfreq(int n, double d) {
    final nOut = n ~/ 2 + 1;
    return List<double>.generate(nOut, (k) => k / (n * d));
  }

  static int _searchSorted(List<double> a, double x) {
    int lo = 0, hi = a.length;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (a[mid] < x) { lo = mid + 1; } else { hi = mid; }
    }
    return lo;
  }

  static int _argMax(List<double> a) {
    int idx = 0; double best = a[0];
    for (int i = 1; i < a.length; i++) {
      final v = a[i];
      if (v > best) { best = v; idx = i; }
    }
    return idx;
  }

  static List<double> _downsample(List<double> a, int step) {
    if (step <= 1) return List<double>.from(a);
    final L = (a.length / step).floor();
    final out = List<double>.filled(L, 0.0);
    int j = 0;
    for (int i = 0; i < L; i++) { out[i] = a[j]; j += step; }
    return out;
  }

  int _maxUsableHpsOrder(int bandLen) {
    int p = 2;
    while (p < hpsOrder && (bandLen / (p + 1)).floor() >= 16) p++;
    return p;
  }

  void _tiltCompensate(List<double> band, double alpha) {
    for (int k = 0; k < band.length; k++) {
      band[k] *= math.pow(k + 1.0, alpha);
    }
  }

  int _maybeOctaveFoldDown(List<double> hpsBand, int minIdx, int peakGlobal) {
    int curr = peakGlobal;
    for (;;) {
      final topInBand = curr - minIdx;
      if (topInBand < 0 || topInBand >= hpsBand.length) break;

      final halfGb = (curr / 2).floor();
      final thirdGb = (curr / 3).floor();

      bool folded = false;
      if (halfGb - minIdx >= 0 && halfGb - minIdx < hpsBand.length) {
        final aTop = hpsBand[topInBand];
        final aHalf = hpsBand[halfGb - minIdx];
        if (aHalf / (aTop + 1e-12) > 0.70) { curr = halfGb; folded = true; }
      }
      if (!folded && thirdGb - minIdx >= 0 && thirdGb - minIdx < hpsBand.length) {
        final aTop = hpsBand[topInBand];
        final aThird = hpsBand[thirdGb - minIdx];
        if (aThird / (aTop + 1e-12) > 0.65) { curr = thirdGb; folded = true; }
      }
      if (!folded) break;
    }
    return curr;
  }

  double _binToFreq(double bin) {
    final i0 = bin.floor();
    final frac = bin - i0;
    if (i0 <= 0) return _freqs.first;
    if (i0 >= _freqs.length - 1) return _freqs.last;
    return _freqs[i0] * (1.0 - frac) + _freqs[i0 + 1] * frac;
  }

  static double _qintDeltaFromLogs(double lm1, double l0, double lp1) {
    // Quadratic interpolation on log-magnitude spectrum (QIFFT).
    // Returns fractional offset in [-1, +1] bins.
    final denom = (lm1 - 2.0 * l0 + lp1);
    if (denom.abs() < 1e-12) return 0.0;
    final d = 0.5 * (lm1 - lp1) / denom;
    // Clamp to be safe if the neighborhood is weird
    return d.clamp(-1.0, 1.0);
  }

  // ----- FFT -----

  static List<_Cx> _rfftLen(List<double> x, int fftLen) {
    final c = List<_Cx>.generate(fftLen, (i) => _Cx(i < x.length ? x[i] : 0.0, 0.0));
    _fftInPlace(c, inverse: false);
    final nOut = fftLen ~/ 2 + 1;
    return c.sublist(0, nOut);
  }

  static void _fftInPlace(List<_Cx> a, {required bool inverse}) {
    final n = a.length;
    if (!_isPowerOfTwo(n)) { throw ArgumentError('FFT size must be a power of two'); }

    int j = 0;
    for (int i = 1; i < n; i++) {
      int bit = n >> 1;
      while ((j & bit) != 0) { j ^= bit; bit >>= 1; }
      j ^= bit;
      if (i < j) { final t = a[i]; a[i] = a[j]; a[j] = t; }
    }

    for (int len = 2; len <= n; len <<= 1) {
      final ang = 2.0 * math.pi / len * (inverse ? 1.0 : -1.0);
      final wlen = _Cx(math.cos(ang), math.sin(ang));
      for (int i = 0; i < n; i += len) {
        var w = const _Cx(1.0, 0.0);
        for (int k = 0; k < (len >> 1); k++) {
          final u = a[i + k];
          final v = a[i + k + (len >> 1)] * w;
          a[i + k] = u + v;
          a[i + k + (len >> 1)] = u - v;
          w = w * wlen;
        }
      }
    }

    if (inverse) {
      for (int i = 0; i < n; i++) { a[i] = a[i] / n.toDouble(); }
    }
  }

  // ----- Note mapping -----

  static const List<String> _noteNames = ['C','C#','D','D#','E','F','F#','G','G#','A','A#','B'];

  static _NoteInfo _freqToNote(double f) {
    if (!(f.isFinite) || f <= 0) return const _NoteInfo(name: '-', octave: 0, cents: 0);
    final n = 69.0 + 12.0 * (math.log(f / 440.0) / math.ln2);
    final nRound = n.round();
    final cents = 100.0 * (n - nRound);
    final noteIndex = (nRound % 12 + 12) % 12;
    final octave = (nRound ~/ 12) - 1;
    return _NoteInfo(name: _noteNames[noteIndex], octave: octave, cents: cents);
  }

  static double _median(List<double> xs) {
    if (xs.isEmpty) return 0.0;
    final a = List<double>.from(xs)..sort();
    final m = a.length >> 1;
    if (a.length.isOdd) return a[m];
    return 0.5 * (a[m - 1] + a[m]);
  }
}

class _NoteInfo {
  final String name;
  final int octave;
  final double cents;
  const _NoteInfo({required this.name, required this.octave, required this.cents});
}

class _Cx {
  final double re;
  final double im;
  const _Cx(this.re, this.im);
  double abs() => math.sqrt(re * re + im * im);
  _Cx operator +(_Cx o) => _Cx(re + o.re, im + o.im);
  _Cx operator -(_Cx o) => _Cx(re - o.re, im - o.im);
  _Cx operator *(_Cx o) => _Cx(re * o.re - im * o.im, re * o.im + im * o.re);
  _Cx operator /(double d) => _Cx(re / d, im / d);
}
