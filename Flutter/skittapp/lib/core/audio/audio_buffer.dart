import 'dart:async';
import 'dart:typed_data';

/// Kehys- ja puskurilogikka äänidatalle
class AudioBuffer {
  final int frameSize; // näytteitä per kehys
  final int sampleRate;
  final StreamController<Float32List> _frameController;

  List<int> _buffer = [];

  AudioBuffer({
    required this.frameSize,
    this.sampleRate = 44100,
  }) : _frameController = StreamController<Float32List>.broadcast();

  /// Lisää PCM16-dataa puskuriin
  /// Kun tarpeeksi dataa, lähetä kehys streamiin
  void addSamples(List<int> pcm16Data) {
    _buffer.addAll(pcm16Data);

    // Tarkista onko tarpeeksi dataa kehykselle (PCM16 = 2 tavua per näyte)
    final bytesNeeded = frameSize * 2;

    while (_buffer.length >= bytesNeeded) {
      // Ota kehyksen verran dataa
      final frameBytes = _buffer.sublist(0, bytesNeeded);
      _buffer = _buffer.sublist(bytesNeeded);

      // Konvertoi PCM16 -> Float32 [-1.0, 1.0]
      final frame = _pcm16ToFloat32(frameBytes);
      
      if (!_frameController.isClosed) {
        _frameController.add(frame);
      }
    }
  }

  /// Streami joka tuottaa float32-kehyksiä
  Stream<Float32List> get frameStream => _frameController.stream;

  /// Konvertoi PCM16 (little-endian) -> Float32
  Float32List _pcm16ToFloat32(List<int> pcm16Bytes) {
    final numSamples = pcm16Bytes.length ~/ 2;
    final result = Float32List(numSamples);

    for (int i = 0; i < numSamples; i++) {
      final low = pcm16Bytes[i * 2];
      final high = pcm16Bytes[i * 2 + 1];
      
      // Little-endian 16-bit signed integer
      int sample = low | (high << 8);
      
      // Käsittele signed int
      if (sample > 32767) {
        sample -= 65536;
      }

      // Normalisoi [-1.0, 1.0]
      result[i] = sample / 32768.0;
    }

    return result;
  }

  /// Tyhjennä puskuri
  void clear() {
    _buffer.clear();
  }

  /// Vapauta resurssit
  void dispose() {
    clear();
    _frameController.close();
  }
}
