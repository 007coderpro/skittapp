import 'dart:async';
import 'dart:typed_data';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:skittapp/core/audio/audio_recorder.dart';
import 'package:skittapp/features/tuner/application/pitch_engine.dart' as adv;
import 'package:skittapp/features/tuner/application/pitch_engine_python.dart'
  as simple;
import 'package:skittapp/features/tuner/application/debug.dart';

import 'widgets/needle_gauge.dart';

/// Tuner-näkymä: mittari + nuotti
class TunerPage extends StatefulWidget {
  const TunerPage({Key? key}) : super(key: key);

  @override
  State<TunerPage> createState() => _TunerPageState();
}

class _NoteAndCents {
  final String name;
  final double cents;
  const _NoteAndCents(this.name, this.cents);
}

_NoteAndCents _freqToNote(double f) {
  if (f <= 0 || !f.isFinite) {
    return const _NoteAndCents('', 0);
  }

  const double a4 = 440.0;
  final double midi = 69 + 12 * (math.log(f / a4) / math.ln2);
  final int midiRounded = midi.round();
  final double cents = (midi - midiRounded) * 100.0;

  const List<String> noteNames = <String>[
    'C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B',
  ];

  final int noteIndex = ((midiRounded % 12) + 12) % 12;
  final int octave = (midiRounded ~/ 12) - 1;
  final String name = '${noteNames[noteIndex]}$octave';

  return _NoteAndCents(name, cents);
}

enum PitchAlgo { simple, advanced }

class _TunerPageState extends State<TunerPage> {
  // UI state
  double _hzDelta = 0.0;      // tuning offset in Hz (UI may lock to selected string)
  double _confidence = 0.0;  // 0.0 - 1.0
  String? _selectedId;       // currently selected/toggled string
  String? _lastSelectedId;   // to detect key change → reset smoother
  double _rms = 0.0;         // audio level
  double _frequency = 0.0;   // detected pitch in Hz (smoothed)
  String _note = '';         // detected note (nearest 12-TET)
  String? _error;            // mic/audio errors
  bool _permissionPermanentlyDenied = false;

  // Stage 3: Smoothing & attack hold
  double _hzDeltaEma = 0.0;
  bool _hasEma = false;
  DateTime? _attackUntil;
  double _prevRms = 0.0;

  // Tracking for delayed logging
  DateTime? _noteStartTime; // when the current note was first pressed
  bool _hasLoggedForCurrentNote = false; // whether we've logged for this press

  PitchAlgo _algo = PitchAlgo.advanced;

  late final AudioRecorderService _recorder;
  StreamSubscription<Uint8List>? _audioSub;
  late final adv.HpsPitchEngine _advancedEngine;
  late final simple.HPSPitchDetector _simpleEngine;
  PitchDebug? _lastDebug;
  bool _isRecording = false;
  Future<void>? _pendingStop;

  // Guitar standard tuning (Hz)
  final Map<String, double> _stringFreq = const {
    'E_high': 329.63, // E4
    'B': 246.94,      // B3
    'G': 196.00,      // G3
    'D': 146.83,      // D3
    'A': 110.00,      // A2
    'E_low': 82.41,   // E2
  };

  final Map<String, String> _stringLabel = const {
    'E_high': 'E',
    'B': 'B',
    'G': 'G',
    'D': 'D',
    'A': 'A',
    'E_low': 'E',
  };

  @override
  void initState() {
    super.initState();

    // Recorder: constant frame size is important for stable tuning
    _recorder = AudioRecorderService(
      sampleRate: 48000,
      samplesPerFrame: 4096, // hop ~85 ms; engine zero-pads internally for resolution
    );

    // Engine with accuracy + debug
    _advancedEngine = adv.HpsPitchEngine(
      sampleRate: 48000,
      windowLength: 4096,
      hpsOrder: 5,
      minF: 50,
      maxF: 1000,
      levelDbGate: -45.0,
      smoothCount: 5,
      padPow2: 2,
      preEmphasis: 0.97,
      tiltAlpha: 0.5,
      sampleRateCorrection: 1.0,
      onDebug: _onEngineDebug,
    );

    _simpleEngine = simple.HPSPitchDetector();
  }

  Future<void> _startAudio() async {
    if (_pendingStop != null) {
      await _pendingStop;
    }
    if (_isRecording) return;
    try {
      final status = await Permission.microphone.request();
      if (!status.isGranted) {
        if (!mounted) return;
        setState(() {
          _error = 'Mikrofonin käyttö on estetty. Salli se laitteen asetuksissa.';
          _permissionPermanentlyDenied = status.isPermanentlyDenied;
          _selectedId = null;
          _noteStartTime = null;
          _hasLoggedForCurrentNote = false;
          _hasEma = false;
          _lastSelectedId = null;
        });
        return;
      }

      await _recorder.start();
      _audioSub = _recorder.frames.listen(
        _processFrame,
        onError: (Object err) {
          unawaited(_stopAudio());
          if (!mounted) return;
          setState(() {
            _error = err.toString();
            _permissionPermanentlyDenied = false;
            _selectedId = null;
            _noteStartTime = null;
            _hasLoggedForCurrentNote = false;
            _hasEma = false;
            _lastSelectedId = null;
          });
        },
        cancelOnError: true,
      );
      _isRecording = true;
      if (!mounted) return;
      setState(() {
        _error = null;
        _permissionPermanentlyDenied = false;
      });
    } catch (err) {
      _isRecording = false;
      if (!mounted) return;
      setState(() {
        _error = err.toString();
        _permissionPermanentlyDenied = false;
        _selectedId = null;
        _noteStartTime = null;
        _hasLoggedForCurrentNote = false;
        _hasEma = false;
        _lastSelectedId = null;
      });
    }
  }

  Future<void> _stopAudio() {
    if (_pendingStop != null) {
      return _pendingStop!;
    }
    if (!_isRecording) {
      return Future<void>.value();
    }

    final future = () async {
      await _audioSub?.cancel();
      _audioSub = null;
      await _recorder.stop();
      _isRecording = false;
      _attackUntil = null;
      _prevRms = 0.0;
    }();

    _pendingStop = future;
    future.whenComplete(() {
      _pendingStop = null;
    });
    return future;
  }

  // Helper: exponential moving average
  static double _ema(double prev, double x, double alpha) => alpha * x + (1 - alpha) * prev;

  // Engine → debug payload per frame
  void _onEngineDebug(PitchDebug dbg) {
    _lastDebug = dbg;
  }

  // Print one structured line when user taps a string
  void _logCurrentStats(String buttonId) {
    if (_lastDebug == null) {
      debugPrint('Note pressed: $buttonId (no debug data yet)');
      return;
    }
    final dbg = _lastDebug!;
    final key = buttonId;
    final fTarget = _stringFreq[buttonId] ?? 0.0;

    final hzUi = (fTarget > 0 && dbg.f0Interp > 0)
        ? (dbg.f0Interp - fTarget)
        : double.nan;

    debugPrint(
      'Note pressed: $key | '
      'f_tgt=${fTarget.toStringAsFixed(2)} '
      'f_raw=${dbg.f0Raw.toStringAsFixed(3)} '
      'f_peak=${dbg.f0Interp.toStringAsFixed(3)} '
      'octFix=${dbg.octaveCorrected ? 1 : 0} '
      'f_med=${(_frequency > 0 ? _frequency : dbg.f0Interp).toStringAsFixed(3)} '
      'deltaHz=${hzUi.toStringAsFixed(2)} '
      'RMS=${dbg.rms.toStringAsFixed(4)} '
      'dBFS=${dbg.dbfs.toStringAsFixed(1)} '
      'conf=${dbg.confidence.toStringAsFixed(2)} '
      'prom=${dbg.prominence.toStringAsFixed(2)} '
      'HPSord=${dbg.hpsOrderUsed} '
      'peakBin=${dbg.peakBin} '
      'binHz=${dbg.binHz.toStringAsFixed(3)} '
      'fftLen=${dbg.fftLen} '
      'fsCorr=${dbg.fsCorrection.toStringAsFixed(6)} '
      'tiltAlpha=${dbg.tiltAlpha.toStringAsFixed(2)} '
      'preEmph=${dbg.preEmphasis.toStringAsFixed(2)} '
      'gate=${dbg.levelDbGate.toStringAsFixed(1)}'
    );
  }

  void _processFrame(Uint8List pcm16Le) {
    // Attack detection: if RMS jumps fast, hold for ~150 ms
    final now = DateTime.now();
    final double currentRmsRaw = _computeRms(pcm16Le);
    final double currentDb = 20.0 * math.log(currentRmsRaw + 1e-12) / math.ln10;

    if (currentDb - _prevRms > 6.0 /* dB jump */) {
      _attackUntil = now.add(const Duration(milliseconds: 150));
    }
    _prevRms = currentDb;

    if (_attackUntil != null && now.isBefore(_attackUntil!)) {
      // Still in attack hold; don't update UI
      return;
    }

    if (_selectedId == null) {
      return;
    }
    final double? target = _stringFreq[_selectedId!];
    if (target == null) {
      return;
    }

    late double uiF0;
    late double uiConfidence;
    late double uiRms;
    late String uiNote;

    if (_algo == PitchAlgo.advanced) {
      final adv.PitchResult? resultNullable = _advancedEngine.processPcm16LeTargeted(
        pcm16Le,
        fTarget: target,
      );

      if (resultNullable == null || !mounted) return;
      final adv.PitchResult result = resultNullable;

      if (_selectedId != _lastSelectedId) {
        _advancedEngine.resetSmoother();
        _hasEma = false;
        _lastSelectedId = _selectedId;
      } else if (_frequency > 0 &&
          (result.f0 - _frequency).abs() / math.max(result.f0, 1e-9) > 0.12) {
        _advancedEngine.resetSmoother();
      }

      uiF0 = result.f0;
      uiConfidence = result.confidence;
      uiRms = result.rms;
      uiNote = result.note;
    } else {
      final int len = pcm16Le.lengthInBytes ~/ 2;
      final bd = pcm16Le.buffer.asByteData();
      final mono = Float64List(len);
      for (int i = 0; i < len; i++) {
        mono[i] = bd.getInt16(i * 2, Endian.little) / 32768.0;
      }

      final simple.PitchResult simpleRes = _simpleEngine.processFrame(
        mono,
        numChannels: 1,
        sampleRate: simple.HPSPitchDetector.sampleRate,
      );

      if (!simpleRes.voiced || simpleRes.f0Smoothed == null || !mounted) {
        return;
      }

      uiF0 = simpleRes.f0Smoothed!;
      final _NoteAndCents noteAndCents = _freqToNote(uiF0);
      uiNote = noteAndCents.name;
      uiConfidence = ((simpleRes.dbLevel + 60.0) / 60.0).clamp(0.0, 1.0);
      uiRms = currentRmsRaw;
    }

    if (_algo == PitchAlgo.advanced &&
        _selectedId != null &&
        _noteStartTime != null &&
        !_hasLoggedForCurrentNote) {
      final elapsed = DateTime.now().difference(_noteStartTime!);
      if (elapsed.inSeconds >= 5) {
        _logCurrentStats(_selectedId!);
        _hasLoggedForCurrentNote = true;
      }
    }

    double hzDeltaRaw = 0.0;
    final double referenceHz = target;
    if (referenceHz > 0) {
      hzDeltaRaw = (uiF0 - referenceHz).clamp(-25.0, 25.0);
    }

    const double alpha = 0.22;
    if (_hasEma) {
      _hzDeltaEma = _ema(_hzDeltaEma, hzDeltaRaw, alpha);
    } else {
      _hzDeltaEma = hzDeltaRaw;
      _hasEma = true;
    }

    if (uiConfidence >= 0.55) {
      setState(() {
        _hzDelta = _hzDeltaEma;
        _confidence = uiConfidence.clamp(0.0, 1.0);
        _rms = uiRms;
        _frequency = uiF0;
        _note = uiNote.isEmpty ? '-' : uiNote;
        _error = null;
      });
    }
  }

  // Helper to compute RMS from PCM16 buffer
  double _computeRms(Uint8List pcm16Le) {
    final len = pcm16Le.lengthInBytes ~/ 2;
    if (len == 0) return 0.0;
    final bd = pcm16Le.buffer.asByteData();
    double sum = 0.0;
    for (int i = 0; i < len; i++) {
      final v = bd.getInt16(i * 2, Endian.little) / 32768.0;
      sum += v * v;
    }
    return math.sqrt(sum / len);
  }

  @override
  void dispose() {
    _audioSub?.cancel();
    unawaited(_recorder.dispose());
    super.dispose();
  }

  Widget _tuningButton({
    required Alignment alignment,
    required String id,
    required String label,
    VoidCallback? onPressed,
  }) {
    return Align(
      alignment: alignment,
      child: SizedBox(
        width: 42,
        height: 42,
        child: ElevatedButton(
          onPressed: () {
            final bool wasSelected = _selectedId == id;
            setState(() {
              if (wasSelected) {
                _selectedId = null;
                _noteStartTime = null;
                _hasLoggedForCurrentNote = false;
                _lastSelectedId = null;
              } else {
                _selectedId = id;
                _advancedEngine.resetSmoother();
                _simpleEngine.clearHistory();
                _hasEma = false;
                _noteStartTime = DateTime.now();
                _hasLoggedForCurrentNote = false;
              }
            });
            if (wasSelected) {
              unawaited(_stopAudio());
            } else {
              unawaited(_startAudio());
            }
            if (onPressed != null) onPressed();
          },
          style: ElevatedButton.styleFrom(
            shape: const CircleBorder(),
            padding: EdgeInsets.zero,
            backgroundColor: _selectedId == id ? Colors.grey[800] : Colors.white,
            foregroundColor: _selectedId == id ? Colors.white : Colors.black,
            elevation: 4,
          ),
          child: Text(label, style: const TextStyle(fontSize: 14)),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final displayNote = _note.isEmpty ? '-' : _note;
    final displayFreq = _frequency > 0 ? '${_frequency.toStringAsFixed(2)} Hz' : '--';
    final displayConfidence = '${(_confidence * 100).clamp(0, 100).toStringAsFixed(0)}%';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Tuner'),
      ),
      body: Column(
        children: [
          const Spacer(flex: 2),

          // Gauge
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            child: SizedBox(
              height: 140,
              width: double.infinity,
              child: NeedleGauge(
                hzDelta: _hzDelta,
                confidence: _confidence,
              ),
            ),
          ),

          if (_error != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
                textAlign: TextAlign.center,
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: Column(
                children: [
                  Text('Note: $displayNote  •  $displayFreq'),
                  const SizedBox(height: 4),
                  Text('RMS: ${_rms.toStringAsFixed(3)}  •  Confidence: $displayConfidence'),
                ],
              ),
            ),

          if (_permissionPermanentlyDenied)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: ElevatedButton(
                onPressed: openAppSettings,
                child: const Text('Avaa asetukset'),
              ),
            ),

          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ChoiceChip(
                  label: const Text('Simple (HPS)'),
                  selected: _algo == PitchAlgo.simple,
                  onSelected: (_) {
                    setState(() {
                      _algo = PitchAlgo.simple;
                      _advancedEngine.resetSmoother();
                      _simpleEngine.clearHistory();
                      _hasEma = false;
                    });
                  },
                ),
                const SizedBox(width: 8),
                ChoiceChip(
                  label: const Text('Advanced+'),
                  selected: _algo == PitchAlgo.advanced,
                  onSelected: (_) {
                    setState(() {
                      _algo = PitchAlgo.advanced;
                      _advancedEngine.resetSmoother();
                      _simpleEngine.clearHistory();
                      _hasEma = false;
                    });
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          const Spacer(flex: 1),

          // Guitar image + string buttons
          SizedBox(
            height: 380,
            width: double.infinity,
            child: Center(
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Image.asset(
                    'assets/images/kitara.png',
                    width: 320,
                    height: 320,
                    fit: BoxFit.contain,
                  ),

                  if (_selectedId != null)
                    Align(
                      alignment: const Alignment(-0.8, -1.2),
                      child: Text(
                        '${_stringLabel[_selectedId] ?? ''} = ${_stringFreq[_selectedId]!.round()} Hz',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w600,
                          color: Theme.of(context).textTheme.bodyLarge?.color ?? Colors.black,
                        ),
                      ),
                    ),

                  // LEFT column: D, A, E (low)
                  _tuningButton(
                    alignment: const Alignment(-0.8, -0.7),
                    id: 'D',
                    label: 'D',
                    onPressed: () {},
                  ),
                  _tuningButton(
                    alignment: const Alignment(-0.8, -0.3),
                    id: 'A',
                    label: 'A',
                    onPressed: () {},
                  ),
                  _tuningButton(
                    alignment: const Alignment(-0.8, 0.1),
                    id: 'E_low',
                    label: 'E',
                    onPressed: () {},
                  ),

                  // RIGHT column: G, B, E (high)
                  _tuningButton(
                    alignment: const Alignment(0.8, -0.7),
                    id: 'G',
                    label: 'G',
                    onPressed: () {},
                  ),
                  _tuningButton(
                    alignment: const Alignment(0.8, -0.3),
                    id: 'B',
                    label: 'B',
                    onPressed: () {},
                  ),
                  _tuningButton(
                    alignment: const Alignment(0.8, 0.1),
                    id: 'E_high',
                    label: 'E',
                    onPressed: () {},
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 24),
        ],
      ),
    );
  }
}
