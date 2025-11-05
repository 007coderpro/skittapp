import 'package:flutter/material.dart';
import 'widgets/needle_gauge.dart';

/// Tuner-näkymä: mittari + nuotti
class TunerPage extends StatefulWidget {
  const TunerPage({Key? key}) : super(key: key);

  @override
  State<TunerPage> createState() => _TunerPageState();
}

class _TunerPageState extends State<TunerPage> {
// update this as your audio/pitch changes
  double _cents = 0.0; // tuning offset in cents
  double _confidence = 0.0; // detection confidence (0.0 - 1.0)
  String? _selectedId; // currently selected/toggled button

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
              } else {
                _selectedId = id;
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
    return Scaffold(
      appBar: AppBar(title: const Text('Tuner')),
      body: Column(
        children: [
          // push content down so gauge and image sit lower
          Spacer(flex: 2),

          // NEEDLE GAUGE (lower on page)
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

          // image + buttons area
          Spacer(flex: 1),

          SizedBox(
            height: 380, // increase area to accommodate bigger image
            width: double.infinity,
            child: Center(
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // Bigger guitar image
                  Image.asset(
                    'assets/images/kitara.png',
                    width: 320,
                    height: 320,
                    fit: BoxFit.contain,
                  ),

                  // LEFT column: top->down D, A, E
                  _tuningButton(
                    alignment: const Alignment(-0.8, -0.7), // top-left
                    id: 'D',
                    label: 'D',
                    onPressed: () => debugPrint('D pressed'),
                  ),
                  _tuningButton(
                    alignment: const Alignment(-0.8, -0.3), // middle-left
                    id: 'A',
                    label: 'A',
                    onPressed: () => debugPrint('A pressed'),
                  ),
                  _tuningButton(
                    alignment: const Alignment(-0.8, 0.1), // bottom-left
                    id: 'E_low',
                    label: 'E',
                    onPressed: () => debugPrint('E pressed'),
                  ),

                  // RIGHT column: top->down G, B, E
                  _tuningButton(
                    alignment: const Alignment(0.8, -0.7), // top-right
                    id: 'G',
                    label: 'G',
                    onPressed: () => debugPrint('G pressed'),
                  ),
                  _tuningButton(
                    alignment: const Alignment(0.8, -0.3), // middle-right
                    id: 'B',
                    label: 'B',
                    onPressed: () => debugPrint('B pressed'),
                  ),
                  _tuningButton(
                    alignment: const Alignment(0.8, 0.1), // bottom-right
                    id: 'E_high',
                    label: 'E',
                    onPressed: () => debugPrint('E (high) pressed'),
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