import 'dart:io';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:shelf_web_socket/shelf_web_socket.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/io.dart';

const String geminiApiKey = '';
const String geminiWsUrl =
    'wss://generativelanguage.googleapis.com/ws/google.ai.generativelanguage.v1alpha.GenerativeService.BidiGenerateContent?key=$geminiApiKey';
final _router = Router()
  ..get(
    '/',
    (Request req) => Response.ok('Trạm trung chuyển Smartonet đã sẵn sàng!\n'),
  )
  ..get('/ws', (Request request) => _webSocketHandler(request));

// THÊM TỪ KHÓA async VÀO ĐÂY
final _webSocketHandler = webSocketHandler((
  WebSocketChannel appChannel,
  String? protocol,
) async {
  print('\n📱 [BƯỚC 1] App Flutter vừa kết nối vào Server!');

  print('🌐 [BƯỚC 2] Đang kết nối tới máy chủ Google Gemini...');
  final geminiChannel = IOWebSocketChannel.connect(Uri.parse(geminiWsUrl));

  // --- MỚI: KIỂM TRA BẮT TAY BẮT BUỘC ---
  try {
    await geminiChannel.ready;
    print('✅ [BƯỚC 2.1] Đã xác thực API Key và bắt tay thành công với Google!');
  } catch (e) {
    print(
      '❌ [LỖI NGHIÊM TRỌNG] Google từ chối kết nối (Sai API Key hoặc URL)!',
    );
    print('Chi tiết lỗi: $e');
    appChannel.sink.close(); // Đóng luôn kết nối với App
    return; // Dừng luôn, không chạy tiếp
  }

  // LUỒNG A: Nhận từ Gemini -> Bơm về App
  geminiChannel.stream.listen(
    (geminiData) {
      print('🤖 Gemini gửi data về App');
      appChannel.sink.add(geminiData);
    },
    onDone: () {
      print('🛑 Gemini đã ngắt kết nối.');
      // --- MỚI: IN LÝ DO GOOGLE NGẮT KẾT NỐI ---
      print('   -> Mã lỗi (Close Code): ${geminiChannel.closeCode}');
      print('   -> Lý do (Close Reason): ${geminiChannel.closeReason}');
      appChannel.sink.close();
    },
    onError: (err) => print('⚠️ Lỗi kết nối với Gemini: $err'),
  );

  // LUỒNG B: Nhận từ App -> Bơm lên Gemini
  appChannel.stream.listen(
    (appData) {
      // --- MỚI: IN XEM APP ĐANG GỬI CÁI GÌ LÊN ---
      String dataPreview = appData.toString();
      if (dataPreview.length > 150) {
        dataPreview = '${dataPreview.substring(0, 150)}... (đã cắt bớt)';
      }
      print('🎤 App vừa gửi: $dataPreview');

      geminiChannel.sink.add(appData);
    },
    onDone: () {
      print('❌ Thiết bị App đã ngắt kết nối.');
      geminiChannel.sink.close();
    },
    onError: (err) => print('⚠️ Lỗi từ App: $err'),
  );
});

void main(List<String> args) async {
  final ip = InternetAddress.anyIPv4;
  final handler = Pipeline()
      .addMiddleware(logRequests())
      .addHandler(_router.call);

  final port = int.parse(Platform.environment['PORT'] ?? '8080');
  final server = await serve(handler, ip, port);

  print(
    '🚀 Server Smartonet đang chạy tại: ws://${server.address.host}:${server.port}/ws',
  );
}
