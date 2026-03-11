import 'package:flutter/material.dart';
import '../services/gemini_http_service.dart';
import '../services/ai_action_executor.dart';
import '../dialogs/voice_dialogs.dart';
import '../services/dbconnector.dart';
import '../database/models.dart';


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
    _addMessage("Xin chào! Tôi là trợ lý AI của bạn. Hãy nhập câu hỏi hoặc yêu cầu của bạn nhé!", false);
  }

  void _addMessage(String text, bool isUser) {
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

    try {
      // BƯỚC MỚI: Lấy danh sách ghi chú/lịch hẹn hiện tại từ DB
      List<Note> allData = await DbConnector.instance.getAllNotes();

      // Truyền allData vào cho Gemini
      final responseMap = await GeminiHttpService.analyzeIntent(
        userInput,
        currentData: allData,
      );

      if (responseMap != null) {
        final String type = responseMap['type'] ?? 'conversation';
        final String aiMessage = responseMap['message'] ?? 'Tôi đã hiểu.';

        if (type == 'command') {
          bool isSuccess = await AiActionExecutor.execute(responseMap);
          if (isSuccess) {
            _addMessage(aiMessage, false);
          } else {
            _addMessage("Xin lỗi, tôi không thể tìm thấy mục bạn yêu cầu hoặc có lỗi xảy ra.", false);
          }
        } else {
          _addMessage(aiMessage, false);
        }
      } else {
        _addMessage("Xin lỗi, tôi không thể kết nối đến máy chủ AI lúc này.", false);
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
            )
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
          onTap: _handleVoiceInput,
          borderRadius: BorderRadius.circular(30),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 12.0),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF4FACFE), Color(0xFF00F2FE)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(30),
              boxShadow: [
                BoxShadow(
                  color: Colors.blue.withValues(alpha:0.3),
                  blurRadius: 8,
                  offset: const Offset(0, 4),
                )
              ],
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.record_voice_over, color: Colors.white, size: 20),
                SizedBox(width: 8),
                Text(
                  "Trò chuyện trực tiếp",
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
            )
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
                constraints: const BoxConstraints(
                  maxHeight: 120,
                ),
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
                  onSubmitted: (value) {
                    _handleSubmitted(value);
                  },
                  decoration: const InputDecoration(
                    hintText: 'Nhập tin nhắn...',
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
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