import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'python_bridge.dart';

/// Käynnistää paikallisen prosessin (esim. PyInstaller-bundle "pitch_service_stdio").
/// Kommunikoi JSON-riveillä: request \n, response \n.
class PythonBridgeStdio implements PythonBridge {
  final String executablePath; // esim. assets/bin/macos/pitch_service_stdio
  Process? _proc;
  StreamSubscription<String>? _stdoutSub;

  // Vastauksia odottavat completerit jonossa
  final _pending = <Completer<PitchResult?>>[];

  PythonBridgeStdio(this.executablePath);

  @override
  Future<void> start() async {
    _proc = await Process.start(executablePath, [], runInShell: false);
    _stdoutSub = _proc!.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) {
      if (_pending.isNotEmpty) {
        final comp = _pending.removeAt(0);
        try {
          final j = jsonDecode(line) as Map<String, dynamic>;
          comp.complete(PitchResult.fromJson(j));
        } catch (e) {
          comp.complete(null);
        }
      }
    });

    _proc!.stderr.transform(utf8.decoder).listen((e) {
      // log e if you want
    });
  }

  @override
  Future<PitchResult?> processFrame(Uint8List pcmInt16, {required int sampleRate}) async {
    final req = jsonEncode({
      'sr': sampleRate,
      'data_b64': base64Encode(pcmInt16),
    });
    final comp = Completer<PitchResult?>();
    _pending.add(comp);
    _proc?.stdin.writeln(req);
    return comp.future.timeout(const Duration(seconds: 2), onTimeout: () => null);
  }

  @override
  Future<void> stop() async {
    await _stdoutSub?.cancel();
    _proc?.stdin.writeln(jsonEncode({'cmd': 'quit'}));
    await _proc?.kill();
  }
}

