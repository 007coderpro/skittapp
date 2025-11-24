import 'dart:math' as math;
import 'dart:typed_data';

import 'package:fftea/fftea.dart';
import 'package:scidart/scidart.dart' as scidart;


/*

incoming audio frame
      ↓
_padOrTruncate → multiply Hann window → real FFT magnitudes
      ↓
Harmonic Product Spectrum (multiply partial copies)
      ↓
Search 70–1200 Hz → pick strongest bin → optional octave correction
      ↓
smooth with running median (history=20)
      ↓
PitchResult(f0Raw, f0Smoothed, level, voiced)

*/

// ---------- Apufunktiot ----------

// Hann window scidartilla
Float64List _hannWindow(int length) {
  final arr = scidart.hann(length); // Array
  return Float64List.fromList(arr.toList());
}

// Median (pidetään oma, yksinkertainen ja oikea)
double _median(List<double> values) {
  if (values.isEmpty) return double.nan;
  final sorted = List<double>.from(values)..sort();
  final n = sorted.length;
  if (n.isOdd) {
    return sorted[n ~/ 2];
  } else {
    final mid1 = sorted[n ~/ 2 - 1];
    final mid2 = sorted[n ~/ 2];
    return (mid1 + mid2) / 2.0;
  }
}

// Pad / truncate frame window-pituuteen
Float64List _padOrTruncate(Float64List frame, int windowLength) {
  final out = Float64List(windowLength);
  final copyLen = math.min(frame.length, windowLength);
  out.setRange(0, copyLen, frame);
  return out;
}

// RMS + dB
double _rms(Float64List x) {
  if (x.isEmpty) return 0.0;
  double sumSq = 0.0;
  for (final v in x) {
    sumSq += v * v;
  }
  return math.sqrt(sumSq / x.length);
}

double _dbFromRms(double rms) {
  if (rms == 0.0) return double.negativeInfinity;
  return 20.0 * math.log(rms) / math.ln10; // 20*log10
}

// Real FFT magnitudi fftea:lla (rfft + discardConjugates + magnitudes)
List<double> _realFftMagnitude(Float64List frame, FFT fft) {
  // returns Float64x2List (complex array)
  final freq = fft.realFft(frame);
  // jättää Nyquistin ja poistaa konjugaatit, tämä vastaa rfft:n "puolta"
  final mags = freq.discardConjugates().magnitudes(); // Float64List
  return mags;
}

// ---------- PitchResult ----------

class PitchResult {
  final double? f0Raw;
  final double? f0Smoothed;
  final double dbLevel;
  final bool voiced;

  PitchResult({
    required this.f0Raw,
    required this.f0Smoothed,
    required this.dbLevel,
    required this.voiced,
  });
}

// ---------- HPSPitchDetector ----------

class HPSPitchDetector {
  static const int sampleRate = 48000;
  static const int windowLength = 4096 * 16;
  static const int partials = 5;
  static const double dbThreshold = -30.0;
  static const int historySize = 20;

  // kitara-alue
  static const double minFreq = 70.0;
  static const double maxFreq = 1200.0;

  final Float64List _window;
  final List<double> _f0Values = [];
  final FFT _fft; // fftea:n FFT-objekti (cache)

  HPSPitchDetector()
      : _window = _hannWindow(windowLength),
        _fft = FFT(windowLength);

  /// Equivalent to Python HPS_f0_frame with guitar-band constraints.
  double hpsF0Frame(
    Float64List frame, {
    int sampleRate = HPSPitchDetector.sampleRate,
    int windowLength = HPSPitchDetector.windowLength,
    int partials = HPSPitchDetector.partials,
  }) {
    // pad / truncate
    final data = _padOrTruncate(frame, windowLength);

    // Hann-ikkuna
    for (int i = 0; i < windowLength; i++) {
      data[i] *= _window[i];
    }

    // FFT magnitudi fftea:lla
    final magSpec = _realFftMagnitude(data, _fft);
    final nFreqs = magSpec.length;

    // taajuusvektori (k * fs / N)
    final freqs = List<double>.generate(
      nFreqs,
      (k) => k * sampleRate / windowLength,
    );

    // HPS
    final hpsSpec = List<double>.from(magSpec);
    for (int p = 2; p <= partials; p++) {
      // kerrotaan aina olemassa olevia binnejä niiden p-kertoimilla
      final limit = nFreqs ~/ p;
      for (int i = 0; i < limit; i++) {
        hpsSpec[i] *= magSpec[i * p];
      }
    }

    // rajataan kitara-alueelle
    int startIdx = 0;
    while (startIdx < nFreqs && freqs[startIdx] < minFreq) {
      startIdx++;
    }
    int endIdx = nFreqs - 1;
    while (endIdx > startIdx && freqs[endIdx] > maxFreq) {
      endIdx--;
    }
    if (startIdx >= endIdx) {
      return 0.0;
    }

    // haetaan maksimi HPS-spektristä tällä alueella
    int peakIdx = startIdx;
    double peakVal = hpsSpec[peakIdx];
    for (int i = startIdx + 1; i <= endIdx; i++) {
      if (hpsSpec[i] > peakVal) {
        peakVal = hpsSpec[i];
        peakIdx = i;
      }
    }

    double f0 = freqs[peakIdx];

    // Python-tyylinen oktavikorjaus (f0/2 ja vertaillaan amplitudia)
    if (f0 > 130.0) {
      final target = f0 / 2.0;
      int lowerIdx = 0;
      double bestDiff = (freqs[0] - target).abs();
      for (int i = 1; i < freqs.length; i++) {
        final diff = (freqs[i] - target).abs();
        if (diff < bestDiff) {
          bestDiff = diff;
          lowerIdx = i;
        }
      }

      final ampMain = magSpec[peakIdx];
      final ampLower = magSpec[lowerIdx];

      if (ampLower > 0.2 * ampMain) {
        f0 = freqs[lowerIdx];
      }
    }

    // jos ollaan alle kitara-alueen, nostetaan oktaaveja ylös
    while (f0 > 0 && f0 < minFreq) {
      f0 *= 2.0;
    }
    if (f0 > maxFreq) {
      f0 = maxFreq;
    }

    return f0;
  }

  /// Equivalent to smooth_f0(f0) with deque(maxlen=20).
  double smoothF0(double f0) {
    _f0Values.add(f0);
    if (_f0Values.length > historySize) {
      _f0Values.removeAt(0);
    }

    if (_f0Values.length < 3) {
      return f0;
    }

    return _median(_f0Values);
  }

  void clearHistory() {
    _f0Values.clear();
  }

  /// Equivalent to audio_callback in Python, but as a pure function.
  PitchResult processFrame(
    Float64List audioData, {
    int numChannels = 1,
    int sampleRate = HPSPitchDetector.sampleRate,
  }) {
    // mono-kanava (ensimmäinen kanava, kuten Pythonissa indata[:, 0])
    Float64List mono;
    if (numChannels <= 1) {
      mono = audioData;
    } else {
      final frames = audioData.length ~/ numChannels;
      mono = Float64List(frames);
      for (int i = 0; i < frames; i++) {
        mono[i] = audioData[i * numChannels];
      }
    }

    final rms = _rms(mono);
    final dbLevel = _dbFromRms(rms);

    if (dbLevel > dbThreshold) {
      final f0Raw = hpsF0Frame(
        mono,
        sampleRate: sampleRate,
        windowLength: windowLength,
        partials: partials,
      );
      final f0Smoothed = smoothF0(f0Raw);

      return PitchResult(
        f0Raw: f0Raw,
        f0Smoothed: f0Smoothed,
        dbLevel: dbLevel,
        voiced: true,
      );
    } else {
      clearHistory();
      return PitchResult(
        f0Raw: null,
        f0Smoothed: null,
        dbLevel: dbLevel,
        voiced: false,
      );
    }
  }
}
