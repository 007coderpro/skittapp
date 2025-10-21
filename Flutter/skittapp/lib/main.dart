import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'app/app.dart';

// Dev-versio: yksinkertainen RMS-näyttö
// Tuotantoversio: käytä app/app.dart

void main() {
  runApp(
    const ProviderScope(
      child: App(),
    ),
  );
}

/* 
// Dev-käynnistys (yksinkertainen):
import 'core/audio/audio_recorder.dart';
import 'core/ipc/python_bridge_http.dart';
import 'features/tuner/application/tuner_controller.dart';

void main() {
  final recorder = AudioRecorderService(sampleRate: 48000, samplesPerFrame: 4096);
  final bridge = PythonBridgeHttp('http://127.0.0.1:8000');
  final controller = TunerController(recorder: recorder, bridge: bridge);
  runApp(MyDevApp(controller));
}

class MyDevApp extends StatefulWidget {
  final TunerController controller;
  const MyDevApp(this.controller, {super.key});
  @override
  State<MyDevApp> createState() => _MyDevAppState();
}

class _MyDevAppState extends State<MyDevApp> {
  @override
  void initState() {
    super.initState();
    widget.controller.start();
  }

  @override
  void dispose() {
    widget.controller.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: const Text('Tuner Dev Pipe')),
        body: AnimatedBuilder(
          animation: widget.controller,
          builder: (_, __) => Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              'RMS: ${widget.controller.lastRms.toStringAsFixed(4)}\n'
              'f0: ${widget.controller.lastF0?.toStringAsFixed(2) ?? "-"}\n'
              'conf: ${widget.controller.lastConfidence.toStringAsFixed(2)}',
            ),
          ),
        ),
      ),
    );
  }
}
*/
