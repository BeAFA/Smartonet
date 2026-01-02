abstract class BaseModel {
  int? id;
  DateTime createdDate;
  bool active;

  BaseModel({this.id, DateTime? createdDate, this.active = true})
    : createdDate = createdDate ?? DateTime.now();

  Map<String, dynamic> toBaseMap() {
    return {
      'id': id,
      'created_date': createdDate.toIso8601String(),
      'active': active ? 1 : 0,
    };
  }
}

class Note extends BaseModel {
  String title;
  String content;
  bool remind;
  String tag;

  Note({
    super.id,
    super.createdDate,
    super.active,
    required this.title,
    required this.content,
    this.remind = false,
    this.tag = 'General',
  });

  Map<String, dynamic> toMap() {
    var map = toBaseMap();
    map.addAll({'title': title, 'content': content, 'remind': remind ? 1 : 0, 'tag': tag,});
    return map;
  }
}

class Reminder extends BaseModel {
  int noteId;
  DateTime scheduledTime;

  Reminder({
    super.id,
    super.createdDate,
    super.active,
    required this.noteId,
    required this.scheduledTime,
  });

  Map<String, dynamic> toMap() {
    var map = toBaseMap();
    map.addAll({
      'note_id': noteId,
      'scheduled_time': scheduledTime.toIso8601String(),
    });
    return map;
  }
}
