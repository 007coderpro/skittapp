import 'dart:collection';
import 'dart:math';
import 'dart:typed_data';
import 'package:fftea/fftea.dart';

const int samp = 48000; // Näytteenottotaajuus
const int windowlen = 4096 * 16; // Ikkunan pituus (näytteitä)
const double threshold = -30; // dB-raja äänitason tunnistukseen
const double octaveThreshold = 130; // Korkeuden kynnys oktaavikorjaukselle
const int queueLength = 20; // F0-smootherin pituus

List<double> hanning(int length) {
  // Generate Hann window
  return List<double>.generate(
    length,
    (i) => 0.5 * (1 - cos(2 * pi * i / (length - 1))),
  );
}

List<double> rfftfreq(int n, double d) {
  // Generate frequencies for rfft
  final int halfN = (n ~/ 2) + 1;
  return List<double>.generate(halfN, (i) => i / (n * d));
}

double median(List<double> values) {
  if (values.isEmpty) return 0.0;
  final sorted = List<double>.from(values)..sort();
  final mid = sorted.length ~/ 2;
  if (sorted.length % 2 == 1) {
    return sorted[mid];
  } else {
    return (sorted[mid - 1] + sorted[mid]) / 2;
  }
}

double hpsF0Frame(
  List<double> frame, {
  int sampleRate = samp,
  int windowLength = windowlen,
  int partials = 5,
}) {
  final freqs = rfftfreq(windowLength, 1 / sampleRate);

  // Pad frame if needed
  List<double> processedFrame;
  if (frame.length < windowLength) {
    processedFrame = List<double>.from(frame)
      ..addAll(List<double>.filled(windowLength - frame.length, 0.0));
  } else if (frame.length > windowLength) {
    processedFrame = frame.sublist(0, windowLength);
  } else {
    processedFrame = frame;
  }

  // Windowing
  final window = hanning(windowLength);
  final windowedFrame = List<double>.generate(
    windowLength,
    (i) => processedFrame[i] * window[i],
  );

  // FFT using fftea
  final fft = FFT(windowLength);
  final complexArray = fft.realFft(Float64List.fromList(windowedFrame));

  // Calculate magnitude spectrum
  final magSpec = List<double>.generate(
    complexArray.length,
    (i) {
      // Float64x2 uses .x and .y for components (real, imag)
      final real = complexArray[i].x;
      final imag = complexArray[i].y;
      return sqrt(real * real + imag * imag);
    },
  );

  // Copy original spectrum for HPS
  List<double> hpsSpec = List<double>.from(magSpec);

  // HPS algorithm
  for (int p = 2; p <= partials; p++) {
    final downsampled = <double>[];
    for (int i = 0; i < magSpec.length; i += p) {
      downsampled.add(magSpec[i]);
    }
    final len = min(hpsSpec.length, downsampled.length);
    for (int i = 0; i < len; i++) {
      hpsSpec[i] = hpsSpec[i] * downsampled[i];
    }
    hpsSpec = hpsSpec.sublist(0, len);
  }

  // Find peak index
  int peakIdx = 0;
  double peakVal = hpsSpec[0];
  for (int i = 1; i < hpsSpec.length; i++) {
    if (hpsSpec[i] > peakVal) {
      peakVal = hpsSpec[i];
      peakIdx = i;
    }
  }

  double f0 = freqs[peakIdx];

  // Octave correction
  if (f0 > octaveThreshold) {
    final lowerOctaveFreq = f0 / 2;

    // Find index closest to lower octave frequency
    int lowerIdx = 0;
    double minDiff = (freqs[0] - lowerOctaveFreq).abs();
    for (int i = 1; i < freqs.length; i++) {
      final diff = (freqs[i] - lowerOctaveFreq).abs();
      if (diff < minDiff) {
        minDiff = diff;
        lowerIdx = i;
      }
    }

    final ampMain = magSpec[peakIdx];
    final ampLower = magSpec[lowerIdx];

    // If lower octave amplitude is > 20% of detected peak, use lower octave
    if (ampMain > 0 && ampLower / ampMain > 0.2) {
      f0 = lowerOctaveFreq;
    }
  }

  return f0;
}

class F0Smoother {
  final int maxLen;
  final Queue<double> _values = Queue<double>();

  F0Smoother({this.maxLen = queueLength});

  double smooth(double f0) {
    _values.addLast(f0);

    if (_values.length > maxLen) {
      _values.removeFirst();
    }

    if (_values.length < 3) {
      return f0;
    }

    return median(_values.toList());
  }

  void clear() {
    _values.clear();
  }
}

// Global smoother instance
final f0Smoother = F0Smoother();

/// Convert stereo/multi-channel audio to mono by averaging channels
Float64List convertToMono(Float64List audioData, int numChannels) {
  if (numChannels == 1) {
    // Already mono
    return audioData;
  }

  final numFrames = audioData.length ~/ numChannels;
  final monoData = Float64List(numFrames);

  for (int i = 0; i < numFrames; i++) {
    double sum = 0.0;
    for (int ch = 0; ch < numChannels; ch++) {
      sum += audioData[i * numChannels + ch];
    }
    monoData[i] = sum / numChannels;
  }

  return monoData;
}

void audioCallback(Float64List audioData, {int numChannels = 1}) {
  // Convert to mono if needed
  final monoData = convertToMono(audioData, numChannels);

  // Calculate dB level
  double sumSquares = 0.0;
  for (final sample in monoData) {
    sumSquares += sample * sample;
  }
  final rms = sqrt(sumSquares / monoData.length);

  double dbLevel;
  if (rms > 1e-10) {
    dbLevel = 20 * log(rms) / ln10;
  } else {
    dbLevel = -100;
  }

  if (dbLevel > threshold) {
    final f0Raw = hpsF0Frame(monoData.toList(), sampleRate: samp);
    final f0Smoothed = f0Smoother.smooth(f0Raw);

    print(
      'F0: ${f0Smoothed.toStringAsFixed(2)} Hz | '
      'Raw: ${f0Raw.toStringAsFixed(2)} Hz | '
      'dB: ${dbLevel.toStringAsFixed(1)}',
    );
  } else {
    f0Smoother.clear();
    print('dB: ${dbLevel.toStringAsFixed(1)} (too quiet)');
  }
}