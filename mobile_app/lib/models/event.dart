class EventItem {
  final int id;
  final String title, description, eventDate, startTime, endTime, location;
  final String levelCode, typeCode, statusCode;
  final bool isRegistrationRequired;
  final int? maxParticipants;
  final int participantsCount;
  final String? userRegistrationStatus;

  const EventItem({required this.id, required this.title, required this.description,
    required this.eventDate, required this.startTime, required this.endTime,
    required this.location, required this.levelCode, required this.typeCode,
    required this.statusCode, required this.isRegistrationRequired,
    this.maxParticipants, required this.participantsCount, this.userRegistrationStatus});

  factory EventItem.fromJson(Map<String, dynamic> j) => EventItem(
    id: j['id'] as int, title: (j['title'] ?? '') as String,
    description: (j['description'] ?? '') as String,
    eventDate: (j['event_date'] ?? '') as String,
    startTime: (j['start_time'] ?? '') as String,
    endTime: (j['end_time'] ?? '') as String,
    location: (j['location'] ?? '') as String,
    levelCode: (j['level_code'] ?? '') as String,
    typeCode: (j['type_code'] ?? '') as String,
    statusCode: (j['status_code'] ?? '') as String,
    isRegistrationRequired: (j['is_registration_required'] ?? true) as bool,
    maxParticipants: j['max_participants'] as int?,
    participantsCount: (j['participants_count'] ?? 0) as int,
    userRegistrationStatus: j['user_registration_status'] as String?,
  );

  bool get isRegistered => userRegistrationStatus == 'registered';
  bool get isAttended   => userRegistrationStatus == 'attended';
  bool get hasRegistration => userRegistrationStatus != null && userRegistrationStatus != 'cancelled';

  String get levelLabel { switch(levelCode){case 'federal':return 'Федеральное';case 'regional':return 'Региональное';case 'local':return 'Вузовское';case 'unit':return 'Внутриотрядное';default:return levelCode;} }
  String get typeLabel  { switch(typeCode){case 'sport':return 'Спортивное';case 'culture':return 'Культурное';case 'education':return 'Обучающее';case 'headquarters':return 'Штабное';case 'labor':return 'Трудовое';default:return typeCode;} }

  String get dayStr   => eventDate.length>=10 ? eventDate.substring(8,10) : '';
  String get monthStr {
    if(eventDate.length<7) return '';
    final m=int.tryParse(eventDate.substring(5,7))??0;
    const ms=['','ЯНВ','ФЕВ','МАР','АПР','МАЙ','ИЮН','ИЮЛ','АВГ','СЕН','ОКТ','НОЯ','ДЕК'];
    return m>0&&m<=12?ms[m]:'';
  }
  String get startTimeShort => startTime.length>=5?startTime.substring(0,5):startTime;
}
