import 'dart:async';
import 'dart:typed_data';
import 'package:record/record.dart';

class VoiceService {
  final AudioRecorder _recorder = AudioRecorder();

  final List<Uint8List> _chunks = [];

  StreamSubscription<Uint8List>? _micSub;

  final _micController = StreamController<Uint8List>.broadcast();
  Stream<Uint8List> get audioStream => _micController.stream;

  Future<void> startRecording() async {

    if (!await _recorder.hasPermission()) {
      throw Exception("Microphone permission denied");
    }

    _chunks.clear();

    final stream = await _recorder.startStream(
      const RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: 16000,
        numChannels: 1,
      ),
    );

    _micSub = stream.listen((data) {
      _chunks.add(data);
      _micController.add(data);
    });
  }

  Future<List<Uint8List>> stopRecording() async {

    await _micSub?.cancel();
    await _recorder.stop();

    return List.from(_chunks);
  }

  void dispose() {
    _recorder.dispose();
    _micController.close();
  }
}