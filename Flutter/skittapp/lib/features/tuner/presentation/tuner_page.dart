import 'dart:async';
import 'dart:typed_data';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:skittapp/core/audio/audio_recorder.dart';
import 'package:skittapp/features/tuner/application/pitch_engine.dart';
import 'package:skittapp/features/tuner/application/debug.dart';

import 'widgets/needle_gauge.dart';

/// Tuner-näkymä: mittari + nuotti
class TunerPage extends StatefulWidget {
  const TunerPage({Key? key}) : super(key: key);

  @override
  State<TunerPage> createState() => _TunerPageState();
}

class _TunerPageState extends State<TunerPage> {
  // UI state
  double _cents = 0.0;       // tuning offset (UI may lock to selected string)
  double _confidence = 0.0;  // 0.0 - 1.0
  String? _selectedId;       // currently selected/toggled string
  String? _lastSelectedId;   // to detect key change → reset smoother
  double _rms = 0.0;         // audio level
  double _frequency = 0.0;   // detected pitch in Hz (smoothed)
  String _note = '';         // detected note (nearest 12-TET)
  String? _error;            // mic/audio errors
  bool _permissionPermanentlyDenied = false;

  // Stage 3: Smoothing & attack hold
  double _centsEma = 0.0;
  bool _hasEma = false;
  DateTime? _attackUntil;
  double _prevRms = 0.0;

  // Tracking for delayed logging
  DateTime? _noteStartTime; // when the current note was first pressed
  bool _hasLoggedForCurrentNote = false; // whether we've logged for this press

  late final AudioRecorderService _recorder;
  StreamSubscription<Uint8List>? _audioSub;
  late final HpsPitchEngine _engine;
  PitchDebug? _lastDebug;

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
    _engine = HpsPitchEngine(
      sampleRate: 48000,
      windowLength: 4096,
      hpsOrder: 5,
      minF: 50,
      maxF: 1000,
      levelDbGate: -45.0,
      smoothCount: 5,
      padPow2: 2,          // x4 FFT → ~2.93 Hz bin spacing @ 48k/4096
      preEmphasis: 0.97,   // stabilize spectral tilt
      tiltAlpha: 0.5,      // enable tilt compensation (helps low-E bias)
      sampleRateCorrection: 1.0, // set after quick 440 Hz calibration if needed
      onDebug: _onEngineDebug,   // debug logging (structured)
    );

    unawaited(_startAudio());
  }

  Future<void> _startAudio() async {
    try {
      final status = await Permission.microphone.request();
      if (!status.isGranted) {
        if (!mounted) return;
        setState(() {
          _error = 'Mikrofonin käyttö on estetty. Salli se laitteen asetuksissa.';
          _permissionPermanentlyDenied = status.isPermanentlyDenied;
        });
        return;
      }

      await _recorder.start();
      _audioSub = _recorder.frames.listen(
        _processFrame,
        onError: (Object err) {
          if (!mounted) return;
          setState(() {
            _error = err.toString();
            _permissionPermanentlyDenied = false;
          });
        },
      );
    } catch (err) {
      if (!mounted) return;
      setState(() {
        _error = err.toString();
        _permissionPermanentlyDenied = false;
      });
    }
  }

  // Helper: cents difference f vs target
  static double _centsFromFreq(double f, double target) {
    if (f <= 0 || target <= 0) return 0.0;
    return 1200.0 * (math.log(f / target) / math.ln2);
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

    final centsUi = (fTarget > 0 && dbg.f0Interp > 0)
        ? _centsFromFreq(dbg.f0Interp, fTarget)
        : double.nan;

    debugPrint(
      'Note pressed: $key | '
      'f_tgt=${fTarget.toStringAsFixed(2)} '
      'f_raw=${dbg.f0Raw.toStringAsFixed(3)} '
      'f_peak=${dbg.f0Interp.toStringAsFixed(3)} '
      'octFix=${dbg.octaveCorrected ? 1 : 0} '
      'f_med=${(_frequency > 0 ? _frequency : dbg.f0Interp).toStringAsFixed(3)} '
      'cents_ui=${centsUi.toStringAsFixed(1)} '
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

    // Use targeted mode when a string is selected, otherwise use regular mode
    final double? target = _selectedId != null ? _stringFreq[_selectedId!] : null;
    
    final PitchResult? resultNullable;
    if (_selectedId != null && target != null) {
      // Pressed-note mode: use THS search
      resultNullable = _engine.processPcm16LeTargeted(
        pcm16Le,
        fTarget: target,
      );
    } else {
      // Regular mode: wide-band HPS
      resultNullable = _engine.processPcm16Le(
        pcm16Le,
        targetHz: null,
        narrowSearchToTarget: false,
        targetHarmTol: 0.06,
      );
    }

    if (resultNullable == null || !mounted) return;
    
    // Now we know result is non-null
    final result = resultNullable;

    // Reset smoother on key change or on very large jumps (>12% frame-to-frame)
    if (_selectedId != _lastSelectedId) {
      _engine.resetSmoother();
      _hasEma = false; // reset EMA on key change
      _lastSelectedId = _selectedId;
    } else if (_frequency > 0 &&
        (result.f0 - _frequency).abs() / math.max(result.f0, 1e-9) > 0.12) {
      _engine.resetSmoother();
    }

    // Check if 5 seconds have passed since note was pressed, and log if so
    if (_selectedId != null && 
        _noteStartTime != null && 
        !_hasLoggedForCurrentNote) {
      final elapsed = DateTime.now().difference(_noteStartTime!);
      if (elapsed.inSeconds >= 5) {
        _logCurrentStats(_selectedId!);
        _hasLoggedForCurrentNote = true; // log only once per press
      }
    }

    // Compute UI cents: if a string is selected, show deviation vs that target
    double centsRaw = result.cents;
    if (target != null) {
      centsRaw = _centsFromFreq(result.f0, target).clamp(-100.0, 100.0);
    }

    // EMA smoothing on cents (τ ≈ 200 ms). If hop is ~85 ms => alpha ~ 0.22
    const double alpha = 0.22;
    if (_hasEma) {
      _centsEma = _ema(_centsEma, centsRaw, alpha);
    } else {
      _centsEma = centsRaw;
      _hasEma = true;
    }

    // Lock display only when stable and confident
    if (result.confidence >= 0.55) {
      setState(() {
        _cents = _centsEma;
        _confidence = result.confidence.clamp(0.0, 1.0).toDouble();
        _rms = result.rms;
        _frequency = result.f0;
        _note = result.note;
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
            setState(() {
              if (_selectedId == id) {
                _selectedId = null;
                _noteStartTime = null; // reset timing when unselecting
                _hasLoggedForCurrentNote = false;
              } else {
                _selectedId = id;
                _engine.resetSmoother();   // reset smoothing when picking a new string
                _noteStartTime = DateTime.now(); // start timing for this note
                _hasLoggedForCurrentNote = false; // reset log flag
              }
            });
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
        actions: [
          IconButton(
            tooltip: 'Calibrate 440→fs',
            onPressed: () {
              // Quick in-app helper:
              // If you play 440 Hz and the app shows f_meas, set correction = 440/f_meas.
              final fMeas = _frequency;
              if (fMeas > 0) {
                final corr = (440.0 / fMeas);
                _engine.setSampleRateCorrection((_engine.sampleRateCorrection * corr));
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Sample-rate correction set to ${_engine.sampleRateCorrection.toStringAsFixed(6)}')),
                );
              }
            },
            icon: const Icon(Icons.tune),
          ),
        ],
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
                cents: _cents,
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
