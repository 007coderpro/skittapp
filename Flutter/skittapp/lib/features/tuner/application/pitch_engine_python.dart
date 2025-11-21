import 'dart:math' as math;
import 'dart:typed_data';

class Complex {
  double re;
  double im;

  Complex(this.re, this.im);

  Complex operator +(Complex other) => Complex(re + other.re, im + other.im);
  Complex operator -(Complex other) => Complex(re - other.re, im - other.im);
  Complex operator *(Complex other) =>
      Complex(re * other.re - im * other.im, re * other.im + im * other.re);

  double get abs => math.sqrt(re * re + im * im);
}

/// Simple in-place radix-2 FFT (Cooley–Tukey).
/// Assumes `input.length` is a power of two.
List<Complex> _fft(List<Complex> input) {
  final n = input.length;
  final output = List<Complex>.generate(
    n,
    (i) => Complex(input[i].re, input[i].im),
  );

  // Bit-reversal permutation
  int j = 0;
  for (int i = 1; i < n; i++) {
    int bit = n >> 1;
    while ((j & bit) != 0) {
      j &= ~bit;
      bit >>= 1;
    }
    j |= bit;
    if (i < j) {
      final temp = output[i];
      output[i] = output[j];
      output[j] = temp;
    }
  }

  // Danielson–Lanczos section
  for (int len = 2; len <= n; len <<= 1) {
    final angle = -2 * math.pi / len;
    final wLen = Complex(math.cos(angle), math.sin(angle));

    for (int i = 0; i < n; i += len) {
      var w = Complex(1.0, 0.0);
      final halfLen = len >> 1;
      for (int k = 0; k < halfLen; k++) {
        final u = output[i + k];
        final v = output[i + k + halfLen] * w;

        output[i + k] = u + v;
        output[i + k + halfLen] = u - v;

        w = w * wLen;
      }
    }
  }

  return output;
}

/// Real FFT magnitude, equivalent to numpy.rfft followed by np.abs().
List<double> _realFftMagnitude(Float64List frame) {
  final n = frame.length;
  final complexInput = List<Complex>.generate(
    n,
    (i) => Complex(frame[i], 0.0),
  );
  final spectrum = _fft(complexInput);

  final half = n ~/ 2;
  final mag = List<double>.filled(half + 1, 0.0);
  for (int k = 0; k <= half; k++) {
    mag[k] = spectrum[k].abs;
  }
  return mag;
}

/// Hann window, equivalent to np.hanning(N).
Float64List _hannWindow(int length) {
  final win = Float64List(length);
  if (length == 1) {
    win[0] = 1.0;
    return win;
  }
  for (int n = 0; n < length; n++) {
    win[n] = 0.5 - 0.5 * math.cos(2 * math.pi * n / (length - 1));
  }
  return win;
}

/// Median, equivalent to np.median (for 1D, numeric).
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

/// This class mirrors HPS_real.py logic as closely as possible.
class HPSPitchDetector {
  static const int sampleRate = 48000;
  static const int windowLength = 4096 * 16;
  static const int partials = 5;
  static const double dbThreshold = -30.0;
  static const int historySize = 20;

  final Float64List _window;
  final List<double> _f0Values = [];

  HPSPitchDetector() : _window = _hannWindow(windowLength);

  /// Equivalent to Python HPS_f0_frame.
  double hpsF0Frame(
    Float64List frame, {
    int sampleRate = HPSPitchDetector.sampleRate,
    int windowLength = HPSPitchDetector.windowLength,
    int partials = HPSPitchDetector.partials,
  }) {
    // Make a copy so we can pad/truncate without touching caller’s buffer
    final data = Float64List(windowLength);

    if (frame.length < windowLength) {
      // pad with zeros at the end
      for (int i = 0; i < frame.length; i++) {
        data[i] = frame[i];
      }
      for (int i = frame.length; i < windowLength; i++) {
        data[i] = 0.0;
      }
    } else {
      // truncate
      for (int i = 0; i < windowLength; i++) {
        data[i] = frame[i];
      }
    }

    // Apply Hann window (np.hanning)
    for (int i = 0; i < windowLength; i++) {
      data[i] *= _window[i];
    }

    // Magnitude spectrum (real FFT)
    final magSpec = _realFftMagnitude(data);

    // Frequencies, equivalent to np.fft.rfftfreq
    final nFreqs = magSpec.length;
    final freqs = List<double>.generate(
      nFreqs,
      (k) => k * sampleRate / windowLength,
    );

    // Copy for HPS
    final hpsSpec = List<double>.from(magSpec);

    // HPS algorithm, like:
    // for p in range(2, partials+1):
    //   downsampled = mag_spec[::p]
    //   hps_spec = hps_spec[:len(downsampled)] * downsampled
    for (int p = 2; p <= partials; p++) {
      final downsampled = <double>[];
      for (int i = 0; i < magSpec.length; i += p) {
        downsampled.add(magSpec[i]);
      }

      final len = downsampled.length;
      for (int i = 0; i < len; i++) {
        hpsSpec[i] *= downsampled[i];
      }
      // Remaining bins are implicitly ignored (like Python’s [:len])
    }

    // Find peak → f0 estimate
    int peakIdx = 0;
    double peakVal = hpsSpec[0];
    for (int i = 1; i < hpsSpec.length; i++) {
      if (hpsSpec[i] > peakVal) {
        peakVal = hpsSpec[i];
        peakIdx = i;
      }
    }

    double f0 = freqs[peakIdx];

    // Octave correction: if f0 > 130 Hz, check f0/2
    if (f0 > 130.0) {
      final target = f0 / 2.0;

      // Find nearest bin to target (argmin |freqs - target|)
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

    return f0;
  }

  /// Equivalent to smooth_f0(f0) with global deque(maxlen=20).
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

  /// Clear history (called when signal is "too quiet" in Python).
  void clearHistory() {
    _f0Values.clear();
  }

  /// Equivalent to audio_callback in Python, but as a pure function.
  ///
  /// - `audioData` can be mono (numChannels = 1) or interleaved multi-channel.
  /// - To match Python, we use **only the first channel**.
  PitchResult processFrame(
    Float64List audioData, {
    int numChannels = 1,
    int sampleRate = HPSPitchDetector.sampleRate,
  }) {
    // Extract first channel, like indata[:, 0]
    Float64List mono;
    if (numChannels <= 1) {
      mono = audioData;
    } else {
      final frames = audioData.length ~/ numChannels;
      mono = Float64List(frames);
      for (int i = 0; i < frames; i++) {
        mono[i] = audioData[i * numChannels]; // first channel only
      }
    }

    // dB level: 20 * log10(sqrt(mean(x^2))) = 20 * log10(rms)
    double sumSq = 0.0;
    for (int i = 0; i < mono.length; i++) {
      final v = mono[i];
      sumSq += v * v;
    }
    final rms = mono.isEmpty ? 0.0 : math.sqrt(sumSq / mono.length);

    double dbLevel;
    if (rms == 0.0) {
      dbLevel = double.negativeInfinity;
    } else {
      dbLevel = 20.0 * math.log(rms) / math.ln10; // same as 20*log10
    }

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
