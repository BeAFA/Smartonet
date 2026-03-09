import 'package:flutter/material.dart';

class FaqScreen extends StatefulWidget {
  const FaqScreen({super.key});

  @override
  State<FaqScreen> createState() => _FaqScreenState();
}

class _FaqScreenState extends State<FaqScreen> {
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _searchController = TextEditingController();
  bool _isSidebarOpen = false;

  final Map<String, String> _faqData = {
    "notification":
        "Không nhận được thông báo:\n\n"
        "Nguyên nhân:\n"
        "- Chưa cấp quyền thông báo\n"
        "- Hệ thống chặn thông báo\n\n"
        "Cách khắc phục:\n"
        "1. Vào phần thiết lập quyền trong app\n"
        "2. Bật quyền thông báo",

    "alarm":
        "Báo thức không kêu:\n\n"
        "Nguyên nhân:\n"
        "- Chưa cấp quyền báo thức chính xác\n"
        "- Chế độ tiết kiệm pin chặn app\n\n"
        "Cách khắc phục:\n"
        "1. Bật quyền Exact Alarm\n"
        "2. Tắt tối ưu pin",

    "background":
        "Ứng dụng bị tắt khi chạy nền:\n\n"
        "Thường xảy ra trên Xiaomi, Oppo, Vivo.\n\n"
        "Cách khắc phục:\n"
        "- Cho phép tự khởi chạy\n"
        "- Cho phép chạy nền\n"
        "- Tắt tiết kiệm pin",
  };

  @override
  void dispose() {
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  String _searchText = "";

  @override
  Widget build(BuildContext context) {
    final filteredKeys = _faqData.keys.where((key) {
      final text = _faqData[key]!.toLowerCase();
      return text.contains(_searchText.toLowerCase());
    }).toList();

    return Scaffold(
      appBar: AppBar(title: const Text("Các lỗi thường gặp")),
      body: Column(
        children: [
          /// SEARCH BAR
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.menu),
                  onPressed: () {
                    setState(() {
                      _isSidebarOpen = !_isSidebarOpen;
                    });
                  },
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      hintText: "Tìm kiếm lỗi...",
                      prefixIcon: const Icon(Icons.search),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onChanged: (value) {
                      setState(() {
                        _searchText = value;
                      });
                    },
                  ),
                ),
              ],
            ),
          ),

          /// SIDEBAR DROPDOWN
          AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            height: _isSidebarOpen ? 200 : 0,
            width: double.infinity,
            color: Colors.grey.shade100,
            child: ListView(
              children: filteredKeys.map((key) {
                return ListTile(
                  title: Text(_titleFromKey(key)),
                  onTap: () {
                    final index = filteredKeys.indexOf(key);

                    _scrollController.animateTo(
                      index * 300,
                      duration: const Duration(milliseconds: 400),
                      curve: Curves.ease,
                    );

                    setState(() {
                      _isSidebarOpen = false;
                    });
                  },
                );
              }).toList(),
            ),
          ),

          /// CONTENT
          Expanded(
            child: ListView(
              controller: _scrollController,
              padding: const EdgeInsets.all(20),
              children: filteredKeys.map((key) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 40),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _titleFromKey(key),
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(_faqData[key]!, style: const TextStyle(height: 1.5)),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  String _titleFromKey(String key) {
    switch (key) {
      case "notification":
        return "Không nhận được thông báo";
      case "alarm":
        return "Báo thức không kêu";
      case "background":
        return "Ứng dụng bị tắt khi chạy nền";
      default:
        return key;
    }
  }
}
