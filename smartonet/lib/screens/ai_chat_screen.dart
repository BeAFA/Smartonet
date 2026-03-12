import 'package:flutter/material.dart';
import '../services/gemini_http_service.dart';
import '../services/ai_action_executor.dart';
import '../dialogs/voice_dialogs.dart';
import '../services/dbconnector.dart';
import '../database/models.dart';
import '../screens/voice_chat_screen.dart';

class ChatMessage {
  final String text;
  final bool isUser;
  ChatMessage({required this.text, required this.isUser});
}

class AiChatScreen extends StatefulWidget {
  const AiChatScreen({super.key});

  @override
  State<AiChatScreen> createState() => _AiChatScreenState();
}

class _AiChatScreenState extends State<AiChatScreen> {
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final List<ChatMessage> _messages = [];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _addMessage(
      "Xin chào! Tôi là trợ lý AI của bạn. Hãy nhập câu hỏi hoặc yêu cầu của bạn nhé!",
      false,
    );
  }

  void _addMessage(String text, bool isUser) {
    if (!context.mounted) return;
    setState(() {
      _messages.add(ChatMessage(text: text, isUser: isUser));
    });
    _scrollToBottom();
  }

  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _handleSubmitted(String text) async {
    if (text.trim().isEmpty) return;

    final userInput = text.trim();
    _textController.clear();
    _addMessage(userInput, true);

    setState(() {
      _isLoading = true;
    });

    String getWaitingMessage() {
      final messages = [
        "Đợi mình kiểm tra lại chút nhé...",
        "Hình như có chút nhầm lẫn, để mình xem lại danh sách...",
        "Để mình rà soát lại dữ liệu một tí...",
        "Đang đối chiếu lại yêu cầu của bạn...",
      ];
      return (messages..shuffle()).first;
    }

    try {
      List<Note> allData = await DbConnector.instance.getAllNotes();

      // VÒNG 1: Phân tích lần đầu
      final responseMap = await GeminiHttpService.analyzeIntent(
        userInput,
        currentData: allData,
      );

      if (responseMap != null) {
        final String type = responseMap['type'] ?? 'conversation';
        final String aiMessage = responseMap['message'] ?? 'Tôi đã hiểu.';

        if (type == 'command' && mounted) {
          AiExecutionResult result = await AiActionExecutor.execute(
            responseMap,
            context: context,
          );

          if (!result.hasError) {
            // Lệnh thực thi thành công hoàn toàn
            _addMessage(aiMessage, false);
          } else {
            // VÒNG 2: Kích hoạt AI Agent tự sửa lỗi
            _addMessage(getWaitingMessage(), false);

            final correctionMap = await GeminiHttpService.agentSelfCorrection(
              userText: userInput,
              executionResult: result,
              currentData: allData,
            );

            // Xóa câu thông báo chờ ("Đang kiểm tra lại dữ liệu...")
            if (mounted) {
              setState(() {
                _messages.removeLast();
              });
            }

            if (correctionMap != null) {
              String newType = correctionMap['type'] ?? 'conversation';
              String newAiMessage =
                  correctionMap['message'] ?? 'Xin lỗi, đã có sự cố.';

              if (newType == 'command' && mounted) {
                // AI đã tự sửa lệnh, thử chạy lại
                AiExecutionResult retryResult = await AiActionExecutor.execute(
                  correctionMap,
                  context: context,
                );
                if (!retryResult.hasError) {
                  _addMessage(newAiMessage, false);
                } else {
                  _addMessage(
                    "Mình đã thử sửa nhưng hệ thống vẫn báo lỗi. Bạn có thể kiểm tra lại yêu cầu không?",
                    false,
                  );
                }
              } else {
                // AI không thể sửa, xuất câu xin lỗi tự nhiên
                _addMessage(newAiMessage, false);
              }
            } else {
              _addMessage(
                "Đã xảy ra lỗi khi phân tích dữ liệu, vui lòng thử lại sau.",
                false,
              );
            }
          }
        } else {
          // Trò chuyện thông thường
          _addMessage(aiMessage, false);
        }
      } else {
        // Trường hợp responseMap = null thường do chưa có API Key
        _addMessage(
          "Không thể kết nối máy chủ AI. Bạn đã nhập API Key chưa?",
          false,
        );
      }
    } catch (e) {
      _addMessage("Đã có lỗi hệ thống: $e", false);
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _handleVoiceInput() async {
    final result = await showDialog<String>(
      context: context,
      builder: (context) => const VoiceRecordDialog(),
    );

    if (result != null && result.trim().isNotEmpty) {
      await _handleSubmitted(result);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Trợ lý thông minh',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.all(16.0),
              itemCount: _messages.length,
              itemBuilder: (context, index) {
                final msg = _messages[index];
                return _buildMessageBubble(msg);
              },
            ),
          ),
          if (_isLoading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8.0),
              child: CircularProgressIndicator(),
            ),
          _buildDirectChatButton(),
          _buildInputArea(),
        ],
      ),
    );
  }

  Widget _buildMessageBubble(ChatMessage message) {
    return Align(
      alignment: message.isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 6.0),
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.75,
        ),
        decoration: BoxDecoration(
          color: message.isUser ? Colors.blueAccent : Colors.white,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(message.isUser ? 16 : 4),
            bottomRight: Radius.circular(message.isUser ? 4 : 16),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Text(
          message.text,
          style: TextStyle(
            fontSize: 15.0,
            color: message.isUser ? Colors.white : Colors.black87,
            height: 1.4,
          ),
        ),
      ),
    );
  }

  Widget _buildDirectChatButton() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            // Điều hướng sang màn hình đối thoại trực tiếp
            Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const VoiceChatScreen()),
            );
          },
          borderRadius: BorderRadius.circular(30),
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: 24.0,
              vertical: 12.0,
            ),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF4FACFE), Color(0xFF00F2FE)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(30),
              boxShadow: [
                BoxShadow(
                  color: Colors.blue.withValues(alpha: 0.3),
                  blurRadius: 8,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.record_voice_over, color: Colors.white, size: 20),
                SizedBox(width: 8),
                Text(
                  "Đối thoại",
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildInputArea() {
    return SafeArea(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
        decoration: BoxDecoration(
          color: Theme.of(context).scaffoldBackgroundColor,
          boxShadow: [
            BoxShadow(
              offset: const Offset(0, -2),
              blurRadius: 4,
              color: Colors.black.withValues(alpha: 0.05),
            ),
          ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 4.0),
              child: IconButton(
                icon: const Icon(Icons.mic, color: Colors.blueAccent, size: 28),
                onPressed: _handleVoiceInput,
              ),
            ),
            Expanded(
              child: Container(
                constraints: const BoxConstraints(maxHeight: 120),
                decoration: BoxDecoration(
                  color: Colors.grey[200],
                  borderRadius: BorderRadius.circular(20.0),
                ),
                child: TextField(
                  controller: _textController,
                  minLines: 1,
                  maxLines: 5,
                  keyboardType: TextInputType.multiline,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (value) => _handleSubmitted(value),
                  decoration: const InputDecoration(
                    hintText: 'Nhập tin nhắn...',
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 16.0,
                      vertical: 12.0,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Padding(
              padding: const EdgeInsets.only(bottom: 4.0),
              child: CircleAvatar(
                backgroundColor: Colors.blueAccent,
                radius: 22,
                child: IconButton(
                  icon: const Icon(Icons.send, color: Colors.white, size: 20),
                  onPressed: () => _handleSubmitted(_textController.text),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
