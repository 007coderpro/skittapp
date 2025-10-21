import 'package:flutter/material.dart';
import '../features/tuner/presentation/tuner_page.dart';

/// Pääsovellus Riverpod-wrapperilla
class App extends StatelessWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Kitaraviritys',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const TunerPage(),
      debugShowCheckedModeBanner: false,
    );
  }
}
