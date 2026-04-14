class UserProfile {
  final int id;
  final String email, lastName, firstName, middleName;
  final String phone, memberCardNumber, memberCardLocation;
  final String accountStatus;
  final String unitName, hqName, positionName, roleCode;
  final int? unitId, unitPositionId;

  const UserProfile({
    required this.id,
    required this.email,
    required this.lastName,
    required this.firstName,
    this.middleName         = '',
    this.phone              = '',
    this.memberCardNumber   = '',
    this.memberCardLocation = 'with_user',
    this.accountStatus      = 'active',
    this.unitId,
    this.unitPositionId,
    required this.unitName,
    required this.hqName,
    required this.positionName,
    required this.roleCode,
  });

  factory UserProfile.fromJson(Map<String, dynamic> j) => UserProfile(
    id:                 j['id']                                    as int,
    email:              (j['email']                ?? '')           as String,
    lastName:           (j['last_name']            ?? '')           as String,
    firstName:          (j['first_name']           ?? '')           as String,
    middleName:         (j['middle_name']          ?? '')           as String,
    phone:              (j['phone']                ?? '')           as String,
    memberCardNumber:   (j['member_card_number']   ?? '')           as String,
    memberCardLocation: (j['member_card_location'] ?? 'with_user')  as String,
    accountStatus:      (j['account_status']       ?? 'active')     as String,
    unitId:              j['unit_id']               as int?,
    unitPositionId:      j['unit_position_id']      as int?,
    unitName:           (j['unit_name']            ?? '')           as String,
    hqName:             (j['hq_name']              ?? '')           as String,
    positionName:       (j['position_name']        ?? '')           as String,
    roleCode:           (j['role_code']            ?? 'participant') as String,
  );

  String get fullName => '$lastName $firstName'.trim();

  String get memberCardLocationLabel =>
      memberCardLocation == 'in_hq' ? 'В РШ' : 'На руках';

  bool get isPendingApproval => accountStatus == 'pending_approval';

  /// Работник штаба — видит все отряды штаба, НЕ имеет прав администратора
  bool get isHQStaff => roleCode == 'hq_staff';

  /// Только настоящие администраторы — могут одобрять заявки ШСО
  bool get isAdmin {
    switch (roleCode) {
      case 'superadmin':
      case 'regional_admin':
      case 'local_admin':
        return true;
      default:
        return false;
    }
  }

  /// Вкладка «Управление» и кнопка сканера.
  /// hq_staff намеренно НЕ включён — штабники не управляют мероприятиями.
  bool get isManager {
    switch (roleCode) {
      case 'superadmin':
      case 'regional_admin':
      case 'local_admin':
      case 'unit_commander':
      case 'unit_commissioner':
      case 'unit_master':
        return true;
      default:
        return false;
    }
  }

  String get roleLabel {
    switch (roleCode) {
      case 'superadmin':        return 'Супер администратор';
      case 'regional_admin':    return 'Администратор региона';
      case 'local_admin':       return 'Администратор штаба';
      case 'hq_staff':          return 'Работник штаба';
      case 'unit_commander':    return 'Командир';
      case 'unit_commissioner': return 'Комиссар';
      case 'unit_master':       return 'Мастер';
      case 'participant':       return 'Боец';
      case 'candidate':         return 'Кандидат';
      default:                  return roleCode;
    }
  }
}

class HQItem {
  final int id;
  final String name;
  const HQItem({required this.id, required this.name});
  factory HQItem.fromJson(Map<String, dynamic> j) =>
      HQItem(id: j['id'] as int, name: (j['name'] ?? '') as String);
}

class UnitItem {
  final int id;
  final String name, directionCode, hqName;
  const UnitItem({
    required this.id,
    required this.name,
    required this.directionCode,
    required this.hqName,
  });
  factory UnitItem.fromJson(Map<String, dynamic> j) => UnitItem(
    id:            j['id']              as int,
    name:          (j['name']           ?? '') as String,
    directionCode: (j['direction_code'] ?? '') as String,
    hqName:        (j['hq_name']        ?? '') as String,
  );
}

class PositionItem {
  final int id;
  final String code, name;
  const PositionItem({required this.id, required this.code, required this.name});
  factory PositionItem.fromJson(Map<String, dynamic> j) => PositionItem(
    id:   j['id']    as int,
    code: (j['code'] ?? '') as String,
    name: (j['name'] ?? '') as String,
  );
}

class HQPositionItem {
  final int id;
  final String code, name;
  const HQPositionItem({required this.id, required this.code, required this.name});
  factory HQPositionItem.fromJson(Map<String, dynamic> j) => HQPositionItem(
    id:   j['id']    as int,
    code: (j['code'] ?? '') as String,
    name: (j['name'] ?? '') as String,
  );
}

class HQStaffRequest {
  final int id, userId, hqId, positionId;
  final String fullName, hqName, positionName, status, comment;
  final DateTime requestedAt;

  const HQStaffRequest({
    required this.id,
    required this.userId,
    required this.fullName,
    required this.hqId,
    required this.hqName,
    required this.positionId,
    required this.positionName,
    required this.status,
    required this.requestedAt,
    this.comment = '',
  });

  factory HQStaffRequest.fromJson(Map<String, dynamic> j) => HQStaffRequest(
    id:           j['id']             as int,
    userId:       j['user_id']        as int,
    fullName:     (j['full_name']     ?? '') as String,
    hqId:         j['hq_id']          as int,
    hqName:       (j['hq_name']       ?? '') as String,
    positionId:   j['position_id']    as int,
    positionName: (j['position_name'] ?? '') as String,
    status:       (j['status']        ?? 'pending') as String,
    requestedAt:  DateTime.tryParse((j['requested_at'] ?? '') as String) ??
        DateTime.now(),
    comment:      (j['comment']       ?? '') as String,
  );
}

class MyRegistration {
  final int registrationId;
  final String qrCode, status, participationType;
  final String registeredAt;
  final int eventId;
  final String eventTitle, eventDate, startTime, location, levelCode, typeCode;

  const MyRegistration({
    required this.registrationId,
    required this.qrCode,
    required this.status,
    this.participationType = 'participant',
    required this.registeredAt,
    required this.eventId,
    required this.eventTitle,
    required this.eventDate,
    required this.startTime,
    required this.location,
    required this.levelCode,
    required this.typeCode,
  });

  factory MyRegistration.fromJson(Map<String, dynamic> j) => MyRegistration(
    registrationId:    j['registration_id']     as int,
    qrCode:            (j['qr_code']            ?? '') as String,
    status:            (j['status']             ?? '') as String,
    participationType: (j['participation_type'] ?? 'participant') as String,
    registeredAt:      (j['registered_at']      ?? '') as String,
    eventId:           j['event_id']             as int,
    eventTitle:        (j['event_title']         ?? '') as String,
    eventDate:         (j['event_date']          ?? '') as String,
    startTime:         (j['start_time']          ?? '') as String,
    location:          (j['location']            ?? '') as String,
    levelCode:         (j['level_code']          ?? '') as String,
    typeCode:          (j['type_code']           ?? '') as String,
  );

  bool get isUpcoming => status == 'registered';
  bool get isAttended => status == 'attended';

  String get startTimeShort =>
      startTime.length >= 5 ? startTime.substring(0, 5) : startTime;

  String get dayStr =>
      eventDate.length >= 10 ? eventDate.substring(8, 10) : '';

  String get monthStr {
    if (eventDate.length < 7) return '';
    final m = int.tryParse(eventDate.substring(5, 7)) ?? 0;
    const ms = [
      '', 'янв', 'фев', 'мар', 'апр', 'май', 'июн',
      'июл', 'авг', 'сен', 'окт', 'ноя', 'дек'
    ];
    return m > 0 && m <= 12 ? ms[m] : '';
  }
}