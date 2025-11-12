import 'package:flutter/material.dart';
import 'dart:math' as math;

/// Neulakello viritykselle (cents [-50, +50])
class NeedleGauge extends StatelessWidget {
  final double cents;
  final double confidence;

  const NeedleGauge({
    super.key,
    required this.cents,
    required this.confidence,
  });

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: const Size(300, 200),
      painter: _NeedleGaugePainter(
        cents: cents.clamp(-50.0, 50.0),
        confidence: confidence,
      ),
    );
  }
}

class _NeedleGaugePainter extends CustomPainter {
  final double cents;
  final double confidence;

  _NeedleGaugePainter({
    required this.cents,
    required this.confidence,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height * 0.8);
    final radius = size.width * 0.4;
    const arcStroke = 10.0; // use one stroke width everywhere

    // Tausta-arc
    final arcPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = arcStroke
      ..color = Colors.grey.shade300;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      math.pi,
      math.pi,
      false,
      arcPaint,
    );

    // Värillinen arc (vihreä keskellä, punainen reunoilla)
    final coloredArcPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = arcStroke;

    // Piirrä värisegmentit
    final segments = 20;
    for (int i = 0; i < segments; i++) {
      final startAngle = math.pi + (i * math.pi / segments);
      final sweepAngle = math.pi / segments;
      
      final ratio = (i / segments - 0.5).abs() * 2; // 0 keskellä, 1 reunoilla
      final color = Color.lerp(Colors.green, Colors.red, ratio)!;
      
      coloredArcPaint.color = color;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        startAngle,
        sweepAngle,
        false,
        coloredArcPaint,
      );
    }

    // Keskiviiva
    final centerLinePaint = Paint()
      ..color = Colors.black
      ..strokeWidth = 2;

    canvas.drawLine(
      Offset(center.dx, center.dy - radius - 20),
      Offset(center.dx, center.dy - radius + 10),
      centerLinePaint,
    );

    // Neula
    if (confidence > 0.3) {
      // Map [-50, +50] cents onto [π, 2π] semicircle with 0 at 1.5π (straight up)
      // cents = -50 → angle = π (left)
      // cents = 0   → angle = 1.5π (up)
      // cents = +50 → angle = 2π (right)
      final needleAngle = 1.5 * math.pi + (cents / 50.0) * 0.5 * math.pi;
      
      // Make the tip land close to the arc edge (leave tiny 2px margin)
      final needleLength = radius - arcStroke / 2 - 2;

      final needlePaint = Paint()
        ..color = Colors.red
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round;

      final needleEnd = Offset(
        center.dx + needleLength * math.cos(needleAngle),
        center.dy + needleLength * math.sin(needleAngle),
      );

      canvas.drawLine(center, needleEnd, needlePaint);

      // Dot at the TIP (not at the center)
      canvas.drawCircle(needleEnd, 6, Paint()..color = Colors.red.shade700);
    }

    // Tekstit: -50, 0, +50
    final textStyle = TextStyle(
      color: Colors.grey.shade700,
      fontSize: 14,
      fontWeight: FontWeight.bold,
    );

    _drawText(canvas, '-50', Offset(center.dx - radius - 20, center.dy), textStyle);
    _drawText(canvas, '0', Offset(center.dx, center.dy - radius - 30), textStyle);
    _drawText(canvas, '+50', Offset(center.dx + radius + 10, center.dy), textStyle);
  }

  void _drawText(Canvas canvas, String text, Offset position, TextStyle style) {
    final textPainter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
    )..layout();

    textPainter.paint(
      canvas,
      Offset(position.dx - textPainter.width / 2, position.dy - textPainter.height / 2),
    );
  }

  @override
  bool shouldRepaint(_NeedleGaugePainter oldDelegate) {
    return cents != oldDelegate.cents || confidence != oldDelegate.confidence;
  }
}
