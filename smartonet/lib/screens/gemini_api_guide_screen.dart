import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../dialogs/api_key_dialog.dart';

class GeminiApiGuideScreen extends StatelessWidget {
  const GeminiApiGuideScreen({super.key});

  Future<void> _openAiStudio() async {
    final Uri url = Uri.parse("https://aistudio.google.com/app/apikey");

    if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
      throw Exception("Không mở được Google AI Studio");
    }
  }

  void _openApiKeyDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => const ApiKeyDialog(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Cách lấy Gemini API Key"),
      ),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  Text(
                    "Hướng dẫn lấy API Key từ Google AI Studio",
                    style:
                        TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  SizedBox(height: 16),

                  Text(
                    "Bước 1:",
                    style:
                        TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  Text(
                    "Truy cập trang Google AI Studio.",
                  ),

                  SizedBox(height: 12),

                  Text(
                    "Bước 2:",
                    style:
                        TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  Text(
                    "Đăng nhập bằng tài khoản Google của bạn.",
                  ),

                  SizedBox(height: 12),

                  Text(
                    "Bước 3:",
                    style:
                        TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  Text(
                    "Nhấn nút 'Create API Key'.",
                  ),

                  SizedBox(height: 12),

                  Text(
                    "Bước 4:",
                    style:
                        TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  Text(
                    "Sao chép API Key và quay lại ứng dụng để nhập.",
                  ),

                  SizedBox(height: 30),

                  Text(
                    "Sau khi có API Key, bạn có thể nhập vào ứng dụng để kích hoạt trợ lý AI.",
                    style: TextStyle(color: Colors.grey),
                  ),
                ],
              ),
            ),
          ),

          /// 2 nút ở cuối
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _openAiStudio,
                    child: const Text("Lấy API Key"),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton(
                    onPressed: () {
                      Navigator.pop(context);
                      _openApiKeyDialog(context);
                    },
                    child: const Text("Nhập API Key"),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}