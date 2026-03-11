import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import '../database/models.dart';

class GeminiHttpService {
  static Future<Map<String, dynamic>?> analyzeIntent(
    String userText, {
    List<Note>? currentData,
  }) async {
    // String apiKey = await ApiKeyService.getApiKey() ?? '';
    String apiKey =
        ''; // Xóa dòng này nếu dùng storage

    final url = Uri.parse(
      'https://generativelanguage.googleapis.com/v1beta/models/gemini-3.1-flash-lite-preview:generateContent?key=$apiKey',
    );

    final now = DateTime.now();

    // Tóm tắt dữ liệu hiện có để AI biết đường mà tìm ID
    String contextData = "Danh sách trống.";
    if (currentData != null && currentData.isNotEmpty) {
      contextData = currentData
          .map((n) {
            String type = n.hasAppointment ? "Lịch hẹn" : "Ghi chú";
            return "[$type] ID: ${n.id} | Tiêu đề: '${n.title}' | Nội dung: '${n.content}' | Thời gian: ${n.time.toIso8601String()}";
          })
          .join('\n');
    }

    final prompt =
        '''
Bạn là AI trợ lý ảo thông minh cho ứng dụng ghi chú và lịch hẹn Smartonet.

Thời gian hiện tại của hệ thống: ${now.toIso8601String()}.

DỮ LIỆU HIỆN CÓ CỦA NGƯỜI DÙNG:
$contextData

NHIỆM VỤ:
Phân tích yêu cầu của người dùng và trả về DUY NHẤT một chuỗi JSON hợp lệ. Không sử dụng markdown (không có ```json).

QUY TẮC "type":
1. Yêu cầu có tính hành động (tạo mới, cập nhật, xóa, lên kế hoạch, liệt kê) -> type: "command"
2. Chỉ chào hỏi, tâm sự, hỏi đáp kiến thức chung -> type: "conversation"

QUY TẮC XỬ LÝ HÀNH ĐỘNG (Dành cho mảng "commands"):
- Xử lý đơn & đa tác vụ: Dựa vào yêu cầu, tạo ra 1 hoặc NHIỀU đối tượng lệnh trong mảng "commands".
- Lên kế hoạch/Danh sách/Chuỗi sự kiện: Nếu yêu cầu là một kế hoạch dài ngày, một danh sách nhiều mục, hoặc một chuỗi công việc (VD: lộ trình học, thực đơn, kế hoạch du lịch, danh sách việc làm), hãy TỰ ĐỘNG CHIA NHỎ một cách logic. 
  -> Mỗi ngày / Mỗi hạng mục lớn sẽ là 1 lệnh "create" riêng biệt trong mảng.
  -> Gom các chi tiết nhỏ của hạng mục đó vào trường "content".
  -> Tự động nội suy và tịnh tiến thời gian "datetime" cho phù hợp với logic (VD: ngày 1, ngày 2...).
- Cập nhật/Xóa: Phải đối chiếu với [DỮ LIỆU HIỆN CÓ] để lấy chính xác "target_id".

CẤU TRÚC ĐỐI TƯỢNG TRONG "commands":
- "action": "create", "update", hoặc "delete".
- "target_id": Số nguyên ID (nếu update/delete) hoặc null (nếu create).
- "has_appointment": true (nếu cần đổ chuông báo thức đúng giờ), false (nếu chỉ lưu dạng ghi chú thông thường).
- "title": Tiêu đề súc tích (dưới 10 chữ).
- "content": Nội dung chi tiết (nếu có).
- "datetime": Định dạng "YYYY-MM-DDTHH:MM:00" (hoặc null nếu không có thời gian cụ thể).
- "volume": 1 (nếu có báo thức) hoặc 0.

ĐỊNH DẠNG JSON BẮT BUỘC:
{
  "type": "command hoặc conversation",
  "message": "Câu phản hồi giao tiếp tự nhiên bằng tiếng Việt để báo cáo kết quả cho người dùng.",
  "commands": [
    {
      "action": "create | update | delete",
      "target_id": 123 | null,
      "has_appointment": true | false,
      "title": "Tiêu đề",
      "content": "Nội dung",
      "datetime": "2026-03-12T08:00:00 | null",
      "volume": 0 | 1
    }
  ]
}

Câu của người dùng:
"$userText"
''';

    final requestBody = jsonEncode({
      "contents": [
        {
          "parts": [
            {"text": prompt},
          ],
        },
      ],
      "generationConfig": {"responseMimeType": "application/json"},
    });

    try {
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: requestBody,
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        String textResponse =
            data['candidates'][0]['content']['parts'][0]['text'];

        // --- ĐOẠN MỚI THÊM: Xóa bỏ các ký tự markdown thừa ---
        textResponse = textResponse
            .replaceAll('```json', '')
            .replaceAll('```', '')
            .trim();

        return jsonDecode(textResponse);
      } else {
        debugPrint('Lỗi HTTP: ${response.statusCode} - ${response.body}');
      }
    } catch (e) {
      debugPrint('Lỗi khi phân tích JSON từ AI: $e');
    }
    return null;
  }
}
