class UserProfile {
  final int id;
  final String email, lastName, firstName, middleName;
  final String unitName, hqName, positionName, roleCode;
  final int? unitId, unitPositionId;
  final String phone, memberCardNumber, memberCardLocation, accountStatus;

  const UserProfile({
    required this.id,
    required this.email,
    required this.lastName,
    required this.firstName,
    required this.middleName,
    this.unitId,
    this.unitPositionId,
    required this.unitName,
    required this.hqName,
    required this.positionName,
    required this.roleCode,
    this.phone              = '',
    this.memberCardNumber   = '',
    this.memberCardLocation = 'with_user',
    this.accountStatus      = 'active',
  });

  factory UserProfile.fromJson(Map<String, dynamic> j) => UserProfile(
    id:                 j['id'] as int,
    email:              (j['email']             ?? '') as String,
    lastName:           (j['last_name']         ?? '') as String,
    firstName:          (j['first_name']        ?? '') as String,
    middleName:         (j['middle_name']       ?? '') as String,
    unitId:             j['unit_id']             as int?,
    unitPositionId:     j['unit_position_id']    as int?,
    unitName:           (j['unit_name']         ?? '') as String,
    hqName:             (j['hq_name']           ?? '') as String,
    positionName:       (j['position_name']     ?? 'Боец') as String,
    roleCode:           (j['role_code']         ?? 'participant') as String,
    phone:              (j['phone']             ?? '') as String,
    memberCardNumber:   (j['member_card_number']   ?? '') as String,
    memberCardLocation: (j['member_card_location'] ?? 'with_user') as String,
    accountStatus:      (j['account_status']    ?? 'active') as String,
  );

  String get fullName => '$lastName $firstName'.trim();

  bool get isHQStaff => roleCode == 'hq_staff';

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

  bool get canScan => isManager;

  bool get isPendingApproval => accountStatus == 'pending_approval';

  String get roleLabel {
    switch (roleCode) {
      case 'superadmin':        return 'Супер администратор';
      case 'regional_admin':    return 'Администратор региона';
      case 'local_admin':       return 'Администратор штаба';
      case 'unit_commander':    return 'Командир';
      case 'unit_commissioner': return 'Комиссар';
      case 'unit_master':       return 'Мастер/Инженер';
      case 'hq_staff':          return 'Работник штаба';
      case 'participant':       return 'Боец';
      case 'candidate':         return 'Кандидат';
      default:
        return positionName.isNotEmpty ? positionName : 'Боец';
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
  const UnitItem({required this.id, required this.name,
    required this.directionCode, required this.hqName});
  factory UnitItem.fromJson(Map<String, dynamic> j) => UnitItem(
    id:            j['id'] as int,
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
    id: j['id'] as int,
    code: (j['code'] ?? '') as String,
    name: (j['name'] ?? '') as String,
  );
}

class HQPositionItem {
  final int id;
  final String code, name;
  const HQPositionItem({required this.id, required this.code, required this.name});
  factory HQPositionItem.fromJson(Map<String, dynamic> j) => HQPositionItem(
    id:   j['id'] as int,
    code: (j['code'] ?? '') as String,
    name: (j['name'] ?? '') as String,
  );
}