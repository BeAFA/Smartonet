import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path/path.dart' hide Context;
import 'package:smartonet/database/dbconnector.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sqflite/sqflite.dart';
import 'database/models.dart';
import 'utils/dao.dart';

void main() {
  // --- CẤU HÌNH CHO WINDOWS/LINUX ---
  if (Platform.isWindows || Platform.isLinux) {
    // Khởi tạo FFI
    sqfliteFfiInit();
    // Gán databaseFactory
    databaseFactory = databaseFactoryFfi;
  }
  // ----------------------------------
  runApp(const Smartonet());
}

class Smartonet extends StatelessWidget {
  const Smartonet({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Smartonet',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF2563EB),
          brightness: Brightness.light,
        ),
        scaffoldBackgroundColor: const Color(0xFFF8FAFC),
      ),
      home: const MainScreen(),
    );
  }
}

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _selectedIndex = 1;
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _contentController = TextEditingController();

  // 1. KHỞI TẠO DAO
  final NoteDao _dao = NoteDao();

  // 2. XÓA MOCK DATA, CHỈ KHAI BÁO LIST RỖNG
  List<Map<String, dynamic>> _reminders = [];
  List<Map<String, dynamic>> _notes = [];

  @override
  void initState() {
    super.initState();
    // 3. GỌI HÀM LOAD DỮ LIỆU KHI MỞ APP
    _loadDataFromDB();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _contentController.dispose();
    super.dispose();
  }

  // --- HÀM LOAD DỮ LIỆU TỪ SQLITE ---
  Future<void> _loadDataFromDB() async {
    // Gọi hàm lấy Notes
    final notesData = await _dao.getNotes();

    // GỌI HÀM MỚI: Lấy Reminder có kèm Title thật từ bảng Note
    final remindersData = await _dao.getRemindersWithDetails();

    setState(() {
      // Cập nhật list Ghi chú
      _notes = notesData.toList();

      // Cập nhật list Nhắc nhở (Cần xử lý data một chút để khớp với UI)
      _reminders = remindersData.map((item) {
        DateTime scheduled = DateTime.parse(item['scheduled_time']);
        return {
          'id': item['id'], // ID của bảng reminder
          'note_id':
              item['note_id'], // QUAN TRỌNG: ID của Note gốc để Join/Update
          'title': item['title'] ?? 'Nhắc nhở #${item['note_id']}',
          // Nên lấy title thật từ bảng Notes thông qua Join query trong DAO
          'content':
              item['content'] ?? '', // Cần lấy content thật từ bảng Notes
          'time':
              '${scheduled.hour}:${scheduled.minute.toString().padLeft(2, '0')}',
          'date': '${scheduled.day}/${scheduled.month}',
          'isUrgent': true,
          'full_date': scheduled, // Lưu object gốc để tiện xử lý logic
        };
      }).toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // --- APP BAR ---
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Smartonet',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.notifications_outlined),
            onPressed: () {},
          ),
          const SizedBox(width: 8),
          const CircleAvatar(
            backgroundColor: Color.fromARGB(255, 68, 138, 255),
            child: Icon(Icons.person, color: Colors.white),
          ),
          const SizedBox(width: 16),
        ],
      ),

      // --- BODY ---
      body: IndexedStack(
        index: _selectedIndex,
        children: [
          _buildAllNotes(), // Trang danh sách ghi chú
          _buildDashboard(), // Trang chủ dashboard
          _buildReminderList(), // Trang danh sách nhắc nhở
        ],
      ),

      // --- FLOATING ACTION BUTTON (Nút thêm mới) ---
      floatingActionButton: Container(
        margin: const EdgeInsets.only(bottom: 50),
        height: 55,
        width: 220,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(30), // Bo tròn dạng viên thuốc
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.2),
              spreadRadius: 1,
              blurRadius: 6,
              offset: const Offset(0, 3), // Tạo bóng đổ nhẹ để nút nổi lên
            ),
          ],
        ),
        child: Material(
          color: const Color(0xFFE8EAF6), // Chuyển màu nền vào Material
          borderRadius: BorderRadius.circular(30), // Bo góc cho Material
          clipBehavior:
              Clip.hardEdge, // Cắt bỏ phần hiệu ứng loang ra ngoài góc bo
          child: Row(
            children: [
              // --- Nút bên trái: Thủ công ---
              Expanded(
                child: InkWell(
                  borderRadius: const BorderRadius.horizontal(
                    left: Radius.circular(30),
                  ),
                  hoverColor: const Color(0xFF3F51B5).withOpacity(0.1),
                  splashColor: const Color(0xFF3F51B5).withOpacity(0.2),

                  onTap: () {
                    // Gọi hàm mở form thủ công của bạn
                    _openNoteForm(context);
                  },
                  child: Container(
                    height:
                        55, // Bắt buộc set chiều cao để vùng hover phủ kín nút
                    alignment: Alignment.center,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: const [
                        Icon(
                          Icons.edit,
                          color: Color(0xFF3F51B5),
                          size: 20,
                        ), // Màu Indigo đậm
                        SizedBox(width: 8),
                        Text(
                          "Thủ công",
                          style: TextStyle(
                            color: Color(0xFF3F51B5),
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              // --- Đường kẻ dọc ngăn cách ---
              Container(
                width: 1,
                height: 30,
                color: Colors.grey.withOpacity(0.4),
              ),

              // --- Nút bên phải: Giọng nói ---
              Expanded(
                child: InkWell(
                  hoverColor: const Color(0xFF3F51B5).withOpacity(0.1),
                  splashColor: const Color(0xFF3F51B5).withOpacity(0.2),
                  borderRadius: const BorderRadius.horizontal(
                    right: Radius.circular(30),
                  ),
                  onTap: () {
                    // TODO: Viết logic xử lý ghi âm tại đây
                    print("Đã chọn giọng nói");
                  },
                  child: Container(
                    height:
                        55, // Bắt buộc set chiều cao để vùng hover phủ kín nút
                    alignment: Alignment.center,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: const [
                        Icon(Icons.mic, color: Colors.redAccent, size: 20),
                        SizedBox(width: 8),
                        Text(
                          "Giọng nói",
                          style: TextStyle(
                            color: Colors.redAccent,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,

      // --- BOTTOM NAVIGATION ---
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (int index) {
          setState(() {
            _selectedIndex = index;
          });
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.sticky_note_2_outlined),
            selectedIcon: Icon(Icons.sticky_note_2),
            label: 'Ghi chú',
          ),
          NavigationDestination(
            icon: Icon(Icons.dashboard_outlined),
            selectedIcon: Icon(Icons.dashboard),
            label: 'Tổng quan',
          ),
          NavigationDestination(
            icon: Icon(Icons.calendar_month_outlined),
            selectedIcon: Icon(Icons.calendar_month),
            label: 'Lịch nhắc',
          ),
        ],
      ),
    );
  }

  // --- WIDGET: TRANG DASHBOARD ---
  Widget _buildDashboard() {
    final displayReminders = _reminders.take(4).toList();
    final displayNotes = _notes.take(4).toList();
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionHeader(
            title: 'Lịch nhắc sắp tới',
            onTap: () {
              setState(() {
                _selectedIndex = 2;
              });
            },
          ),
          const SizedBox(height: 10),
          _reminders.isEmpty
              ? _buildEmptyState(
                  "Không có lịch nhắc nào sắp tới",
                  Icons.notifications_off_outlined,
                )
              : ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: displayReminders.length,
                  itemBuilder: (context, index) {
                    final item = displayReminders[index];
                    return ReminderCard(
                      title: item['title'],
                      time: item['time'],
                      date: item['date'],
                      isUrgent: item['isUrgent'],
                      onEdit: () {
                        _showEditReminderDialog(context, item);
                      },
                    );
                  },
                ),
          const SizedBox(height: 25),
          SectionHeader(
            title: 'Ghi chú gần đây',
            onTap: () {
              setState(() {
                _selectedIndex = 0;
              });
            },
          ),

          const SizedBox(height: 10),
          _notes.isEmpty
              ? _buildEmptyState("Chưa có ghi chú nào", Icons.note_add_outlined)
              : GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    crossAxisSpacing: 10,
                    mainAxisSpacing: 10,
                    childAspectRatio: 1.1,
                  ),
                  itemCount: displayNotes.length,
                  itemBuilder: (context, index) {
                    final note = displayNotes[index];
                    return NoteCard(
                      title: note['title'],
                      content: note['content'],
                      tag: note['tag'] ?? 'General',
                      hasReminder: note['remind'] == 1,
                      onEdit: () {
                        _openNoteForm(context, existingNote: note);
                      },
                      onDelete: () {
                        _deleteNote(context, note['id']);
                      },
                    );
                  },
                ),
        ],
      ),
    );
  }

  // --- WIDGET: TRANG TẤT CẢ GHI CHÚ ---
  Widget _buildAllNotes() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // --- 1. PHẦN TIÊU ĐỀ (LUÔN HIỂN THỊ) ---
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 20, 16, 10),
          child: Text(
            "Tất cả Ghi chú",
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
        ),

        // --- 2. PHẦN NỘI DUNG (Thay đổi tùy theo dữ liệu) ---
        Expanded(
          // Kiểm tra: Nếu rỗng thì hiện EmptyState, ngược lại hiện ListView
          child: _notes.isEmpty
              ? _buildEmptyState("Chưa có ghi chú nào", Icons.note_add_outlined)
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _notes.length,
                  itemBuilder: (context, index) {
                    final note = _notes[index];
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: NoteCard(
                        title: note['title'],
                        content: note['content'],
                        tag: note['tag'],
                        isFullWidth: true,
                        hasReminder: note['remind'] == 1,
                        onEdit: () {
                          _openNoteForm(context, existingNote: note);
                        },
                        onDelete: () {
                          _deleteNote(context, note['id']);
                        },
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildReminderList() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // --- 1. PHẦN TIÊU ĐỀ (LUÔN HIỂN THỊ) ---
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 20, 16, 10),
          child: Text(
            "Tất cả Lịch hẹn",
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
        ),

        // --- 2. PHẦN NỘI DUNG (Thay đổi tùy theo dữ liệu) ---
        Expanded(
          // Kiểm tra: Nếu rỗng thì hiện EmptyState, ngược lại hiện ListView
          child: _reminders.isEmpty
              ? _buildEmptyState(
                  "Không có lịch nhắc nào sắp tới",
                  Icons.notifications_off_outlined,
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16.0),
                  // Thêm padding dưới cùng để không bị nút Tạo Mới che mất item cuối
                  // padding: const EdgeInsets.only(left: 16, right: 16, top: 16, bottom: 80),
                  itemCount: _reminders.length,
                  itemBuilder: (context, index) {
                    final item = _reminders[index];
                    return Padding(
                      padding: const EdgeInsets.only(
                        bottom: 10.0,
                      ), // Khoảng cách giữa các card
                      child: ReminderCard(
                        title: item['title'],
                        time: item['time'],
                        date: item['date'],
                        isUrgent: item['isUrgent'],
                        onEdit: () {
                          _showEditReminderDialog(context, item);
                        },
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  // // --- HÀM: HIỆN FORM THÊM MỚI ---
  // void _showAddModal(BuildContext context) {
  //   // Ở đầu hàm _showAddModal
  //   List<Map<String, dynamic>> _notes = [];
  //   final TextEditingController _titleController = TextEditingController();
  //   final TextEditingController _contentController = TextEditingController();
  //   final TextEditingController _tagController = TextEditingController();
  //   DateTime? _selectedDate;
  //   TimeOfDay? _selectedTime;

  //   showModalBottomSheet(
  //     context: context,
  //     isScrollControlled: true,
  //     shape: const RoundedRectangleBorder(
  //       borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
  //     ),
  //     builder: (context) {
  //       return SizedBox(
  //         height: MediaQuery.of(context).size.height * 0.50,
  //         child: StatefulBuilder(
  //           builder: (BuildContext context, StateSetter setModalState) {
  //             return Padding(
  //               padding: EdgeInsets.only(
  //                 bottom: MediaQuery.of(context).viewInsets.bottom,
  //                 top: 20,
  //                 left: 20,
  //                 right: 20,
  //               ),
  //               child: Column(
  //                 mainAxisSize: MainAxisSize.min,
  //                 crossAxisAlignment: CrossAxisAlignment.stretch,
  //                 children: [
  //                   const Text(
  //                     'Tạo ghi chú / Nhắc nhở',
  //                     style: TextStyle(
  //                       fontSize: 20,
  //                       fontWeight: FontWeight.bold,
  //                     ),
  //                   ),
  //                   const SizedBox(height: 15),
  //                   TextField(
  //                     controller: _titleController,
  //                     decoration: InputDecoration(
  //                       labelText: 'Tiêu đề',
  //                       border: OutlineInputBorder(
  //                         borderRadius: BorderRadius.circular(12),
  //                       ),
  //                       prefixIcon: const Icon(Icons.title),
  //                     ),
  //                   ),
  //                   const SizedBox(height: 15),
  //                   Expanded(
  //                     child: TextField(
  //                       controller: _contentController,
  //                       maxLines: null, // Cho phép xuống dòng vô hạn
  //                       expands:
  //                           true, // Quan trọng: Bắt nội dung dãn kín khung Expanded
  //                       textAlignVertical:
  //                           TextAlignVertical.top, // Gõ chữ từ trên cùng
  //                       decoration: InputDecoration(
  //                         labelText: 'Nội dung chi tiết',
  //                         border: OutlineInputBorder(
  //                           borderRadius: BorderRadius.circular(12),
  //                         ),
  //                         alignLabelWithHint: true,
  //                       ),
  //                     ),
  //                   ),
  //                   const SizedBox(height: 15),
  //                   Row(
  //                     children: [
  //                       // NÚT CHỌN NGÀY
  //                       Expanded(
  //                         child: OutlinedButton.icon(
  //                           onPressed: () async {
  //                             final DateTime? picked = await showDatePicker(
  //                               context: context,
  //                               initialDate: DateTime.now(),
  //                               firstDate: DateTime.now(),
  //                               lastDate: DateTime(2100),
  //                             );
  //                             if (picked != null) {
  //                               // Dùng setModalState để cập nhật text nút bấm
  //                               setModalState(() {
  //                                 _selectedDate = picked;
  //                               });
  //                             }
  //                           },
  //                           icon: const Icon(Icons.calendar_today),
  //                           // Logic hiển thị: Nếu chưa chọn thì hiện "Chọn ngày", chọn rồi thì hiện ngày tháng
  //                           label: Text(
  //                             _selectedDate == null
  //                                 ? 'Chọn ngày'
  //                                 : '${_selectedDate!.day}/${_selectedDate!.month}/${_selectedDate!.year}',
  //                             style: TextStyle(
  //                               color: _selectedDate != null
  //                                   ? Colors.black
  //                                   : null,
  //                               fontWeight: _selectedDate != null
  //                                   ? FontWeight.bold
  //                                   : null,
  //                             ),
  //                           ),
  //                         ),
  //                       ),
  //                       const SizedBox(width: 10),
  //                       // NÚT CHỌN GIỜ
  //                       Expanded(
  //                         child: OutlinedButton.icon(
  //                           onPressed: () async {
  //                             final TimeOfDay? picked = await showTimePicker(
  //                               context: context,
  //                               initialTime: TimeOfDay.now(),
  //                             );
  //                             if (picked != null) {
  //                               setModalState(() {
  //                                 _selectedTime = picked;
  //                               });
  //                             }
  //                           },
  //                           icon: const Icon(Icons.access_time),
  //                           // Logic hiển thị giờ phút (thêm số 0 đằng trước nếu nhỏ hơn 10)
  //                           label: Text(
  //                             _selectedTime == null
  //                                 ? 'Chọn giờ'
  //                                 : '${_selectedTime!.hour.toString().padLeft(2, '0')}:${_selectedTime!.minute.toString().padLeft(2, '0')}',
  //                             style: TextStyle(
  //                               color: _selectedTime != null
  //                                   ? Colors.black
  //                                   : null,
  //                               fontWeight: _selectedTime != null
  //                                   ? FontWeight.bold
  //                                   : null,
  //                             ),
  //                           ),
  //                         ),
  //                       ),
  //                     ],
  //                   ),
  //                   const SizedBox(height: 15),
  //                   SizedBox(
  //                     width: double.infinity,
  //                     height: 50,
  //                     child: FilledButton(
  //                       onPressed: () async {
  //                         if (_titleController.text.trim().isEmpty) return;

  //                         // 1. Chuẩn bị dữ liệu
  //                         bool isRemind = false;
  //                         DateTime? finalScheduledTime;

  //                         if (_selectedDate != null && _selectedTime != null) {
  //                           isRemind = true;
  //                           finalScheduledTime = DateTime(
  //                             _selectedDate!.year,
  //                             _selectedDate!.month,
  //                             _selectedDate!.day,
  //                             _selectedTime!.hour,
  //                             _selectedTime!.minute,
  //                           );
  //                         }

  //                         // 2. Tạo đối tượng Note (Import từ models.dart)
  //                         Note newNote = Note(
  //                           title: _titleController.text,
  //                           content: _contentController.text,
  //                           remind: isRemind,
  //                           tag: _tagController.text.isEmpty
  //                               ? 'General'
  //                               : _tagController.text,
  //                         );

  //                         // 3. GỌI DAO ĐỂ LƯU VÀO SQLITE
  //                         await _dao.createNote(
  //                           newNote,
  //                           scheduledTime: finalScheduledTime,
  //                         );

  //                         // 4. Load lại dữ liệu để UI cập nhật
  //                         await _loadDataFromDB();

  //                         // 5. Đóng Modal
  //                         if (!context.mounted) return;
  //                         Navigator.pop(context);
  //                       },
  //                       child: const Text('Lưu'),
  //                     ),
  //                   ),
  //                   const SizedBox(height: 15),
  //                 ],
  //               ),
  //             );
  //           },
  //         ),
  //       );
  //     },
  //   );
  // }

  void _handleDelete(int id) async {
    // id này là id của bảng notes.
    // Nếu item bạn lấy từ list reminders, hãy truyền item['note_id'].
    // Nếu item bạn lấy từ list notes, hãy truyền item['id'].

    await Dbconnector.instance.deleteItem(id);

    // Refresh UI
    _loadDataFromDB();
  }

  // 1. Hàm xóa ghi chú
  Future<void> _deleteNote(BuildContext ctx, int id) async {
    bool confirm =
        await showDialog(
          context: ctx,
          builder: (dctx) => AlertDialog(
            title: const Text("Xác nhận xóa"),
            content: const Text("Bạn có chắc muốn xóa ghi chú này không?"),
            actions: [
              TextButton(
                child: const Text("Hủy"),
                onPressed: () => Navigator.pop(dctx, false),
              ),
              TextButton(
                child: const Text("Xóa", style: TextStyle(color: Colors.red)),
                onPressed: () => Navigator.pop(dctx, true),
              ),
            ],
          ),
        ) ??
        false;

    if (confirm) {
      // Gọi hàm deleteNote từ dbconnector (bạn nhớ cập nhật dbconnector.dart như bài trước nhé)
      _handleDelete(id);
      await _loadDataFromDB(); // Load lại dữ liệu
    }
  }

  void _handleSave({
    int? currentId, // null nếu tạo mới, có số nếu sửa
    required String title,
    required String content,
    String? pickedTime, // Chuỗi giờ "14:30 02/01/2026" hoặc null
  }) async {
    await Dbconnector.instance.saveNoteOrReminder(
      id: currentId,
      title: title,
      content: content,
      scheduledTime:
          pickedTime, // Truyền null nếu user xóa giờ hoặc không chọn giờ
    );

    // Refresh UI
    _loadDataFromDB();
  }

  // 2. Hàm hiện dialog sửa ghi chú (Code bạn vừa gửi)
  // --- HÀM: HIỆN DIALOG SỬA (GIỮA MÀN HÌNH) ---
  // void _showEditDialog(
  //   BuildContext ctx,
  //   Map<String, dynamic> existingNote,
  // ) async {
  //   _titleController.text = existingNote['title'];
  //   _contentController.text = existingNote['content'];

  //   // 1. Kiểm tra xem Note này có đang bật nhắc nhở không
  //   bool isRemind = (existingNote['remind'] == 1);
  //   DateTime? currentScheduledTime;

  //   // 2. Nếu có nhắc nhở, ta cần lấy giờ cụ thể từ DB (vì list notes chưa có thông tin này)
  //   if (isRemind) {
  //     final db = await Dbconnector.instance.database;
  //     final maps = await db.query(
  //       'reminders',
  //       columns: ['scheduled_time'],
  //       where: 'note_id = ?',
  //       whereArgs: [existingNote['id']],
  //     );
  //     if (maps.isNotEmpty) {
  //       currentScheduledTime = DateTime.parse(
  //         maps.first['scheduled_time'] as String,
  //       );
  //     }
  //   }

  //   // Biến tạm để lưu giờ/phút khi user chỉnh sửa trên Dialog
  //   DateTime? tempDate = currentScheduledTime;
  //   TimeOfDay? tempTime = currentScheduledTime != null
  //       ? TimeOfDay.fromDateTime(currentScheduledTime)
  //       : null;

  //   if (!ctx.mounted) return;

  //   showDialog(
  //     context: ctx,
  //     builder: (context) {
  //       // Dùng StatefulBuilder để cập nhật giao diện TRONG Dialog (khi chọn ngày/giờ)
  //       return StatefulBuilder(
  //         builder: (context, setStateDialog) {
  //           return Dialog(
  //             shape: RoundedRectangleBorder(
  //               borderRadius: BorderRadius.circular(16),
  //             ),
  //             child: Container(
  //               padding: const EdgeInsets.all(20),
  //               width:
  //                   MediaQuery.of(context).size.width *
  //                   0.9, // Chiếm 90% chiều rộng
  //               child: SingleChildScrollView(
  //                 child: Column(
  //                   mainAxisSize: MainAxisSize.min,
  //                   crossAxisAlignment: CrossAxisAlignment.start,
  //                   children: [
  //                     const Text(
  //                       "Chỉnh sửa ghi chú",
  //                       style: TextStyle(
  //                         fontSize: 20,
  //                         fontWeight: FontWeight.bold,
  //                       ),
  //                     ),
  //                     const SizedBox(height: 20),

  //                     // --- TIÊU ĐỀ ---
  //                     TextField(
  //                       controller: _titleController,
  //                       decoration: const InputDecoration(
  //                         labelText: 'Tiêu đề',
  //                         border: OutlineInputBorder(),
  //                         contentPadding: EdgeInsets.symmetric(
  //                           horizontal: 12,
  //                           vertical: 12,
  //                         ),
  //                       ),
  //                     ),
  //                     const SizedBox(height: 15),

  //                     // --- NỘI DUNG ---
  //                     TextField(
  //                       controller: _contentController,
  //                       decoration: const InputDecoration(
  //                         labelText: 'Nội dung',
  //                         border: OutlineInputBorder(),
  //                       ),
  //                       maxLines: 5,
  //                       minLines: 2,
  //                     ),
  //                     const SizedBox(height: 15),

  //                     // --- LOGIC HIỂN THỊ NGÀY GIỜ ---
  //                     // Chỉ hiển thị nếu Note gốc có lịch hẹn (isRemind == true)
  //                     if (isRemind) ...[
  //                       Row(
  //                         children: [
  //                           // Nút chọn NGÀY
  //                           Expanded(
  //                             child: OutlinedButton.icon(
  //                               onPressed: () async {
  //                                 final picked = await showDatePicker(
  //                                   context: context,
  //                                   initialDate: tempDate ?? DateTime.now(),
  //                                   firstDate: DateTime.now(),
  //                                   lastDate: DateTime(2100),
  //                                 );
  //                                 if (picked != null) {
  //                                   setStateDialog(() => tempDate = picked);
  //                                 }
  //                               },
  //                               icon: const Icon(
  //                                 Icons.calendar_today,
  //                                 size: 18,
  //                               ),
  //                               label: Text(
  //                                 tempDate == null
  //                                     ? "Ngày"
  //                                     : "${tempDate!.day}/${tempDate!.month}/${tempDate!.year}",
  //                                 style: const TextStyle(fontSize: 13),
  //                               ),
  //                             ),
  //                           ),
  //                           const SizedBox(width: 8),
  //                           // Nút chọn GIỜ
  //                           Expanded(
  //                             child: OutlinedButton.icon(
  //                               onPressed: () async {
  //                                 final picked = await showTimePicker(
  //                                   context: context,
  //                                   initialTime: tempTime ?? TimeOfDay.now(),
  //                                 );
  //                                 if (picked != null) {
  //                                   setStateDialog(() => tempTime = picked);
  //                                 }
  //                               },
  //                               icon: const Icon(Icons.access_time, size: 18),
  //                               label: Text(
  //                                 tempTime == null
  //                                     ? "Giờ"
  //                                     : "${tempTime!.hour}:${tempTime!.minute.toString().padLeft(2, '0')}",
  //                                 style: const TextStyle(fontSize: 13),
  //                               ),
  //                             ),
  //                           ),
  //                         ],
  //                       ),
  //                       const SizedBox(height: 20),
  //                     ],

  //                     // --- CÁC NÚT ACTION ---
  //                     Row(
  //                       mainAxisAlignment: MainAxisAlignment.end,
  //                       children: [
  //                         TextButton(
  //                           onPressed: () => Navigator.pop(context),
  //                           child: const Text(
  //                             "Hủy",
  //                             style: TextStyle(color: Colors.grey),
  //                           ),
  //                         ),
  //                         const SizedBox(width: 10),
  //                         FilledButton(
  //                           onPressed: () async {
  //                             // Xử lý logic thời gian
  //                             DateTime? finalDateTime;

  //                             // Nếu đang ở chế độ có nhắc nhở, ta gộp ngày + giờ
  //                             if (isRemind &&
  //                                 tempDate != null &&
  //                                 tempTime != null) {
  //                               finalDateTime = DateTime(
  //                                 tempDate!.year,
  //                                 tempDate!.month,
  //                                 tempDate!.day,
  //                                 tempTime!.hour,
  //                                 tempTime!.minute,
  //                               );
  //                             }

  //                             // Gọi hàm save chung
  //                             _handleSave(
  //                               currentId: existingNote['id'],
  //                               title: _titleController.text,
  //                               content: _contentController.text,
  //                               // Nếu isRemind = false hoặc chưa chọn giờ -> finalDateTime là null -> DAO sẽ xóa reminder
  //                               pickedTime: finalDateTime?.toString(),
  //                             );

  //                             // Đóng dialog
  //                             Navigator.pop(context);
  //                           },
  //                           child: const Text("Cập nhật"),
  //                         ),
  //                       ],
  //                     ),
  //                   ],
  //                 ),
  //               ),
  //             ),
  //           );
  //         },
  //       );
  //     },
  //   );
  // }

  // --- HÀM MỞ FORM CHUNG CHO CẢ TẠO MỚI VÀ SỬA ---
  void _openNoteForm(
    BuildContext context, {
    Map<String, dynamic>? existingNote,
  }) async {
    DateTime? initialDate;

    // A. NẾU LÀ SỬA (existingNote != null)
    if (existingNote != null) {
      // Kiểm tra xem note này có nhắc nhở không để lấy giờ hiển thị
      if (existingNote['remind'] == 1) {
        // Query lấy giờ từ bảng reminders
        // (Lưu ý: Nếu item từ Dashboard đã có sẵn 'full_date' thì dùng luôn, đỡ phải query)
        if (existingNote.containsKey('full_date') &&
            existingNote['full_date'] != null) {
          initialDate = existingNote['full_date'];
        } else {
          // Nếu click từ danh sách Ghi chú (chưa có giờ), phải query DB
          final db = await Dbconnector.instance.database;
          final maps = await db.query(
            'reminders',
            columns: ['scheduled_time'],
            where: 'note_id = ?',
            whereArgs: [existingNote['id']],
          );
          if (maps.isNotEmpty) {
            initialDate = DateTime.parse(
              maps.first['scheduled_time'] as String,
            );
          }
        }
      }
    }

    if (!context.mounted) return;

    // B. HIỂN THỊ DIALOG
    showDialog(
      context: context,
      builder: (context) {
        return NoteFormDialog(
          noteData: existingNote, // Truyền dữ liệu cũ vào (nếu có)
          initialDate: initialDate, // Truyền giờ cũ vào (nếu có)
          // C. XỬ LÝ KHI ẤN NÚT LƯU
          onSubmit: (title, content, pickedTime) async {
            if (title.trim().isEmpty) return;

            if (existingNote == null) {
              // --- LOGIC TẠO MỚI ---
              Note newNote = Note(
                title: title,
                content: content,
                remind: pickedTime != null, // Có giờ => True
                tag: 'General',
              );
              await _dao.createNote(newNote, scheduledTime: pickedTime);
            } else {
              // --- LOGIC CẬP NHẬT ---
              await _dao.updateNoteOrReminder(
                id:
                    existingNote['id'] ??
                    existingNote['note_id'], // ID của Note
                title: title,
                content: content,
                scheduledTime: pickedTime, // Nếu null => DAO sẽ xoá reminder
              );
            }

            // Refresh UI
            await _loadDataFromDB();
          },
        );
      },
    );
  }

  void _showEditReminderDialog(
    BuildContext context,
    Map<String, dynamic> item,
  ) {
    final TextEditingController titleCtrl = TextEditingController(
      text: item['title'],
    );
    final TextEditingController contentCtrl = TextEditingController(
      text: item['content'],
    );

    // Lấy DateTime gốc từ item (đã lưu ở bước _loadDataFromDB) hoặc parse lại
    DateTime? tempDate = item['full_date'] as DateTime?;
    TimeOfDay? tempTime = tempDate != null
        ? TimeOfDay.fromDateTime(tempDate)
        : TimeOfDay.now();

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return Dialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              child: Container(
                padding: const EdgeInsets.all(20),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        "Chỉnh sửa Nhắc nhở",
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 20),

                      TextField(
                        controller: titleCtrl,
                        decoration: const InputDecoration(
                          labelText: "Tiêu đề",
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 15),

                      // ... (Phần chọn ngày giờ giữ nguyên như code cũ của bạn) ...
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () async {
                                final picked = await showDatePicker(
                                  context: context,
                                  initialDate: tempDate ?? DateTime.now(),
                                  firstDate: DateTime.now(),
                                  lastDate: DateTime(2100),
                                );
                                if (picked != null)
                                  setStateDialog(() => tempDate = picked);
                              },
                              icon: const Icon(Icons.calendar_today),
                              label: Text(
                                tempDate == null
                                    ? "Chọn ngày"
                                    : "${tempDate!.day}/${tempDate!.month}",
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () async {
                                final picked = await showTimePicker(
                                  context: context,
                                  initialTime: tempTime ?? TimeOfDay.now(),
                                );
                                if (picked != null)
                                  setStateDialog(() => tempTime = picked);
                              },
                              icon: const Icon(Icons.access_time),
                              label: Text(
                                tempTime == null
                                    ? "Chọn giờ"
                                    : "${tempTime!.hour}:${tempTime!.minute.toString().padLeft(2, '0')}",
                              ),
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 25),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(
                            onPressed: () => Navigator.pop(context),
                            child: const Text(
                              "Hủy",
                              style: TextStyle(color: Colors.grey),
                            ),
                          ),

                          // --- NÚT XÓA ---
                          TextButton.icon(
                            icon: const Icon(
                              Icons.delete_outline,
                              color: Colors.redAccent,
                            ),
                            label: const Text(
                              "Xóa Note",
                              style: TextStyle(color: Colors.redAccent),
                            ),
                            onPressed: () async {
                              // Xóa toàn bộ Note và Reminder liên quan
                              await _dao.deleteNote(item['note_id']);

                              // Load lại UI và đóng dialog
                              await _loadDataFromDB();
                              if (context.mounted) Navigator.pop(context);
                            },
                          ),

                          // --- NÚT LƯU ---
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF3F51B5),
                              foregroundColor: Colors.white,
                            ),
                            child: const Text("Lưu"),
                            onPressed: () async {
                              // 1. Tổng hợp thời gian
                              DateTime? finalDateTime;
                              if (tempDate != null && tempTime != null) {
                                finalDateTime = DateTime(
                                  tempDate!.year,
                                  tempDate!.month,
                                  tempDate!.day,
                                  tempTime!.hour,
                                  tempTime!.minute,
                                );
                              }

                              // 2. Gọi DAO để cập nhật
                              // Lưu ý: item['note_id'] là ID của Note gốc
                              await _dao.updateNoteOrReminder(
                                id: item['note_id'],
                                title: titleCtrl.text,
                                content: contentCtrl.text,
                                scheduledTime:
                                    finalDateTime, // Truyền DateTime mới (hoặc null nếu muốn gỡ nhắc nhở)
                              );

                              // 3. Refresh UI
                              await _loadDataFromDB();
                              if (context.mounted) Navigator.pop(context);
                            },
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildEmptyState(String message, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(
        vertical: 30,
      ), // Khoảng cách trên dưới
      alignment: Alignment.center,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 50, color: Colors.grey.shade400),
          const SizedBox(height: 10),
          Text(
            message,
            style: TextStyle(color: Colors.grey.shade500, fontSize: 14),
          ),
        ],
      ),
    );
  }
}

class NoteFormDialog extends StatefulWidget {
  final Map<String, dynamic>? noteData; // Null = Tạo mới, Có dữ liệu = Sửa
  final DateTime? initialDate; // Giờ hẹn hiện tại (nếu có)
  final Function(String title, String content, DateTime? time) onSubmit;

  const NoteFormDialog({
    super.key,
    this.noteData,
    this.initialDate,
    required this.onSubmit,
  });

  @override
  State<NoteFormDialog> createState() => _NoteFormDialogState();
}

class _NoteFormDialogState extends State<NoteFormDialog> {
  late TextEditingController _titleController;
  late TextEditingController _contentController;
  DateTime? _selectedDate;
  TimeOfDay? _selectedTime;

  @override
  void initState() {
    super.initState();
    // 1. Điền dữ liệu cũ nếu đang ở chế độ Sửa
    _titleController = TextEditingController(
      text: widget.noteData?['title'] ?? '',
    );
    _contentController = TextEditingController(
      text: widget.noteData?['content'] ?? '',
    );

    // 2. Điền ngày giờ cũ nếu có
    if (widget.initialDate != null) {
      _selectedDate = widget.initialDate;
      _selectedTime = TimeOfDay.fromDateTime(widget.initialDate!);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Lấy kích thước màn hình để chỉnh độ rộng Dialog
    final size = MediaQuery.of(context).size;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      backgroundColor: Colors.white,
      child: Container(
        width: size.width * 0.9, // Chiếm 90% chiều rộng màn hình
        padding: const EdgeInsets.all(20),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // --- TIÊU ĐỀ FORM ---
              Text(
                widget.noteData == null
                    ? "Tạo ghi chú / Nhắc nhở"
                    : "Chỉnh sửa ghi chú",
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 20),

              // --- INPUT TIÊU ĐỀ ---
              TextField(
                controller: _titleController,
                decoration: InputDecoration(
                  labelText: 'Tiêu đề',
                  prefixIcon: const Icon(Icons.title_outlined),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 12,
                  ),
                ),
              ),
              const SizedBox(height: 15),

              // --- INPUT NỘI DUNG ---
              Container(
                constraints: BoxConstraints(
                  maxHeight: size.height * 0.3,
                ), // Giới hạn chiều cao
                child: TextField(
                  controller: _contentController,
                  maxLines: null, // Cho phép xuống dòng thoải mái
                  decoration: InputDecoration(
                    labelText: 'Nội dung chi tiết',
                    alignLabelWithHint: true,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 15),

              // --- CHỌN NGÀY GIỜ ---
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: _selectedDate ?? DateTime.now(),
                          firstDate: DateTime.now(),
                          lastDate: DateTime(2100),
                        );
                        if (picked != null)
                          setState(() => _selectedDate = picked);
                      },
                      icon: const Icon(Icons.calendar_today, size: 18),
                      label: Text(
                        _selectedDate == null
                            ? "Chọn ngày"
                            : "${_selectedDate!.day}/${_selectedDate!.month}/${_selectedDate!.year}",
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        final picked = await showTimePicker(
                          context: context,
                          initialTime: _selectedTime ?? TimeOfDay.now(),
                        );
                        if (picked != null)
                          setState(() => _selectedTime = picked);
                      },
                      icon: const Icon(Icons.access_time, size: 18),
                      label: Text(
                        _selectedTime == null
                            ? "Chọn giờ"
                            : "${_selectedTime!.hour}:${_selectedTime!.minute.toString().padLeft(2, '0')}",
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 25),

              // --- NÚT ACTION ---
              SizedBox(
                width: double.infinity,
                height: 50,
                child: FilledButton(
                  onPressed: () {
                    // 1. Gộp ngày giờ lại (nếu có chọn)
                    DateTime? finalDate;
                    if (_selectedDate != null && _selectedTime != null) {
                      finalDate = DateTime(
                        _selectedDate!.year,
                        _selectedDate!.month,
                        _selectedDate!.day,
                        _selectedTime!.hour,
                        _selectedTime!.minute,
                      );
                    }

                    // 2. Trả dữ liệu về cho hàm gọi
                    widget.onSubmit(
                      _titleController.text,
                      _contentController.text,
                      finalDate,
                    );
                    Navigator.pop(context); // Đóng Dialog
                  },
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF3F51B5),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: Text(widget.noteData == null ? "Lưu" : "Cập nhật"),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// --- CUSTOM WIDGETS ---
class SectionHeader extends StatelessWidget {
  final String title;
  final VoidCallback onTap;
  const SectionHeader({super.key, required this.title, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
          TextButton(
            onPressed: onTap,
            child: const Text(
              'Xem tất cả',
              style: TextStyle(color: Colors.blue, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

class ReminderCard extends StatelessWidget {
  final String title;
  final String time;
  final String date;
  final bool isUrgent;
  final VoidCallback? onEdit;

  const ReminderCard({
    super.key,
    required this.title,
    required this.time,
    required this.date,
    this.isUrgent = false,
    this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: isUrgent ? Colors.red.shade50 : Colors.blue.shade50,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(Icons.alarm, color: isUrgent ? Colors.red : Colors.blue),
        ),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text('$date • $time'),
        trailing: InkWell(
          onTap: onEdit, // <--- Gán hàm onEdit vào đây
          borderRadius: BorderRadius.circular(20), // Hiệu ứng bo tròn khi nhấn
          child: const Padding(
            padding: EdgeInsets.all(8.0), // Tăng vùng bấm cho dễ thao tác
            child: Icon(Icons.arrow_forward_ios, size: 14, color: Colors.grey),
          ),
        ),
      ),
    );
  }
}

class NoteCard extends StatelessWidget {
  final String title;
  final String content;
  final String tag;
  final bool isFullWidth;
  final bool hasReminder;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  const NoteCard({
    super.key,
    required this.title,
    required this.content,
    required this.tag,
    this.isFullWidth = false,
    this.hasReminder = false,
    this.onEdit,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // --- Hàng 1: Tag và Các nút chức năng ---
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Tag hiển thị bên trái
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.blue.shade50,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        tag,
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: Colors.blue,
                        ),
                      ),
                    ),
                    if (hasReminder)
                      Container(
                        margin: const EdgeInsets.only(left: 8),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.orange.shade50,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: Colors.orange.shade100),
                        ),
                        child: Row(
                          children: const [
                            Icon(
                              Icons.alarm,
                              size: 12,
                              color: Colors.deepOrange,
                            ),
                            SizedBox(width: 4),
                            Text(
                              "Có hẹn",
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: Colors.deepOrange,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
                // 👇 ĐÂY LÀ PHẦN HIỂN THỊ NÚT SỬA/XÓA 👇
                // Kiểm tra: Nếu có truyền hàm vào thì mới hiện nút
                if (onEdit != null || onDelete != null)
                  Row(
                    children: [
                      // Nút Sửa
                      InkWell(
                        onTap: onEdit,
                        borderRadius: BorderRadius.circular(12),
                        child: const Padding(
                          padding: EdgeInsets.all(6.0),
                          child: Icon(
                            Icons.edit,
                            size: 20,
                            color: Colors.orange,
                          ),
                        ),
                      ),
                      const SizedBox(width: 4),
                      // Nút Xóa
                      InkWell(
                        onTap: onDelete,
                        borderRadius: BorderRadius.circular(12),
                        child: const Padding(
                          padding: EdgeInsets.all(6.0),
                          child: Icon(
                            Icons.delete,
                            size: 20,
                            color: Colors.red,
                          ),
                        ),
                      ),
                    ],
                  ),
              ],
            ),

            const SizedBox(height: 12),

            // --- Hàng 2: Tiêu đề ---
            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
                color: Colors.black87,
              ),
            ),

            // --- Hàng 3: Nội dung ---
            const SizedBox(height: 6),
            Text(
              content,
              maxLines: isFullWidth ? 3 : 5,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }
}
