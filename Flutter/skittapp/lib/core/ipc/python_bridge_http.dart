import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'python_bridge.dart';

class PythonBridgeHttp implements PythonBridge {
  final Uri endpoint; // esim. http://127.0.0.1:8000/process_frame
  PythonBridgeHttp(String baseUrl) : endpoint = Uri.parse('$baseUrl/process_frame');

  @override
  Future<void> start() async {
    // Ei tarvita: HTTP-palvelin oletetaan käynnissä
  }

  @override
  Future<PitchResult?> processFrame(Uint8List pcmInt16, {required int sampleRate}) async {
    final body = jsonEncode({
      'sr': sampleRate,
      'data_b64': base64Encode(pcmInt16),
    });
    final resp = await http.post(
      endpoint,
      headers: {'Content-Type': 'application/json'},
      body: body,
    );
    if (resp.statusCode == 200) {
      final j = jsonDecode(resp.body) as Map<String, dynamic>;
      return PitchResult.fromJson(j);
    } else {
      // Voit logittaa resp.body
      return null;
    }
  }

  @override
  Future<void> stop() async {}
}

