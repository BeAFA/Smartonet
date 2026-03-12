import 'package:flutter/material.dart';
import '../services/voice_chat_service.dart';
import '../services/voice_service.dart';
import '../services/gemini_live_service.dart';
import '../services/audio_player_service.dart';

class VoiceChatScreen extends StatefulWidget {
  const VoiceChatScreen({super.key});

  @override
  State<VoiceChatScreen> createState() => _VoiceChatScreenState();
}

class _VoiceChatScreenState extends State<VoiceChatScreen> {
  late VoiceChatService chatService;

  @override
  void initState() {
    super.initState();

    chatService = VoiceChatService(
      voiceService: VoiceService(),
      geminiService: GeminiLiveService(),
      audioService: AudioPlayerService(),
    );

    chatService.addListener(() {
      if (mounted) setState(() {});
    });
  }

  Future<void> startChat() async {
    const apiKey = "AIzaSy...";
    await chatService.start(apiKey);
  }

  Future<void> stopChat() async {
    await chatService.stop();
  }

  @override
  void dispose() {
    chatService.disposeAll();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = chatService.state;

    String status = "";

    switch (state) {
      case VoiceState.listening:
        status = "Đang nghe...";
        break;
      case VoiceState.thinking:
        status = "Đang xử lý...";
        break;
      case VoiceState.speaking:
        status = "AI đang nói...(Chạm để ngắt)";
        break;
      case VoiceState.idle:
        status = "Chạm để bắt đầu";
        break;
    }

    return Scaffold(
      appBar: AppBar(title: const Text("Voice AI Chat"), centerTitle: true),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Icon chữ "AI" tĩnh màu xanh
            GestureDetector(
              onTap: () {
                // Chỉ cho phép ngắt lời khi AI đang nói hoặc đang xử lý
                if (state == VoiceState.speaking ||
                    state == VoiceState.thinking) {
                  chatService.interrupt();
                }
              },
              child: Container(
                width: 180,
                height: 180,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: state == VoiceState.speaking
                      ? Colors.purple.withValues(
                          alpha: 0.15,
                        ) // Đổi màu xíu khi đang nói cho sinh động
                      : Colors.blue.withValues(alpha: 0.15),
                ),
                child: Text(
                  "AI",
                  style: TextStyle(
                    fontSize: 80,
                    fontWeight: FontWeight.bold,
                    color: state == VoiceState.speaking
                        ? Colors.purple
                        : Colors.blue,
                  ),
                ),
              ),
            ),

            const SizedBox(height: 40),

            Text(
              status,
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w500),
            ),

            const SizedBox(height: 50),

            // Nút điều khiển (Bắt đầu / Tạm dừng) ở dưới cùng
            InkWell(
              onTap: () {
                if (state == VoiceState.idle) {
                  startChat();
                } else {
                  stopChat();
                }
              },
              borderRadius: BorderRadius.circular(30),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 32,
                  vertical: 14,
                ),
                decoration: BoxDecoration(
                  color: state == VoiceState.idle
                      ? Colors.blue
                      : Colors.redAccent,
                  borderRadius: BorderRadius.circular(30),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      state == VoiceState.idle ? Icons.play_arrow : Icons.pause,
                      color: Colors.white,
                      size: 28,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      state == VoiceState.idle ? "Bắt đầu" : "Tạm dừng",
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
