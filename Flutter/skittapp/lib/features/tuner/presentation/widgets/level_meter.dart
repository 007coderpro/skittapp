import 'package:flutter/material.dart';

/// Äänenvoimakkuusmittari (level [0.0, 1.0])
class LevelMeter extends StatelessWidget {
  final double level;

  const LevelMeter({
    super.key,
    required this.level,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.mic, size: 20, color: Colors.grey),
            const SizedBox(width: 8),
            Text(
              'Äänenvoimakkuus',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: LinearProgressIndicator(
            value: level,
            minHeight: 16,
            backgroundColor: Colors.grey.shade300,
            valueColor: AlwaysStoppedAnimation<Color>(
              _getLevelColor(level),
            ),
          ),
        ),
      ],
    );
  }

  Color _getLevelColor(double level) {
    if (level < 0.3) {
      return Colors.orange;
    } else if (level < 0.7) {
      return Colors.green;
    } else {
      return Colors.red;
    }
  }
}
