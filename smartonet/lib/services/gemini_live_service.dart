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

  GeminiConnectionState _state = GeminiConnectionState.idle;
  GeminiConnectionState get state => _state;

  String? _apiKey = '';

  bool _setupComplete = false;
  int _retry = 0;

  String _url(String apiKey) {
    return "wss://generativelanguage.googleapis.com/ws/google.ai.generativelanguage.v1beta.GenerativeService.BidiGenerateContent?key=";
  }

  Future<void> connect(String apiKey) async {
    if (_state == GeminiConnectionState.connecting ||
        _state == GeminiConnectionState.connected ||
        _state == GeminiConnectionState.ready) {
      return;
    }

    _apiKey = apiKey;
    _setupComplete = false;

    await _socketSub?.cancel();
    await _channel?.sink.close();

    _setState(GeminiConnectionState.connecting);

    try {
      final uri = Uri.parse(_url(apiKey));
      debugPrint("Connecting websocket → $uri");

      _channel = WebSocketChannel.connect(uri);
      await _channel!.ready;

      debugPrint("WebSocket connected");

      _setState(GeminiConnectionState.connected);

      _retry = 0;

      _listen();
      _sendSetup();
    } catch (e) {
      debugPrint("WebSocket connection error: $e");
      _reconnect();
    }
  }

  final _audioCompleteController = StreamController<void>.broadcast();
  Stream<void> get onAudioComplete => _audioCompleteController.stream;

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
            debugPrint("Unknown message type: ${message.runtimeType}");
            return;
          }

          debugPrint("WS message: $jsonString");

          final data = jsonDecode(jsonString);

          /// setup complete
          if (data["setupComplete"] != null) {
            debugPrint("Gemini setup complete");

            _setupComplete = true;
            _setState(GeminiConnectionState.ready);
            return;
          }

          /// audio response
          if (data["serverContent"] != null) {
            final server = data["serverContent"];

            /// audio chunks
            if (server["modelTurn"] != null) {
              final parts = server["modelTurn"]["parts"];

              for (final part in parts) {
                if (part["inlineData"] != null) {
                  final audioBase64 = part["inlineData"]["data"];
                  final audioBytes = base64Decode(audioBase64);

                  _audioController.add(audioBytes);
                }
              }
            }

            /// AI nói xong
            if (server["turnComplete"] == true) {
              debugPrint("AI audio turn complete");
              _audioCompleteController.add(null);
            }
          }
        } catch (e) {
          debugPrint("Parse error: $e");
        }
      },

      onError: (error) {
        debugPrint("WebSocket error: $error");
        _reconnect();
      },

      onDone: () {
        debugPrint("WebSocket closed");

        final code = _channel?.closeCode;
        final reason = _channel?.closeReason;

        debugPrint("Close code: $code");
        debugPrint("Close reason: $reason");

        _reconnect();
      },
    );
  }

  /// setup message
  void _sendSetup() {
    final setup = {
      "setup": {
        "model": "models/gemini-2.5-flash-native-audio-preview-12-2025",
        "generationConfig": {
          "responseModalities": ["AUDIO"],
        },
      },
    };

    _channel?.sink.add(jsonEncode(setup));

    debugPrint("Sent setup message");
  }

  /// send audio
  void sendAudio(Uint8List audio) {
    if (!_setupComplete || _state != GeminiConnectionState.ready) {
      return;
    }

    final message = {
      "realtimeInput": {
        "mediaChunks": [
          {"mimeType": "audio/pcm;rate=16000", "data": base64Encode(audio)},
        ],
      },
    };

    _channel?.sink.add(jsonEncode(message));
  }

  void interruptAI() {
    if (!_setupComplete || _state != GeminiConnectionState.ready) return;

    final message = {
      "clientContent": {
        "turns": [
          {"role": "user", "parts": []},
        ],
        "turnComplete": true,
      },
    };

    _channel?.sink.add(jsonEncode(message));
    debugPrint("Sent interrupt signal to AI");
  }

  void _reconnect() {
    if (_state == GeminiConnectionState.reconnecting) return;

    _setState(GeminiConnectionState.reconnecting);

    _retry++;

    final delay = Duration(seconds: (1 << _retry).clamp(1, 10));

    debugPrint("Reconnect in ${delay.inSeconds}s");

    Future.delayed(delay, () {
      if (_apiKey != null) {
        connect(_apiKey!);
      }
    });
  }

  Future<void> disconnect() async {
    _apiKey = null;
    await _socketSub?.cancel();
    _socketSub = null;
    await _channel?.sink.close();
    _channel = null;

    _setState(GeminiConnectionState.closed);
  }

  void _setState(GeminiConnectionState s) {
    _state = s;
    debugPrint("WebSocket state → $_state");
  }

  Future<void> sendUserAudio(List<Uint8List> chunks) async {
    if (!_setupComplete || _state != GeminiConnectionState.ready) return;

    for (final audio in chunks) {
      final message = {
        "realtimeInput": {
          "mediaChunks": [
            {"mimeType": "audio/pcm;rate=16000", "data": base64Encode(audio)},
          ],
        },
      };

      _channel?.sink.add(jsonEncode(message));
    }

    /// báo cho Gemini biết user đã nói xong
    final turnComplete = {
      "clientContent": {
        "turns": [
          {
            "role": "user",
            "parts": [
              {
                "inlineData": {
                  "mimeType": "audio/pcm;rate=16000",
                  "data": "BASE64_AUDIO",
                },
              },
            ],
          },
        ],
        "turnComplete": true,
      },
    };

    _channel?.sink.add(jsonEncode(turnComplete));
  }

  void dispose() {
  disconnect();
  _audioController.close();
  _audioCompleteController.close();
}
}
