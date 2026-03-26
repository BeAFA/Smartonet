import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import '../database/models.dart';
import 'api_key_service.dart';
import 'ai_action_executor.dart';

class GeminiHttpService {
  static Future<Map<String, dynamic>?> analyzeIntent(
    String userText, {
    List<Note>? currentData,
    String? chatHistory,
  }) async {
    // Tự động lấy API Key từ storage
    String apiKey = '';

    final url = Uri.parse(
      'https://generativelanguage.googleapis.com/v1beta/models/gemini-3.1-flash-lite-preview:generateContent?key=$apiKey',
    );

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
Bạn là AI trợ lý ảo thông minh cho Smartonet.
Thời gian hiện tại: ${DateTime.now().toIso8601String()}.

LỊCH SỬ TRÒ CHUYỆN GẦN ĐÂY:
${chatHistory ?? "Không có"}

DỮ LIỆU HIỆN CÓ:
$contextData

NHIỆM VỤ:
1. Nếu sửa được lệnh: Trả về JSON "command" kèm câu thông báo thành công.
2. Nếu không sửa được: Trả về JSON "conversation". 

QUY TẮC NÓI CHUYỆN KHI LỖI:
- Không dùng từ ngữ kỹ thuật như "ID", "database", "null", "target_id".
- Hãy trả lời tự nhiên như 1 người trợ lý.

QUY TẮC XỬ LÝ HÀNH ĐỘNG ("commands"):
- Lên kế hoạch/Danh sách: TỰ ĐỘNG CHIA NHỎ thành nhiều lệnh "create".
- Cập nhật/Xóa lịch: Đối chiếu [DỮ LIỆU HIỆN CÓ] lấy "target_id".
- Xóa nhạc: Lệnh "delete_audio", xóa bài cụ thể -> "keyword": tên bài, xóa tất cả -> "keyword": "all".
- Nghe/Phát nhạc: Dùng lệnh "preview_audio". BẮT BUỘC tuân thủ:
  + "keyword": Tên bài hát. Nếu muốn nghe "tất cả" hoặc không nói rõ tên, để "all".
  + "audio_type": "custom" (nhạc tải lên), "default" (nhạc hệ thống), hoặc "both" (không nói rõ).
  + "play_count": Số lượng bài muốn nghe. Nghe "tất cả" -> -1. Không nói rõ -> 1.
  + "duration_in_seconds": NẾU người dùng nói "nghe thử" chung chung -> 10. NẾU người dùng nói số giây cụ thể -> số đó. NẾU yêu cầu "phát", "nghe toàn bộ" -> null.

CẤU TRÚC ĐỐI TƯỢNG TRONG "commands":
- "action": "create" | "update" | "delete" | "preview_audio" | "stop_preview" | "delete_audio"
- "target_id": Số nguyên ID hoặc null.
- "has_appointment": true | false.
- "title": Tiêu đề (dưới 10 chữ).
- "content": Nội dung chi tiết.
- "datetime": Định dạng "YYYY-MM-DDTHH:MM:00" hoặc null.
- "volume": 1.0 hoặc 0.0.
- "keyword": "tên bài hát | all | null"
- "audio_type": "custom | default | both"
- "play_count": 1 | 3 | -1 | null
- "duration_in_seconds": 10 | 5 | null

QUY TẮC XỬ LÝ TRÙNG LẶP & MƠ HỒ:
1. Nếu người dùng muốn xóa/sửa nhưng có nhiều kết quả trùng tên:
   - Trả về type: "conversation".
   - Trong "message", hãy liệt kê các mục đó (ví dụ theo thời gian hoặc nội dung) và hỏi người dùng chọn cái nào.
2. Nếu dựa vào LỊCH SỬ, bạn biết người dùng đang trả lời câu hỏi trước đó (VD: "Cái thứ hai", "Lịch lúc 8h"):
   - Hãy tìm đúng target_id của mục đó và trả về type: "command".
3. Tuyệt đối không tự ý chọn ID nếu không chắc chắn.

ĐỊNH DẠNG JSON BẮT BUỘC:
{
  "type": "command | conversation",
  "message": "...",
  "commands": [...]
}

Câu của người dùng: "$userText"
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
        textResponse = textResponse
            .replaceAll('```json', '')
            .replaceAll('```', '')
            .trim();
        return jsonDecode(textResponse);
      }
    } catch (e) {
      debugPrint('Lỗi khi phân tích JSON từ AI: $e');
    }
    return null;
  }

  // HÀM MỚI: AI Agent tự đánh giá lỗi và sửa sai
  static Future<Map<String, dynamic>?> agentSelfCorrection({
    required String userText,
    required AiExecutionResult executionResult,
    required List<Note> currentData,
  }) async {
    String apiKey =
        await ApiKeyService.getApiKey() ??
        '';
    if (apiKey.isEmpty) return null;

    final url = Uri.parse(
      'https://generativelanguage.googleapis.com/v1beta/models/gemini-3.1-flash-lite-preview:generateContent?key=$apiKey',
    );

    String errorReport = executionResult.failures
        .map((f) {
          return "- Lệnh: ${jsonEncode(f.command)}\n  Lỗi: ${f.errorMessage}";
        })
        .join('\n');

    String contextData = currentData
        .map((n) {
          String type = n.hasAppointment ? "Lịch hẹn" : "Ghi chú";
          return "[$type] ID: ${n.id} | Tiêu đề: '${n.title}' | Nội dung: '${n.content}'";
        })
        .join('\n');

    final prompt =
        '''
Bạn là AI trợ lý ảo thông minh. Bạn vừa cố gắng thực hiện yêu cầu: "$userText"
Tuy nhiên, thao tác của bạn đã GẶP LỖI HỆ THỐNG.

DANH SÁCH LỖI:
$errorReport

DỮ LIỆU HIỆN CÓ (Cập nhật mới nhất):
$contextData

NHIỆM VỤ:
1. Phân tích nguyên nhân lỗi. (Ví dụ: truyền sai target_id so với dữ liệu hiện có).
2. NẾU BẠN CÓ THỂ SỬA SAI (VD: tìm ra ID đúng từ Dữ liệu hiện có), hãy trả về JSON với type: "command" và mảng "commands" chứa CÁC LỆNH ĐÃ SỬA ĐÚNG. Đừng quên kèm "message" thông báo thành công.
3. NẾU KHÔNG THỂ SỬA (VD: người dùng yêu cầu thao tác trên mục không tồn tại), trả về JSON với type: "conversation", và "message" giải thích ngắn gọn, tự nhiên bằng tiếng Việt cho người dùng hiểu. Không trả về "commands".

ĐỊNH DẠNG JSON BẮT BUỘC (Không dùng markdown):
{
  "type": "command hoặc conversation",
  "message": "Câu phản hồi tự nhiên cho người dùng...",
  "commands": []
}
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
        textResponse = textResponse
            .replaceAll('```json', '')
            .replaceAll('```', '')
            .trim();
        return jsonDecode(textResponse);
      }
    } catch (e) {
      debugPrint('Lỗi Agent Self Correction: $e');
    }
    return null;
  }
}
