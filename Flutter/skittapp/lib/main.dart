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
