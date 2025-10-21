import 'package:flutter/material.dart';
import '../../../core/audio/audio_recorder.dart';
import '../../../core/ipc/python_bridge_http.dart';
import '../application/tuner_controller.dart';
import 'widgets/needle_gauge.dart';
import 'widgets/level_meter.dart';

/// Tuner-näkymä: mittari + nuotti
class TunerPage extends StatefulWidget {
  const TunerPage({super.key});

  @override
  State<TunerPage> createState() => _TunerPageState();
}

class _TunerPageState extends State<TunerPage> {
  late TunerController _controller;
  bool _isRecording = false;

  @override
  void initState() {
    super.initState();
    
    // Luo controller HTTP-sillalla (voit vaihtaa stdio-versioon)
    final recorder = AudioRecorderService(
      sampleRate: 48000,
      channels: 1,
      samplesPerFrame: 4096,
    );
    final bridge = PythonBridgeHttp('http://127.0.0.1:8000');
    
    _controller = TunerController(recorder: recorder, bridge: bridge);
    _controller.addListener(() {
      setState(() {}); // Päivitä UI kun data muuttuu
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _toggleRecording() async {
    if (_isRecording) {
      await _controller.stop();
      setState(() => _isRecording = false);
    } else {
      try {
        await _controller.start();
        setState(() => _isRecording = true);
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Virhe: $e')),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Kitaraviritys'),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Nuotti ja taajuus
              if (_controller.lastNote != null) ...[
                Text(
                  _controller.lastNote!,
                  style: Theme.of(context).textTheme.displayLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                const SizedBox(height: 8),
                Text(
                  '${_controller.lastF0?.toStringAsFixed(2) ?? '--'} Hz',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 24),
              ] else ...[
                Text(
                  '--',
                  style: Theme.of(context).textTheme.displayLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: Colors.grey,
                      ),
                ),
                const SizedBox(height: 8),
                Text(
                  _isRecording ? 'Kuunnellaan...' : 'Soita nuotti',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        color: Colors.grey,
                      ),
                ),
                const SizedBox(height: 24),
              ],

              // RMS-taso (placeholder-metriikka)
              if (_isRecording) ...[
                Text(
                  'RMS: ${(_controller.lastRms * 100).toStringAsFixed(1)}%',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 16),
              ],

              // Neulakello
              Expanded(
                child: Center(
                  child: NeedleGauge(
                    cents: _controller.lastCents ?? 0.0,
                    confidence: _controller.lastConfidence,
                  ),
                ),
              ),

              const SizedBox(height: 24),

              // Äänenvoimakkuusmittari
              LevelMeter(level: _controller.lastRms),

              const SizedBox(height: 32),

              // Aloita/Lopeta -painike
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _toggleRecording,
                  icon: Icon(
                    _isRecording ? Icons.stop : Icons.mic,
                  ),
                  label: Text(
                    _isRecording ? 'Lopeta' : 'Aloita viritys',
                    style: const TextStyle(fontSize: 18),
                  ),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

