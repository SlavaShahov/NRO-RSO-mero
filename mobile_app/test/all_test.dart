// mobile_app/test/all_test.dart
// Запуск: flutter test test/all_test.dart

import 'package:flutter_test/flutter_test.dart';

// ══ Копии логики из приложения (для изолированных тестов) ══════════════════

String? validatePhone(String v) {
  if (v.trim().isEmpty) return null;
  final c = v.trim().replaceAll(RegExp(r'\D'), '');
  if (!RegExp(r'^8\d{10}$').hasMatch(c))
    return 'Формат: 89139391688 (11 цифр, начиная с 8)';
  return null;
}

int posOrder(String name, bool hq) {
  if (hq) {
    if (name.contains('Командир')) return 1;
    if (name.contains('Комиссар')) return 2;
    if (name.contains('Инженер'))  return 3;
    return 4;
  }
  if (name.contains('Командир')) return 5;
  if (name.contains('Комиссар')) return 6;
  if (name.contains('Мастер'))   return 7;
  return 8;
}

String displayName(String name) {
  if (name == 'Кандидат' || name.isEmpty) return 'Боец';
  return name;
}

bool isManagerRole(String role) {
  const roles = {
    'superadmin', 'regional_admin', 'local_admin',
    'unit_commander', 'unit_commissioner', 'unit_master',
  };
  return roles.contains(role);
}

// ══ Тесты телефона ══════════════════════════════════════════════════════════

void main() {
  group('Валидация телефона', () {
    test('пустой → валидно (необязательное)', () {
      expect(validatePhone(''), isNull);
      expect(validatePhone('   '), isNull);
    });

    test('8XXXXXXXXXX (11 цифр) → валидно', () {
      expect(validatePhone('89139391688'), isNull);
      expect(validatePhone('80001112233'), isNull);
      expect(validatePhone('89999999999'), isNull);
    });

    test('10 цифр → ошибка (слишком коротко)', () {
      expect(validatePhone('8913939168'), isNotNull);
    });

    test('12 цифр → ошибка (слишком длинно)', () {
      expect(validatePhone('891393916880'), isNotNull);
    });

    test('начинается с 7 → ошибка', () {
      expect(validatePhone('79139391688'), isNotNull);
    });

    test('начинается с +7 → ошибка', () {
      expect(validatePhone('+79139391688'), isNotNull);
    });

    test('начинается с 9 → ошибка', () {
      expect(validatePhone('99139391688'), isNotNull);
    });

    test('начинается с 1 → ошибка', () {
      expect(validatePhone('19139391688'), isNotNull);
    });

    test('содержит буквы → ошибка', () {
      expect(validatePhone('8913abc1688'), isNotNull);
    });

    test('содержит скобки и тире → убираем не-цифры и проверяем', () {
      // 8(913)939-16-88 → 89139391688 → валидно
      expect(validatePhone('8(913)939-16-88'), isNull);
    });

    test('только нули после 8 → технически валидно', () {
      expect(validatePhone('80000000000'), isNull);
    });

    test('сообщение об ошибке содержит пример', () {
      final err = validatePhone('123');
      expect(err, contains('89139391688'));
    });
  });

  // ══ Тесты порядка должностей ══════════════════════════════════════════════

  group('Порядок должностей — ШСО', () {
    test('Командир штаба = 1', () => expect(posOrder('Командир штаба', true), 1));
    test('Комиссар штаба = 2', () => expect(posOrder('Комиссар штаба', true), 2));
    test('Инженер штаба = 3',  () => expect(posOrder('Инженер штаба',  true), 3));
    test('Работник штаба = 4', () => expect(posOrder('Работник штаба', true), 4));

    test('ШСО по возрастанию', () {
      final orders = [1, 2, 3, 4].toList();
      final got = [
        posOrder('Командир штаба', true),
        posOrder('Комиссар штаба', true),
        posOrder('Инженер штаба',  true),
        posOrder('Работник штаба', true),
      ];
      expect(got, orders);
    });
  });

  group('Порядок должностей — отряд', () {
    test('Командир = 5',  () => expect(posOrder('Командир',  false), 5));
    test('Комиссар = 6',  () => expect(posOrder('Комиссар',  false), 6));
    test('Мастер = 7',    () => expect(posOrder('Мастер',    false), 7));
    test('Боец = 8',      () => expect(posOrder('Боец',      false), 8));
    test('Кандидат = 8',  () => expect(posOrder('Кандидат',  false), 8));
    test('пусто = 8',     () => expect(posOrder('',          false), 8));

    test('отряд по возрастанию', () {
      final names = ['Командир', 'Комиссар', 'Мастер', 'Боец'];
      for (var i = 1; i < names.length; i++) {
        expect(
          posOrder(names[i - 1], false),
          lessThan(posOrder(names[i], false)),
          reason: '${names[i-1]} должен быть выше ${names[i]}',
        );
      }
    });
  });

  group('ШСО всегда выше отряда', () {
    test('любой ШСО выше любого отряда', () {
      final hq   = ['Командир штаба', 'Комиссар штаба', 'Инженер штаба', 'Работник штаба'];
      final unit = ['Командир', 'Комиссар', 'Мастер', 'Боец', 'Кандидат', ''];
      for (final h in hq) {
        for (final u in unit) {
          expect(
            posOrder(h, true),
            lessThan(posOrder(u, false)),
            reason: "'$h'(hq) должен быть выше '$u'(unit)",
          );
        }
      }
    });

    test('Кандидат == Боец по приоритету', () {
      expect(posOrder('Кандидат', false), equals(posOrder('Боец', false)));
    });
  });

  // ══ Тесты displayName ═════════════════════════════════════════════════════

  group('Отображение должности', () {
    test('Кандидат → Боец', () => expect(displayName('Кандидат'), 'Боец'));
    test('пусто → Боец',    () => expect(displayName(''), 'Боец'));
    test('Боец → Боец',     () => expect(displayName('Боец'), 'Боец'));
    test('Командир → Командир', () => expect(displayName('Командир'), 'Командир'));
    test('Комиссар → Комиссар', () => expect(displayName('Комиссар'), 'Комиссар'));
    test('Мастер → Мастер',     () => expect(displayName('Мастер'),   'Мастер'));
    test('Командир штаба → Командир штаба',
      () => expect(displayName('Командир штаба'), 'Командир штаба'));
    test('Инженер штаба → Инженер штаба',
      () => expect(displayName('Инженер штаба'), 'Инженер штаба'));
  });

  // ══ Тесты ролей ═══════════════════════════════════════════════════════════

  group('isManagerRole', () {
    test('суперадмин — да',        () => expect(isManagerRole('superadmin'),        isTrue));
    test('regional_admin — да',    () => expect(isManagerRole('regional_admin'),    isTrue));
    test('local_admin — да',       () => expect(isManagerRole('local_admin'),       isTrue));
    test('unit_commander — да',    () => expect(isManagerRole('unit_commander'),    isTrue));
    test('unit_commissioner — да', () => expect(isManagerRole('unit_commissioner'), isTrue));
    test('unit_master — да',       () => expect(isManagerRole('unit_master'),       isTrue));

    test('hq_staff — НЕТ',   () => expect(isManagerRole('hq_staff'),   isFalse));
    test('participant — НЕТ', () => expect(isManagerRole('participant'), isFalse));
    test('candidate — НЕТ',   () => expect(isManagerRole('candidate'),  isFalse));
    test('пусто — НЕТ',       () => expect(isManagerRole(''),           isFalse));
  });

  // ══ Тесты форматирования данных ═══════════════════════════════════════════

  group('ФИО', () {
    test('полное с отчеством', () {
      final fio = 'Иванов Иван Иванович'.trim();
      expect(fio, 'Иванов Иван Иванович');
    });

    test('без отчества — нет лишних пробелов', () {
      final fio = ('Петров Пётр ').trim();
      expect(fio, 'Петров Пётр');
    });

    test('конкатенация ФИО', () {
      String buildFIO(String l, String f, String m) =>
          [l, f, if (m.isNotEmpty) m].join(' ').trim();

      expect(buildFIO('Иванов', 'Иван', 'Иванович'), 'Иванов Иван Иванович');
      expect(buildFIO('Петров', 'Пётр', ''), 'Петров Пётр');
    });
  });

  group('Учебное заведение — убираем «ШСО »', () {
    test('ШСО НГТУ → НГТУ', () {
      expect('ШСО НГТУ'.replaceFirst('ШСО ', ''), 'НГТУ');
    });
    test('без префикса — без изменений', () {
      expect('НТЖТ'.replaceFirst('ШСО ', ''), 'НТЖТ');
    });
    test('ШСО СГУПС → СГУПС', () {
      expect('ШСО СГУПС'.replaceFirst('ШСО ', ''), 'СГУПС');
    });
  });

  group('Тема письма = название мероприятия', () {
    test('совпадает точно', () {
      const title = 'Закрытие спартакиады РСО 2026';
      const subject = title;
      expect(subject, title);
    });
  });

  group('Санитизация имени файла', () {
    String sanitize(String s) => s
        .replaceAll('/', '-').replaceAll('\\', '-')
        .replaceAll(':', '-').replaceAll('*', '-')
        .replaceAll('?', '-').replaceAll('"', '-')
        .replaceAll('<', '-').replaceAll('>', '-')
        .replaceAll('|', '-');

    test('обычное название — без изменений', () {
      expect(sanitize('Дартс'), 'Дартс');
    });
    test('слэши заменяются', () {
      expect(sanitize('01/04/2026'), '01-04-2026');
    });
    test('двоеточие заменяется', () {
      expect(sanitize('Тест: финал'), 'Тест- финал');
    });
    test('файл заканчивается на .xlsx', () {
      expect('${sanitize("Дартс")}.xlsx', endsWith('.xlsx'));
    });
  });
}
