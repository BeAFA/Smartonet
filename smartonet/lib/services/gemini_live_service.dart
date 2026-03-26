import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

enum GeminiConnectionState {
  idle,
  connecting,
  connected,
  ready,
  reconnecting,
  closed,
}

class GeminiLiveService {
  WebSocketChannel? _channel;
  StreamSubscription? _socketSub;

  final _audioController = StreamController<Uint8List>.broadcast();
  Stream<Uint8List> get audioStream => _audioController.stream;

  final _audioCompleteController = StreamController<void>.broadcast();
  Stream<void> get onAudioComplete => _audioCompleteController.stream;

  GeminiConnectionState _state = GeminiConnectionState.idle;
  GeminiConnectionState get state => _state;

  bool _setupComplete = false;
  int _retry = 0;

  final String _serverUrl = "ws://192.168.1.38:8080/ws";

  Future<void> connect() async {
    if (_state == GeminiConnectionState.connecting ||
        _state == GeminiConnectionState.connected ||
        _state == GeminiConnectionState.ready) {
      return;
    }

    _setupComplete = false;

    await _socketSub?.cancel();
    await _channel?.sink.close();

    _setState(GeminiConnectionState.connecting);

    try {
      final uri = Uri.parse(_serverUrl);
      debugPrint("🔗 Đang kết nối tới máy chủ trung chuyển → $uri");

      _channel = WebSocketChannel.connect(uri);
      await _channel!.ready;

      debugPrint("✅ Đã kết nối WebSocket thành công");

      _setState(GeminiConnectionState.connected);
      _retry = 0;

      _listen();
      _sendSetup(); // Gửi lệnh Setup ngay sau khi kết nối
    } catch (e) {
      debugPrint("❌ Lỗi kết nối WebSocket: $e");
      _reconnect();
    }
  }

  void _listen() {
    _socketSub = _channel!.stream.listen(
      (message) {
        try {
          String jsonString;

          if (message is String) {
            jsonString = message;
          } else if (message is Uint8List) {
            jsonString = utf8.decode(message);
          } else {
            return;
          }

          final data = jsonDecode(jsonString);

          // 1. Nhận xác nhận Setup Complete từ Gemini
          if (data["setupComplete"] != null) {
            debugPrint("🎯 Gemini đã nhận Setup. Sẵn sàng đàm thoại!");
            _setupComplete = true;
            _setState(GeminiConnectionState.ready);
            return;
          }

          // 2. Nhận dữ liệu âm thanh từ Gemini trả về
          if (data["serverContent"] != null) {
            final server = data["serverContent"];

            if (server["modelTurn"] != null) {
              final parts = server["modelTurn"]["parts"];
              for (final part in parts) {
                if (part["inlineData"] != null) {
                  final audioBase64 = part["inlineData"]["data"];
                  final audioBytes = base64Decode(audioBase64);
                  // Bắn raw bytes ra stream để AudioPlayer phát
                  _audioController.add(audioBytes);
                }
              }
            }

            // AI đã nói xong câu đó
            if (server["turnComplete"] == true) {
              debugPrint("🤖 AI đã nói xong.");
              _audioCompleteController.add(null);
            }
          }
        } catch (e) {
          debugPrint("⚠️ Lỗi parse JSON từ Server: $e");
        }
      },
      onError: (error) {
        debugPrint("⚠️ Lỗi luồng WebSocket: $error");
        _reconnect();
      },
      onDone: () {
        debugPrint("🛑 WebSocket đã đóng ngắt");
        _reconnect();
      },
    );
  }

  // ==========================================
  // 2. CẬP NHẬT LẠI MODEL VÀ GỬI SETUP
  // ==========================================
  void _sendSetup() {
    final setup = {
      "setup": {
        // Gọi chính xác tên con AI Native Audio này
        "model": "models/gemini-2.5-flash-native-audio-preview-12-2025",
        "generationConfig": {
          "responseModalities": ["AUDIO"],
          "speechConfig": {
            "voiceConfig": {
              "prebuiltVoiceConfig": {"voiceName": "Aoede"},
            },
          },
        },
        "inputAudioTranscription": {},
      },
    };

    _channel?.sink.add(jsonEncode(setup));
    debugPrint("📤 Đã gửi cấu hình Setup lên Server");
  }

  // ==========================================
  // 3. GỬI ÂM THANH REALTIME TỪ MICRO LÊN SERVER
  // ==========================================
  void sendAudio(Uint8List audio) {
    if (!_setupComplete || _state != GeminiConnectionState.ready) return;

    final message = {
      "realtimeInput": {
        "mediaChunks": [
          {"mimeType": "audio/pcm;rate=16000", "data": base64Encode(audio)},
        ],
      },
    };

    _channel?.sink.add(jsonEncode(message));
  }

  // ==========================================
  // 4. BÁO AI BIẾT USER ĐÃ NÓI XONG HOẶC NGẮT LỜI
  // ==========================================
  void sendTurnComplete() {
    final message = {
      "clientContent": {
        "turns": [
          {
            "role": "user",
            "parts": [
              {"text": "Bạn là trợ lý AI, trả lời bằng giọng nói."},
            ],
          },
        ],
        "turnComplete": true,
      },
    };

    _channel?.sink.add(jsonEncode(message));
  }

  void _reconnect() {
    if (_state == GeminiConnectionState.reconnecting) return;
    _setState(GeminiConnectionState.reconnecting);
    _retry++;
    final delay = Duration(seconds: (1 << _retry).clamp(1, 10));
    debugPrint("🔄 Thử kết nối lại sau ${delay.inSeconds}s...");
    Future.delayed(delay, () {
      connect();
    });
  }

  Future<void> disconnect() async {
    await _socketSub?.cancel();
    _socketSub = null;
    await _channel?.sink.close();
    _channel = null;
    _setState(GeminiConnectionState.closed);
  }

  void _setState(GeminiConnectionState s) {
    _state = s;
    debugPrint("Trạng thái kết nối → $_state");
  }

  void dispose() {
    disconnect();
    _audioController.close();
    _audioCompleteController.close();
  }
}
