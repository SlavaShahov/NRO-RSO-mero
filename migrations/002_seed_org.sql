INSERT INTO regional_offices(name,region,description)
VALUES('Новосибирское региональное отделение МООО «РСО»','Новосибирская область','Региональное отделение РСО по Новосибирской области')
ON CONFLICT DO NOTHING;

DO $$
DECLARE v_ro INTEGER;
BEGIN
  SELECT id INTO v_ro FROM regional_offices WHERE region='Новосибирская область' LIMIT 1;
  INSERT INTO local_headquarters(regional_office_id,name,educational_institution,is_active) VALUES
    (v_ro,'ШСО НГАСУ (Сибстрин)','НГАСУ — Новосибирский государственный архитектурно-строительный университет',true),
    (v_ro,'ШСО НГАУ','НГАУ — Новосибирский государственный аграрный университет',true),
    (v_ro,'ШСО НГМУ','НГМУ — Новосибирский государственный медицинский университет',true),
    (v_ro,'ШСО НГПУ','НГПУ — Новосибирский государственный педагогический университет',true),
    (v_ro,'ШСО НГТУ','НГТУ — Новосибирский государственный технический университет',true),
    (v_ro,'ШСО НГУ','НГУ — Новосибирский государственный университет',true),
    (v_ro,'ШСО НГУЭУ','НГУЭУ — Новосибирский государственный университет экономики и управления',true),
    (v_ro,'ШСО СИУ РАНХиГС','СИУ РАНХиГС — Сибирский институт управления РАНХиГС',true),
    (v_ro,'ШСО СГУВТ','СГУВТ — Сибирский государственный университет водного транспорта',true),
    (v_ro,'ШСО СГУГиТ','СГУГиТ — Сибирский государственный университет геосистем и технологий',true),
    (v_ro,'ШСО СГУПС','СГУПС — Сибирский государственный университет путей сообщения',true),
    (v_ro,'ШСО СибГУТИ','СибГУТИ — Сибирский государственный университет телекоммуникаций и информатики',true),
    (v_ro,'ШСО СибУПК','СибУПК — Сибирский университет потребительской кооперации',true),
    (v_ro,'НТЖТ','НТЖТ — Новосибирский техникум железнодорожного транспорта',true),
    (v_ro,'НКТТ','НКТТ — Новосибирский колледж транспортных технологий',true),
    (v_ro,'НМК','НМК — Новосибирский медицинский колледж',true),
    (v_ro,'НПК №1','НПК №1 им. А.С. Макаренко',true),
    (v_ro,'НГУАДИ','НГУАДИ — Новосибирский государственный университет архитектуры, дизайна и искусств',true),
    (v_ro,'НАСК','НАСК — Новосибирский архитектурно-строительный колледж',true),
    (v_ro,'НАК','НАК — Новосибирский авиационный технический колледж',true),
    (v_ro,'НКПиИТ','НКПиИТ — Новосибирский колледж программирования и информационных технологий',true),
    (v_ro,'НКССиС','НКССиС — Новосибирский колледж систем связи и сервиса',true),
    (v_ro,'НТЭК','НТЭК — Новосибирский техникум экономики и кооперации',true),
    (v_ro,'НТКП','НТКП — Новосибирский торгово-коммерческий колледж',true),
    (v_ro,'НКТ им. А.Н. Косыгина','НКТ им. А.Н. Косыгина',true),
    (v_ro,'НПК','НПК — Новосибирский промышленно-коммерческий лицей',true),
    (v_ro,'НСМК','НСМК — Новосибирский строительно-монтажный колледж',true),
    (v_ro,'НТГиК','НТГиК — Новосибирский техникум геодезии и картографии',true),
    (v_ro,'НХТК','НХТК — Новосибирский химико-технологический колледж',true),
    (v_ro,'НКЛПиС','НКЛПиС — Новосибирский колледж лёгкой промышленности и сервиса',true)
  ON CONFLICT DO NOTHING;
END $$;

DO $$
DECLARE
  h_ngasu INTEGER; h_ngau INTEGER; h_ngmu INTEGER; h_ngpu INTEGER; h_ngtu INTEGER;
  h_ngu INTEGER; h_ngueu INTEGER; h_siu INTEGER; h_sguvt INTEGER; h_sgugit INTEGER;
  h_sgups INTEGER; h_sibguti INTEGER; h_sibupk INTEGER; h_ntjt INTEGER; h_nktt INTEGER;
  h_nmk INTEGER; h_npk1 INTEGER; h_nguadi INTEGER; h_nask INTEGER; h_nak INTEGER;
  h_nkpit INTEGER; h_nkssis INTEGER; h_ntek INTEGER; h_ntkp INTEGER; h_nkt INTEGER;
  h_npk INTEGER; h_nsmk INTEGER; h_ntgik INTEGER; h_nhtk INTEGER; h_nklpis INTEGER;
  d_sso INTEGER; d_spo INTEGER; d_sop INTEGER; d_sshho INTEGER; d_spuo INTEGER;
  d_smo INTEGER; d_sservo INTEGER;
BEGIN
  SELECT id INTO h_ngasu   FROM local_headquarters WHERE name='ШСО НГАСУ (Сибстрин)';
  SELECT id INTO h_ngau    FROM local_headquarters WHERE name='ШСО НГАУ';
  SELECT id INTO h_ngmu    FROM local_headquarters WHERE name='ШСО НГМУ';
  SELECT id INTO h_ngpu    FROM local_headquarters WHERE name='ШСО НГПУ';
  SELECT id INTO h_ngtu    FROM local_headquarters WHERE name='ШСО НГТУ';
  SELECT id INTO h_ngu     FROM local_headquarters WHERE name='ШСО НГУ';
  SELECT id INTO h_ngueu   FROM local_headquarters WHERE name='ШСО НГУЭУ';
  SELECT id INTO h_siu     FROM local_headquarters WHERE name='ШСО СИУ РАНХиГС';
  SELECT id INTO h_sguvt   FROM local_headquarters WHERE name='ШСО СГУВТ';
  SELECT id INTO h_sgugit  FROM local_headquarters WHERE name='ШСО СГУГиТ';
  SELECT id INTO h_sgups   FROM local_headquarters WHERE name='ШСО СГУПС';
  SELECT id INTO h_sibguti FROM local_headquarters WHERE name='ШСО СибГУТИ';
  SELECT id INTO h_sibupk  FROM local_headquarters WHERE name='ШСО СибУПК';
  SELECT id INTO h_ntjt    FROM local_headquarters WHERE name='НТЖТ';
  SELECT id INTO h_nktt    FROM local_headquarters WHERE name='НКТТ';
  SELECT id INTO h_nmk     FROM local_headquarters WHERE name='НМК';
  SELECT id INTO h_npk1    FROM local_headquarters WHERE name='НПК №1';
  SELECT id INTO h_nguadi  FROM local_headquarters WHERE name='НГУАДИ';
  SELECT id INTO h_nask    FROM local_headquarters WHERE name='НАСК';
  SELECT id INTO h_nak     FROM local_headquarters WHERE name='НАК';
  SELECT id INTO h_nkpit   FROM local_headquarters WHERE name='НКПиИТ';
  SELECT id INTO h_nkssis  FROM local_headquarters WHERE name='НКССиС';
  SELECT id INTO h_ntek    FROM local_headquarters WHERE name='НТЭК';
  SELECT id INTO h_ntkp    FROM local_headquarters WHERE name='НТКП';
  SELECT id INTO h_nkt     FROM local_headquarters WHERE name='НКТ им. А.Н. Косыгина';
  SELECT id INTO h_npk     FROM local_headquarters WHERE name='НПК';
  SELECT id INTO h_nsmk    FROM local_headquarters WHERE name='НСМК';
  SELECT id INTO h_ntgik   FROM local_headquarters WHERE name='НТГиК';
  SELECT id INTO h_nhtk    FROM local_headquarters WHERE name='НХТК';
  SELECT id INTO h_nklpis  FROM local_headquarters WHERE name='НКЛПиС';
  SELECT id INTO d_sso    FROM directions WHERE code='ССО';
  SELECT id INTO d_spo    FROM directions WHERE code='СПО';
  SELECT id INTO d_sop    FROM directions WHERE code='СОП';
  SELECT id INTO d_sshho  FROM directions WHERE code='ССхО';
  SELECT id INTO d_spuo   FROM directions WHERE code='СПуО';
  SELECT id INTO d_smo    FROM directions WHERE code='СМО';
  SELECT id INTO d_sservo FROM directions WHERE code='ССервО';

  -- НГАСУ
  INSERT INTO units(local_headquarters_id,direction_id,name) VALUES
    (h_ngasu,d_sop,'СОП «За Горизонтом»'),(h_ngasu,d_spo,'СПО «ВВЕРХ»'),
    (h_ngasu,d_sso,'ССО «Каскад»'),(h_ngasu,d_sso,'ССО «Азимут»'),
    (h_ngasu,d_sso,'ССО «ЖеНСКий двигатель»'),(h_ngasu,d_sso,'ССО «Сибстриновец»'),
    (h_ngasu,d_sso,'ССО «Конструкт»') ON CONFLICT DO NOTHING;
  -- НГАУ
  INSERT INTO units(local_headquarters_id,direction_id,name) VALUES
    (h_ngau,d_sop,'СОП «Молния»'),(h_ngau,d_sop,'СОП «Стихия»'),
    (h_ngau,d_spo,'СПО «Единство»'),(h_ngau,d_sservo,'ССервО «Маяк»'),
    (h_ngau,d_sso,'ССО «Ермак»'),(h_ngau,d_sshho,'ССхО «Летний Сад»'),
    (h_ngau,d_sshho,'ССхО «Механизаторы»'),(h_ngau,d_sshho,'ССхО «ВетСан»'),
    (h_ngau,d_spuo,'СПуО «Риф»') ON CONFLICT DO NOTHING;
  -- НГМУ
  INSERT INTO units(local_headquarters_id,direction_id,name) VALUES
    (h_ngmu,d_spo,'СПО «Атмосфера»'),(h_ngmu,d_smo,'СМО «Обезболь»'),
    (h_ngmu,d_smo,'СМО «Амальгама»'),(h_ngmu,d_smo,'СМО «Махаон»'),
    (h_ngmu,d_smo,'СМО «Эндорфин»'),(h_ngmu,d_smo,'СМО «Медкадры»'),
    (h_ngmu,d_sop,'СОП «Титан»') ON CONFLICT DO NOTHING;
  -- НГПУ
  INSERT INTO units(local_headquarters_id,direction_id,name) VALUES
    (h_ngpu,d_sop,'СОП «Аллегро»'),(h_ngpu,d_sop,'СОП «ВРейсе»'),
    (h_ngpu,d_sop,'СОП «Свои»'),(h_ngpu,d_sop,'СОП «Стриж»'),
    (h_ngpu,d_spo,'СПО «Спутники детства»'),(h_ngpu,d_spo,'СПО «Сапфир»'),
    (h_ngpu,d_spo,'СПО «32 августа»'),(h_ngpu,d_spo,'СПО «Сердце Сибири»'),
    (h_ngpu,d_spo,'СПО «Рассвет»'),(h_ngpu,d_sservo,'ССервО «Ритм»'),
    (h_ngpu,d_spo,'СПО «Рябина»'),(h_ngpu,d_sso,'ССО «Свобода»'),
    (h_ngpu,d_spo,'СПО «Юность»') ON CONFLICT DO NOTHING;
  -- НГТУ
  INSERT INTO units(local_headquarters_id,direction_id,name) VALUES
    (h_ngtu,d_sop,'СОП «Азарт»'),(h_ngtu,d_sop,'СОП «Индиго»'),
    (h_ngtu,d_sop,'СОП «Океан»'),(h_ngtu,d_sop,'СОП «Огни»'),
    (h_ngtu,d_sop,'СОП «Астерия»'),(h_ngtu,d_spo,'СПО «Бесконечное лето»'),
    (h_ngtu,d_spo,'СПО «Будущее время»'),(h_ngtu,d_spo,'СПО «Клевер»'),
    (h_ngtu,d_spo,'СПО «Колибри»'),(h_ngtu,d_sservo,'ССервО «Блеск»'),
    (h_ngtu,d_sso,'ССО «Заря»'),(h_ngtu,d_sso,'ССО «Импульс»'),
    (h_ngtu,d_sso,'ССО «Штурм»'),(h_ngtu,d_sso,'ССО «Квазар»'),
    (h_ngtu,d_sso,'ССО «Разряд»'),(h_ngtu,d_sso,'ССО «Энергия»'),
    (h_ngtu,d_sso,'ССО «Гелиос»') ON CONFLICT DO NOTHING;
  -- НГУ
  INSERT INTO units(local_headquarters_id,direction_id,name) VALUES
    (h_ngu,d_sop,'СОП «Синергия»'),(h_ngu,d_sso,'ССО «Золотое сечение»'),
    (h_ngu,d_spo,'СПО «Синтез»'),(h_ngu,d_smo,'СМО «Эвкалипт»'),
    (h_ngu,d_sservo,'ССервО «Н.Е.О.Н.»') ON CONFLICT DO NOTHING;
  -- НГУЭУ
  INSERT INTO units(local_headquarters_id,direction_id,name) VALUES
    (h_ngueu,d_sop,'СОП «Чайка»'),(h_ngueu,d_sop,'СОП «Форсаж»'),
    (h_ngueu,d_sop,'СОП «Ориентир»'),(h_ngueu,d_spo,'СПО «Жара»'),
    (h_ngueu,d_spo,'СПО «Альфа»'),(h_ngueu,d_spo,'СПО «Грация»'),
    (h_ngueu,d_sso,'ССО «Сибиряк»'),(h_ngueu,d_sservo,'ССервО «Ривьера»') ON CONFLICT DO NOTHING;
  -- СИУ РАНХиГС
  INSERT INTO units(local_headquarters_id,direction_id,name) VALUES
    (h_siu,d_spo,'СПО «Горящие сердца»'),(h_siu,d_spo,'СПО «Вега»'),
    (h_siu,d_sop,'СОП «Вектор»'),(h_siu,d_sop,'СОП «Магистраль»'),
    (h_siu,d_sservo,'ССервО «СибирьСервис»') ON CONFLICT DO NOTHING;
  -- СГУВТ
  INSERT INTO units(local_headquarters_id,direction_id,name) VALUES
    (h_sguvt,d_sop,'СОП «Ночной экспресс»'),(h_sguvt,d_spo,'СПО «Торнадо»'),
    (h_sguvt,d_sso,'ССО «Авангард»') ON CONFLICT DO NOTHING;
  -- СГУГиТ
  INSERT INTO units(local_headquarters_id,direction_id,name) VALUES
    (h_sgugit,d_sop,'СОП «Пункт Назначения»'),(h_sgugit,d_spo,'СПО «Созвездие»'),
    (h_sgugit,d_sservo,'ССервО «Атлантис»'),(h_sgugit,d_sso,'ССО «Корунд»') ON CONFLICT DO NOTHING;
  -- СГУПС
  INSERT INTO units(local_headquarters_id,direction_id,name) VALUES
    (h_sgups,d_sop,'СОП «Передовик»'),(h_sgups,d_sop,'СОП «Атланты»'),
    (h_sgups,d_sop,'СОП «Альтаир»'),(h_sgups,d_sop,'СОП «АРГО»'),
    (h_sgups,d_sop,'СОП «Стальной караван»'),(h_sgups,d_sop,'СОП «Улетный транспорт»'),
    (h_sgups,d_spo,'СПО «Эдельвейс»'),(h_sgups,d_sservo,'ССервО «Гарант»'),
    (h_sgups,d_sso,'ССО «54 регион»'),(h_sgups,d_sso,'ССО «Барс»'),
    (h_sgups,d_sso,'ССО «Стальная колея»'),(h_sgups,d_sso,'ССО «Эшелон»'),
    (h_sgups,d_sop,'СОП «Монолит»'),(h_sgups,d_sso,'ССО «Темп»'),
    (h_sgups,d_sso,'ССО «Путеец»'),(h_sgups,d_sso,'ССО «Высота»'),
    (h_sgups,d_sso,'ССО «Голиаф»') ON CONFLICT DO NOTHING;
  -- СибГУТИ
  INSERT INTO units(local_headquarters_id,direction_id,name) VALUES
    (h_sibguti,d_sop,'СОП «Меридиан»'),(h_sibguti,d_sop,'СОП «НонСтоп»'),
    (h_sibguti,d_spo,'СПО «Сияние»'),(h_sibguti,d_spo,'СПО «Эридан»'),
    (h_sibguti,d_sservo,'ССервО «Люкс»'),(h_sibguti,d_sso,'ССО «Связь»'),
    (h_sibguti,d_sso,'ССО «Династия»'),(h_sibguti,d_sservo,'ССервО «Матрица»') ON CONFLICT DO NOTHING;
  -- СибУПК
  INSERT INTO units(local_headquarters_id,direction_id,name) VALUES
    (h_sibupk,d_sservo,'ССервО «Профи-Сервис»'),(h_sibupk,d_sop,'СОП «Вокруг света»'),
    (h_sibupk,d_spo,'СПО «Искра»'),(h_sibupk,d_sservo,'ССервО «Лайм»'),
    (h_sibupk,d_sop,'СОП «Гермес»'),(h_sibupk,d_sservo,'ССервО «Фреш»') ON CONFLICT DO NOTHING;
  -- Колледжи
  INSERT INTO units(local_headquarters_id,direction_id,name) VALUES
    (h_ntjt,d_sop,'СОП «Кураж»'),(h_ntjt,d_sso,'ССО «Сибирский локомотив»'),(h_ntjt,d_sso,'ССО «Монтеры пути»'),
    (h_nktt,d_sop,'СОП «Эверест»'),
    (h_nmk,d_smo,'СМО «Милосердие»'),(h_nmk,d_smo,'СМО «Максимус»'),
    (h_npk1,d_spo,'СПО «Новаторы»'),
    (h_nguadi,d_spo,'СПО «Колорит»'),
    (h_nask,d_sso,'ССО «АРХиСТРОЙ»'),
    (h_nak,d_sop,'СОП «Железные ласточки»'),
    (h_nkpit,d_sop,'СОП «Мечта»'),
    (h_nkssis,d_sop,'СОП «Гранит»'),
    (h_ntek,d_sop,'СОП «Экономист»'),
    (h_ntkp,d_sservo,'ССервО «Вихрь»'),
    (h_nkt,d_sservo,'ССервО «Кооператив»'),
    (h_npk,d_sso,'ССО «Сварщики»'),
    (h_nsmk,d_sso,'ССО «Электромонтажник»'),(h_nsmk,d_sso,'ССО «Монтажник»'),
    (h_ntgik,d_sso,'ССО «Мидград»'),(h_ntgik,d_sso,'ССО «Базис»'),
    (h_nhtk,d_sso,'ССО «Феррум»'),
    (h_nklpis,d_sop,'СОП «Аврора»')
  ON CONFLICT DO NOTHING;
END $$;
