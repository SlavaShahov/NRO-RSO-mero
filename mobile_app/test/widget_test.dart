// ignore_for_file: prefer_const_constructors

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:rso_events/models/user.dart';
import 'package:rso_events/models/event.dart';
import 'package:rso_events/providers/auth_provider.dart';
import 'package:rso_events/providers/notifications_provider.dart';
import 'package:rso_events/screens/notifications_screen.dart';
import 'package:rso_events/services/api_client.dart';

void main() {
  // ════════════════════════════════════════════════════════════════════════
  // UserProfile.fromJson
  // ════════════════════════════════════════════════════════════════════════
  group('UserProfile.fromJson', () {
    test('все поля', () {
      final u = UserProfile.fromJson({
        'id': 1, 'email': 'test@rso.ru',
        'last_name': 'Иванов', 'first_name': 'Иван', 'middle_name': 'Петрович',
        'unit_name': 'ССО', 'hq_name': 'ШСО НГТУ',
        'position_name': 'Командир', 'role_code': 'unit_commander',
        'phone': '+79130000000', 'member_card_number': 'НРО-001',
        'member_card_location': 'with_user', 'account_status': 'active',
      });
      expect(u.id, 1); expect(u.email, 'test@rso.ru');
      expect(u.fullName, 'Иванов Иван'); expect(u.phone, '+79130000000');
      expect(u.accountStatus, 'active');
    });
    test('defaults', () {
      final u = UserProfile.fromJson({
        'id': 2, 'email': 'a@b.ru',
        'last_name': 'X', 'first_name': 'Y', 'middle_name': '',
        'unit_name': '', 'hq_name': '', 'position_name': '', 'role_code': 'participant',
      });
      expect(u.phone, ''); expect(u.memberCardLocation, 'with_user'); expect(u.accountStatus, 'active');
    });
    test('null поля', () {
      final u = UserProfile.fromJson({
        'id': 3, 'email': 'n@rso.ru', 'last_name': 'Н', 'first_name': 'Н',
        'middle_name': null, 'unit_name': null, 'hq_name': null,
        'position_name': null, 'role_code': null, 'unit_id': null,
      });
      expect(u.middleName, ''); expect(u.unitId, null); expect(u.roleCode, 'participant');
    });
    test('in_hq', () {
      final u = UserProfile.fromJson({
        'id':4,'email':'x@x.ru','last_name':'X','first_name':'X','middle_name':'',
        'unit_name':'','hq_name':'','position_name':'',
        'role_code':'participant','member_card_location':'in_hq',
      });
      expect(u.memberCardLocation, 'in_hq');
    });
  });

  // ════════════════════════════════════════════════════════════════════════
  // UserProfile геттеры
  // Реальная логика из user.dart:
  // isAdmin    = superadmin | regional_admin | local_admin
  // isManager  = superadmin | regional_admin | local_admin  (НЕ unit_commander!)
  // canScan    = isManager
  // isHQStaff  = roleCode == 'hq_staff'
  // ════════════════════════════════════════════════════════════════════════
  group('UserProfile геттеры', () {
    UserProfile u(String role, {String status = 'active'}) => UserProfile(
      id: 1, email: 'u@rso.ru', lastName: 'Л', firstName: 'Ф',
      middleName: '', unitName: '', hqName: '', positionName: '',
      roleCode: role, accountStatus: status,
    );

    // isAdmin
    test('isAdmin superadmin = true',      () => expect(u('superadmin').isAdmin, true));
    test('isAdmin regional_admin = true',  () => expect(u('regional_admin').isAdmin, true));
    test('isAdmin local_admin = true',     () => expect(u('local_admin').isAdmin, true));
    test('isAdmin unit_commander = false', () => expect(u('unit_commander').isAdmin, false));
    test('isAdmin participant = false',    () => expect(u('participant').isAdmin, false));
    test('isAdmin hq_staff = false',       () => expect(u('hq_staff').isAdmin, false));
    test('isAdmin candidate = false',      () => expect(u('candidate').isAdmin, false));

    // isHQStaff
    test('isHQStaff true',  () => expect(u('hq_staff').isHQStaff, true));
    test('isHQStaff false', () => expect(u('unit_commander').isHQStaff, false));

    // isManager — только admin-роли
    test('isManager superadmin = true',      () => expect(u('superadmin').isManager, true));
    test('isManager regional_admin = true',  () => expect(u('regional_admin').isManager, true));
    test('isManager local_admin = true',     () => expect(u('local_admin').isManager, true));
    test('isManager unit_commander = false', () => expect(u('unit_commander').isManager, false));
    test('isManager hq_staff = false',       () => expect(u('hq_staff').isManager, false));
    test('isManager participant = false',    () => expect(u('participant').isManager, false));

    // canScan = isManager
    test('canScan superadmin = true',      () => expect(u('superadmin').canScan, true));
    test('canScan regional_admin = true',  () => expect(u('regional_admin').canScan, true));
    test('canScan unit_commander = false', () => expect(u('unit_commander').canScan, false));
    test('canScan hq_staff = false',       () => expect(u('hq_staff').canScan, false));

    // isPendingApproval
    test('isPendingApproval true',  () => expect(u('hq_staff', status: 'pending_approval').isPendingApproval, true));
    test('isPendingApproval false', () => expect(u('participant').isPendingApproval, false));

    // fullName
    test('fullName', () => expect(u('participant').fullName, 'Л Ф'));

    // roleLabel
    test('roleLabel все непустые', () {
      for (final r in ['superadmin','regional_admin','local_admin',
        'unit_commander','unit_commissioner','unit_master',
        'hq_staff','participant','candidate']) {
        expect(u(r).roleLabel.isNotEmpty, true, reason: 'roleLabel пустой для $r');
      }
    });
    test('roleLabel superadmin',  () => expect(u('superadmin').roleLabel, 'Супер администратор'));
    test('roleLabel participant', () => expect(u('participant').roleLabel, 'Боец'));
    test('roleLabel candidate',   () => expect(u('candidate').roleLabel, 'Кандидат'));
    test('roleLabel commander',   () => expect(u('unit_commander').roleLabel, 'Командир'));
    test('roleLabel hq_staff',    () => expect(u('hq_staff').roleLabel, 'Работник штаба'));
  });

  // ════════════════════════════════════════════════════════════════════════
  // EventItem.fromJson
  // ════════════════════════════════════════════════════════════════════════
  group('EventItem.fromJson', () {
    Map<String, dynamic> base() => {
      'id': 10, 'title': 'Дартс', 'description': 'Турнир',
      'event_date': '2026-05-20', 'start_time': '09:00', 'end_time': '13:00',
      'location': 'НСО', 'level_code': 'regional', 'type_code': 'sport',
      'status_code': 'published', 'is_registration_required': true,
      'participants_count': 5,
    };

    test('базовые поля', () {
      final e = EventItem.fromJson(base());
      expect(e.id, 10); expect(e.title, 'Дартс');
      expect(e.eventDate, '2026-05-20'); expect(e.levelCode, 'regional');
    });
    test('isRegistered',      () => expect(EventItem.fromJson(base()..['user_registration_status']='registered').isRegistered, true));
    test('isAttended',        () => expect(EventItem.fromJson(base()..['user_registration_status']='attended').isAttended, true));
    test('hasReg registered', () => expect(EventItem.fromJson(base()..['user_registration_status']='registered').hasRegistration, true));
    test('hasReg attended',   () => expect(EventItem.fromJson(base()..['user_registration_status']='attended').hasRegistration, true));
    test('hasReg cancelled',  () => expect(EventItem.fromJson(base()..['user_registration_status']='cancelled').hasRegistration, false));
    test('hasReg null',       () => expect(EventItem.fromJson(base()).hasRegistration, false));
    test('regClosed false',   () => expect(EventItem.fromJson(base()).isRegistrationClosed, false));
    test('regClosed true',    () => expect(EventItem.fromJson(base()..['is_registration_closed']=true).isRegistrationClosed, true));
    test('banner null',       () => expect(EventItem.fromJson(base()).bannerBase64, null));
    test('banner value',      () => expect(EventItem.fromJson(base()..['banner_base64']='abc').bannerBase64, 'abc'));

    test('levelLabel все', () {
      const m = {'federal':'Федеральное','regional':'Региональное','local':'Вузовское','unit':'Внутриотрядное'};
      m.forEach((k,v) => expect(EventItem.fromJson(base()..['level_code']=k).levelLabel, v));
    });
    test('typeLabel все', () {
      const m = {'sport':'Спортивное','culture':'Культурное','education':'Обучающее','headquarters':'Штабное','labor':'Трудовое'};
      m.forEach((k,v) => expect(EventItem.fromJson(base()..['type_code']=k).typeLabel, v));
    });

    test('dayStr',   () => expect(EventItem.fromJson(base()).dayStr, '20'));
    test('monthStr май', () => expect(EventItem.fromJson(base()).monthStr, 'МАЙ'));
    test('monthStr все месяцы', () {
      const months = {
        '2026-01-01':'ЯНВ','2026-02-01':'ФЕВ','2026-03-01':'МАР',
        '2026-04-01':'АПР','2026-05-01':'МАЙ','2026-06-01':'ИЮН',
        '2026-07-01':'ИЮЛ','2026-08-01':'АВГ','2026-09-01':'СЕН',
        '2026-10-01':'ОКТ','2026-11-01':'НОЯ','2026-12-01':'ДЕК',
      };
      months.forEach((date, abbr) =>
          expect(EventItem.fromJson(base()..['event_date']=date).monthStr, abbr, reason: date));
    });
    test('startTimeShort с секундами', () =>
        expect(EventItem.fromJson(base()..['start_time']='09:00:00').startTimeShort, '09:00'));
    test('startTimeShort без секунд',  () =>
        expect(EventItem.fromJson(base()..['start_time']='14:30').startTimeShort, '14:30'));
    test('maxParticipants null', () => expect(EventItem.fromJson(base()).maxParticipants, null));
    test('maxParticipants 50',   () => expect(EventItem.fromJson(base()..['max_participants']=50).maxParticipants, 50));
  });

  // ════════════════════════════════════════════════════════════════════════
  // AppNotification.fromJson
  // ════════════════════════════════════════════════════════════════════════
  group('AppNotification.fromJson', () {
    test('hq_staff_approved', () {
      final n = AppNotification.fromJson({'id':1,'type_code':'hq_staff_approved','title':'T','body':'B',
        'ref_id':42,'ref_type':'request','ref_approved':true,'is_read':false,'created_at':'2026-05-13T10:00:00Z'});
      expect(n.refId, 42); expect(n.refType, 'request'); expect(n.refApproved, true);
    });
    test('rejected ref_approved false', () {
      final n = AppNotification.fromJson({'id':2,'type_code':'hq_staff_rejected','title':'T','body':'B',
        'ref_id':5,'ref_type':'request','ref_approved':false,'is_read':false,'created_at':'2026-05-13T10:00:00Z'});
      expect(n.refApproved, false);
    });
    test('event без ref_approved', () {
      final n = AppNotification.fromJson({'id':3,'type_code':'new_event_created','title':'T','body':'B',
        'ref_id':10,'ref_type':'event','is_read':false,'created_at':'2026-05-13T10:00:00Z'});
      expect(n.refId, 10); expect(n.refType, 'event'); expect(n.refApproved, null);
    });
    test('system без ref', () {
      final n = AppNotification.fromJson({'id':4,'type_code':'system_message','title':'T','body':'B',
        'is_read':true,'created_at':'2026-05-13T10:00:00Z'});
      expect(n.refId, null); expect(n.isRead, true);
    });
    test('createdAt парсится', () {
      final n = AppNotification.fromJson({'id':5,'type_code':'x','title':'T','body':'B',
        'is_read':false,'created_at':'2026-05-13T15:30:00Z'});
      expect(n.createdAt.year, 2026); expect(n.createdAt.month, 5);
    });
    test('createdAt fallback', () {
      final before = DateTime.now().subtract(const Duration(seconds: 1));
      final n = AppNotification.fromJson({'id':6,'type_code':'x','title':'T','body':'B',
        'is_read':false,'created_at':''});
      expect(n.createdAt.isAfter(before), true);
    });
    test('все type_code', () {
      for (final t in ['hq_staff_request','hq_staff_approved','hq_staff_rejected',
        'new_event_created','position_change_approved','position_change_rejected','system_message']) {
        expect(() => AppNotification.fromJson({'id':1,'type_code':t,'title':'T','body':'B',
          'is_read':false,'created_at':'2026-01-01T00:00:00Z'}), returnsNormally, reason: t);
      }
    });
  });

  // ════════════════════════════════════════════════════════════════════════
  // Вспомогательные модели
  // ════════════════════════════════════════════════════════════════════════
  group('HQItem', () {
    test('fromJson', () { final h = HQItem.fromJson({'id':1,'name':'ШСО'}); expect(h.id,1); expect(h.name,'ШСО'); });
    test('равенство', () => expect(HQItem.fromJson({'id':1,'name':'А'}), HQItem.fromJson({'id':1,'name':'Б'})));
    test('разные id !=', () => expect(HQItem.fromJson({'id':1,'name':'А'}), isNot(HQItem.fromJson({'id':2,'name':'А'}))));
  });
  group('UnitItem', () {
    test('fromJson', () { final u = UnitItem.fromJson({'id':5,'name':'ССО','direction_code':'ССО','hq_name':'Х'}); expect(u.id,5); });
    test('равенство', () => expect(
        UnitItem.fromJson({'id':1,'name':'А','direction_code':'ССО','hq_name':'X'}),
        UnitItem.fromJson({'id':1,'name':'Б','direction_code':'СПО','hq_name':'Y'})));
  });
  group('PositionItem', () {
    test('fromJson', () => expect(PositionItem.fromJson({'id':2,'code':'commander','name':'К'}).code, 'commander'));
    test('равенство', () => expect(PositionItem.fromJson({'id':1,'code':'a','name':'A'}),
        PositionItem.fromJson({'id':1,'code':'b','name':'B'})));
  });
  group('HQPositionItem', () {
    test('fromJson', () => expect(HQPositionItem.fromJson({'id':1,'code':'cmd','name':'К ШСО'}).name, 'К ШСО'));
  });

  // ════════════════════════════════════════════════════════════════════════
  // base64
  // ════════════════════════════════════════════════════════════════════════
  group('base64', () {
    test('round-trip', () { final b = Uint8List.fromList([1,2,3,255,0,128]); expect(base64Decode(base64Encode(b)), equals(b)); });
    test('пустой', () => expect(base64Decode(base64Encode(Uint8List(0))), isEmpty));
    test('1024 байт', () { final b = Uint8List.fromList(List.generate(1024,(i)=>i%256)); expect(base64Decode(base64Encode(b)), equals(b)); });
    test('PNG magic', () {
      const s = 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==';
      final d = base64Decode(s); expect(d[0], 0x89); expect(d[1], 0x50);
    });
  });

  // ════════════════════════════════════════════════════════════════════════
  // NotificationBell
  // ════════════════════════════════════════════════════════════════════════
  group('NotificationBell', () {
    testWidgets('бейдж при > 0',  (t) async { await t.pumpWidget(_bell(3)); expect(find.text('3'), findsOneWidget); });
    testWidgets('нет бейджа = 0', (t) async { await t.pumpWidget(_bell(0)); expect(find.text('0'), findsNothing); });
    testWidgets('99+ при > 99',   (t) async { await t.pumpWidget(_bell(100)); expect(find.text('99+'), findsOneWidget); });
    testWidgets('99 как 99',      (t) async { await t.pumpWidget(_bell(99)); expect(find.text('99'), findsOneWidget); });
    testWidgets('иконка есть',    (t) async { await t.pumpWidget(_bell(0)); expect(find.byType(IconButton), findsOneWidget); });
  });

  // ════════════════════════════════════════════════════════════════════════
  // NotificationsScreen
  // ════════════════════════════════════════════════════════════════════════
  group('NotificationsScreen', () {
    testWidgets('загрузка', (t) async {
      await t.pumpWidget(_screen(loading: true));
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });
    testWidgets('пустой список', (t) async {
      await t.pumpWidget(_screen()); await t.pump();
      expect(find.text('Нет уведомлений'), findsOneWidget);
    });
    testWidgets('иконка нет уведомлений', (t) async {
      await t.pumpWidget(_screen()); await t.pump();
      expect(find.byIcon(Icons.notifications_none), findsOneWidget);
    });
    testWidgets('заголовок уведомления', (t) async {
      await t.pumpWidget(_screen(notifications: [_n(1,'new_event_created','Тестовое мероприятие')]));
      await t.pump();
      expect(find.text('Тестовое мероприятие'), findsOneWidget);
    });
    testWidgets('тело уведомления', (t) async {
      await t.pumpWidget(_screen(notifications: [_nb(1,'x','Т','Тело уведомления')]));
      await t.pump();
      expect(find.text('Тело уведомления'), findsOneWidget);
    });
    testWidgets('«Прочитать все» при unread > 0', (t) async {
      await t.pumpWidget(_screen(unread:1, notifications:[_n(1,'x','T')]));
      await t.pump();
      expect(find.text('Прочитать все'), findsOneWidget);
    });
    testWidgets('нет «Прочитать все» при 0', (t) async {
      await t.pumpWidget(_screen(unread:0, notifications:[_nr(1,'x','T')]));
      await t.pump();
      expect(find.text('Прочитать все'), findsNothing);
    });
    testWidgets('Одобрить/Отклонить hq_staff у админа', (t) async {
      await t.pumpWidget(_screen(unread:1, isAdmin:true, notifications:[
        _nReq(5,'hq_staff_request','Заявка на ШСО',10),
      ]));
      await t.pump();
      expect(find.text('Одобрить'), findsOneWidget);
      expect(find.text('Отклонить'), findsOneWidget);
    });
    testWidgets('Одобрить/Отклонить position_change у админа', (t) async {
      await t.pumpWidget(_screen(unread:1, isAdmin:true, notifications:[
        _nReq(6,'position_change_request','Смена должности',11),
      ]));
      await t.pump();
      expect(find.text('Одобрить'), findsOneWidget);
      expect(find.text('Отклонить'), findsOneWidget);
    });
    testWidgets('у не-админа нет кнопок', (t) async {
      await t.pumpWidget(_screen(unread:1, isAdmin:false, notifications:[
        _nReq(7,'hq_staff_request','T',12),
      ]));
      await t.pump();
      expect(find.text('Одобрить'), findsNothing);
    });
    testWidgets('прочитанное — нет кнопок', (t) async {
      await t.pumpWidget(_screen(unread:0, isAdmin:true, notifications:[
        AppNotification(id:8,typeCode:'hq_staff_request',title:'T',body:'B',
            refId:13,refType:'request',isRead:true,createdAt:DateTime.now()),
      ]));
      await t.pump();
      expect(find.text('Одобрить'), findsNothing);
    });
    testWidgets('несколько уведомлений', (t) async {
      await t.pumpWidget(_screen(unread:2, notifications:[
        _n(1,'x','Первое'), _n(2,'x','Второе'), _nr(3,'x','Третье'),
      ]));
      await t.pump();
      expect(find.text('Первое'), findsOneWidget);
      expect(find.text('Второе'), findsOneWidget);
      expect(find.text('Третье'), findsOneWidget);
    });
  });
}

// ── Фабрики уведомлений ───────────────────────────────────────────────────────
AppNotification _n(int id, String type, String title) =>
    AppNotification(id:id,typeCode:type,title:title,body:'Б',isRead:false,createdAt:DateTime.now());

AppNotification _nb(int id, String type, String title, String body) =>
    AppNotification(id:id,typeCode:type,title:title,body:body,isRead:false,createdAt:DateTime.now());

AppNotification _nr(int id, String type, String title) =>
    AppNotification(id:id,typeCode:type,title:title,body:'Б',isRead:true,createdAt:DateTime.now());

AppNotification _nReq(int id, String type, String title, int refId) =>
    AppNotification(id:id,typeCode:type,title:title,body:'Б',
        refId:refId,refType:'request',isRead:false,createdAt:DateTime.now());

// ── Провайдеры — наследуются от реальных классов ──────────────────────────────

class _FakeApi extends ApiClient {
  _FakeApi() : super(baseUrl: 'http://localhost');
}

class _FakeNP extends NotificationsProvider {
  _FakeNP({int unread = 0, bool loading = false, List<AppNotification>? notifications})
      : super(api: _FakeApi()) {
    this.notifications = notifications ?? [];
    this.loading = loading;
    unreadCount = unread;
  }
}

class _FakeAP extends AuthProvider {
  _FakeAP(this._isAdmin) : super(api: _FakeApi());
  final bool _isAdmin;

  @override
  UserProfile? get user => UserProfile(
    id: 1, email: 'u@rso.ru', lastName: 'Л', firstName: 'Ф',
    middleName: '', unitName: '', hqName: '', positionName: '',
    roleCode: _isAdmin ? 'superadmin' : 'participant',
  );
  @override bool get isAuthorized => true;
  @override bool get isLoading => false;
}

// ── Хелперы для виджет-тестов ─────────────────────────────────────────────────

Widget _bell(int unread) => ChangeNotifierProvider<NotificationsProvider>.value(
  value: _FakeNP(unread: unread),
  child: MaterialApp(home: Scaffold(appBar: AppBar(actions: [NotificationBell()]))),
);

Widget _screen({bool loading=false, int unread=0, bool isAdmin=false, List<AppNotification>? notifications}) =>
    MultiProvider(
      providers: [
        ChangeNotifierProvider<NotificationsProvider>.value(
            value: _FakeNP(unread:unread, loading:loading, notifications:notifications)),
        ChangeNotifierProvider<AuthProvider>.value(value: _FakeAP(isAdmin)),
      ],
      child: const MaterialApp(home: NotificationsScreen()),
    );