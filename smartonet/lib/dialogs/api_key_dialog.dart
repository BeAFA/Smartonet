import 'package:flutter/material.dart';
import '../services/api_key_service.dart';
import '../screens/gemini_api_guide_screen.dart';

class ApiKeyDialog extends StatefulWidget {
  const ApiKeyDialog({super.key});

  @override
  State<ApiKeyDialog> createState() => _ApiKeyDialogState();
}

class _ApiKeyDialogState extends State<ApiKeyDialog> {
  final TextEditingController _keyController = TextEditingController();
  bool _isLoading = true;
  bool _obscureText = true;

  @override
  void initState() {
    super.initState();
    _loadExistingKey();
  }

  // Tải Key cũ lên nếu người dùng đã từng nhập
  Future<void> _loadExistingKey() async {
    final key = await ApiKeyService.getApiKey();
    if (key != null && key.isNotEmpty) {
      _keyController.text = key;
    }
    setState(() {
      _isLoading = false;
    });
  }

  @override
  void dispose() {
    _keyController.dispose();
    super.dispose();
  }

  void _saveKey() async {
    final key = _keyController.text.trim();
    if (key.isEmpty) {
      // Nếu bỏ trống, coi như người dùng muốn xóa Key
      await ApiKeyService.deleteApiKey();
    } else {
      // Lưu Key an toàn vào Secure Storage
      await ApiKeyService.saveApiKey(key);
    }

    if (mounted) {
      Navigator.pop(context, true); // Trả về true để báo là đã lưu
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: _isLoading
            ? const SizedBox(
                height: 100,
                child: Center(child: CircularProgressIndicator()),
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "Cấu hình Trợ lý AI",
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    "Nhập Gemini API Key của bạn để mở khóa tính năng tạo lịch hẹn và ghi chú thông minh bằng giọng nói.",
                    style: TextStyle(fontSize: 14, color: Colors.grey),
                  ),
                  const SizedBox(height: 20),
                  TextField(
                    controller: _keyController,
                    obscureText: _obscureText, // Ẩn/hiện text
                    decoration: InputDecoration(
                      labelText: "Google AI Studio API Key",
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      prefixIcon: const Icon(Icons.key),
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscureText
                              ? Icons.visibility_off
                              : Icons.visibility,
                        ),
                        onPressed: () {
                          setState(() {
                            _obscureText = !_obscureText;
                          });
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  // Gợi ý chỗ lấy Key (Bạn có thể dùng package url_launcher để làm dòng này click được ra trình duyệt)
                  TextButton(
                    onPressed: () async {
                      await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const GeminiApiGuideScreen(),
                        ),
                      );

                      if (context.mounted) {
                        Navigator.pop(context, false);
                      }
                    },
                    child: const Text(
                      "Hướng dẫn lấy Key miễn phí tại Google AI Studio",
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: const Text(
                          "Hủy",
                          style: TextStyle(color: Colors.grey),
                        ),
                      ),
                      const SizedBox(width: 8),
                      FilledButton(
                        onPressed: _saveKey,
                        child: const Text("Lưu Key"),
                      ),
                    ],
                  ),
                ],
              ),
      ),
    );
  }
}
