import 'dart:async';
import 'dart:typed_data';
import 'package:record/record.dart';

// class VoiceService {
//   final AudioRecorder _recorder = AudioRecorder();

//   StreamController<Uint8List>? _audioStreamController;

//   Stream<Uint8List>? get audioStream => _audioStreamController?.stream;

//   Future<void> startRecording() async {
//     if (!await _recorder.hasPermission()) {
//       throw Exception("Microphone permission denied");
//     }

//     _audioStreamController = StreamController<Uint8List>();

//     final stream = await _recorder.startStream(
//       const RecordConfig(
//         encoder: AudioEncoder.pcm16bits,
//         sampleRate: 16000,
//         numChannels: 1,
//       ),
//     );

//     stream.listen((data) {
//       _audioStreamController?.add(data);
//     });
//   }

//   Future<void> stopRecording() async {
//     await _recorder.stop();
//     await _audioStreamController?.close();
//   }

//   void dispose() {
//     _recorder.dispose();
//     _audioStreamController?.close();
//   }
// }
class VoiceService {
  final AudioRecorder _recorder = AudioRecorder();

  final List<Uint8List> _chunks = [];

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

    stream.listen((data) {
      _chunks.add(data);
    });
  }

  Future<List<Uint8List>> stopRecording() async {
    await _recorder.stop();
    return List.from(_chunks);
  }

  void dispose() {
    _recorder.dispose();
  }
}