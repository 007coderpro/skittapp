import 'dart:async';
import 'dart:typed_data';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';

/// Tuottaa tasapituisia PCM16-kehyksiä (Uint8List) esim. 4096 näytettä @48 kHz.
/// Yksi näyte = 2 tavua (int16).
class AudioRecorderService {
  final _recorder = AudioRecorder();
  StreamController<Uint8List>? _framesCtrl;

  // Asetukset
  final int sampleRate;
  final int channels;
  final int samplesPerFrame; // esim. 4096 → ~85 ms @ 48 kHz

  AudioRecorderService({
    this.sampleRate = 44100,
    this.channels = 1,
    this.samplesPerFrame = 16384,
  });

  Stream<Uint8List> get frames => _framesCtrl!.stream;

  Future<void> start() async {
    // Luvat
    final status = await Permission.microphone.request();
    if (!status.isGranted) {
      throw Exception('Mikrofonilupa evätty');
    }

    _framesCtrl?.close();
    _framesCtrl = StreamController<Uint8List>.broadcast();

    // record: PCM16 streami
    final stream = await _recorder.startStream(RecordConfig(
      encoder: AudioEncoder.pcm16bits,
      sampleRate: sampleRate,
      numChannels: channels,
      bitRate: 256000, // ei merkitystä PCM:lle, mutta pidetään mukana
    ));

    // Puskuroi tasapituisiksi kehyksiksi
    final frameBytes = samplesPerFrame * channels * 2; // int16
    final buffer = BytesBuilder(copy: false);
    stream.listen((chunk) {
      buffer.add(chunk);
      // Ylitäyttö: paloittele tasapituisiksi kehyksiksi
      var data = buffer.toBytes();
      var offset = 0;
      while (data.length - offset >= frameBytes) {
        _framesCtrl?.add(Uint8List.sublistView(data, offset, offset + frameBytes));
        offset += frameBytes;
      }
      // Jätä ylijäämä bufferiin
      final leftover = Uint8List.sublistView(data, offset);
      buffer.clear();
      buffer.add(leftover);
    }, onDone: () {
      _framesCtrl?.close();
    });
  }

  Future<void> stop() async {
    await _recorder.stop();
    await _framesCtrl?.close();
  }

  Future<void> dispose() async {
    await stop();
    _recorder.dispose();
  }

  bool get isRecording => _framesCtrl != null && !_framesCtrl!.isClosed;
}
