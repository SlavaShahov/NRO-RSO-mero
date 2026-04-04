# RSO Events (API + Mobile)

Реализация на основе ТЗ `ТЗ_РСО_Мероприятия_v1.1_полное.docx`:

- JWT-аутентификация (регистрация/вход)
- RBAC на основе ролей (`system_roles` + `unit_positions`)
- Лента мероприятий с фильтрами
- Регистрация на мероприятие с выдачей UUID для QR
- Отметка посещаемости через скан QR (для управляющих ролей)
- Портфолио участника (предстоящие/посещенные)
- PostgreSQL-схема: MVP + расширение до полной нормализованной модели (23 таблицы)
- Запуск через `docker compose`
- OpenAPI спецификация: `openapi.yaml`
- Postman коллекция: `postman_collection.json`
- Flutter-клиент MVP: `mobile_app/`

## Быстрый старт

```bash
docker compose up --build
```

После запуска:

- API: `http://localhost:8080`
- Health: `GET /healthz`
- Swagger UI: `http://localhost:8081`

## Полный план запуска

### 1) Подготовка окружения

- Установить `Docker Desktop` (с включенным `docker compose`)
- Установить `Flutter SDK` (для mobile части)
- Для Android: установить `Android Studio` + эмулятор

Проверка:

```bash
docker --version
docker compose version
flutter --version
```

### 2) Запуск backend + БД + Swagger

Из корня проекта:

```bash
docker compose up --build -d
```

Проверить состояние контейнеров:

```bash
docker compose ps
```

Проверить логи (если что-то не стартовало):

```bash
docker compose logs -f api
docker compose logs -f migrate
docker compose logs -f postgres
docker compose logs -f swagger-ui
docker compose logs -f cleanup
```

### 3) Проверка работоспособности API

- API: [http://localhost:8080](http://localhost:8080)
- Health: [http://localhost:8080/healthz](http://localhost:8080/healthz)
- Swagger UI: [http://localhost:8081](http://localhost:8081)

Быстрая проверка в консоли:

```bash
curl http://localhost:8080/healthz
```

Ожидаемо:

```json
{"status":"ok"}
```

### 4) Запуск мобильного приложения (Flutter)

```bash
cd mobile_app
flutter pub get
flutter run
```

Адрес API в приложении:

- Android Emulator: `http://10.0.2.2:8080`
- iOS Simulator: `http://localhost:8080`
- Реальный телефон: `http://<IP_вашего_ПК>:8080` (ПК и телефон в одной сети)

### 5) Первый сценарий теста

1. Открыть приложение
2. Нажать `Register` (или `Login`)
3. Убедиться, что загрузилась лента событий
4. Нажать `Go` на событии -> получить `QR` в snackbar
5. Открыть профиль -> проверить статистику портфолио

### 6) Остановка/перезапуск

Остановить все сервисы:

```bash
docker compose down
```

Полная очистка (включая volume БД):

```bash
docker compose down -v
```

Пересборка после изменений:

```bash
docker compose up --build -d
```

### 7) Типичные проблемы

- **Порт занят**: освободить `8080/8081/5432` или изменить `ports` в `docker-compose.yml`
- **Миграции не применились**: `docker compose logs migrate`
- **Flutter не видит API**: проверить URL для платформы (`10.0.2.2` для Android эмулятора)
- **Токен “протух”**: заново `Login` или использовать `POST /api/v1/auth/refresh`

## Основные endpoint'ы

- `POST /api/v1/auth/register`
- `POST /api/v1/auth/login`
- `POST /api/v1/auth/refresh`
- `POST /api/v1/auth/logout` (Bearer token)
- `GET /api/v1/events?level=regional&type=education&search=слёт`
- `GET /api/v1/me` (Bearer token)
- `GET /api/v1/portfolio` (Bearer token)
- `POST /api/v1/events/{eventID}/register` (Bearer token)
- `POST /api/v1/attendance/scan` (Bearer token, роль менеджера)

## Примеры запросов

Регистрация:

```bash
curl -X POST http://localhost:8080/api/v1/auth/register \
  -H "Content-Type: application/json" \
  -d '{
    "email":"fighter1@example.com",
    "password":"qwerty123",
    "last_name":"Иванов",
    "first_name":"Иван"
  }'
```

Вход:

```bash
curl -X POST http://localhost:8080/api/v1/auth/login \
  -H "Content-Type: application/json" \
  -d '{"email":"fighter1@example.com","password":"qwerty123"}'
```

Лента мероприятий:

```bash
curl http://localhost:8080/api/v1/events
```

Регистрация на мероприятие:

```bash
curl -X POST http://localhost:8080/api/v1/events/1/register \
  -H "Authorization: Bearer <ACCESS_TOKEN>"
```

Отметка посещения:

```bash
curl -X POST http://localhost:8080/api/v1/attendance/scan \
  -H "Authorization: Bearer <ACCESS_TOKEN_OF_MANAGER>" \
  -H "Content-Type: application/json" \
  -d '{"qr_code":"<UUID_FROM_REGISTRATION>"}'
```

## Структура проекта

- `cmd/api/main.go` — точка входа
- `internal/repo` — доступ к БД
- `internal/service` — бизнес-логика
- `internal/http` — HTTP handlers
- `migrations/*.sql` — схема БД и демо-данные
- `docker-compose.yml` — подъем Postgres, мигратора и API
- `Dockerfile` — сборка/рантайм API
- `openapi.yaml` — Swagger/OpenAPI
- `postman_collection.json` — Postman requests
- `mobile_app` — Flutter клиент

## Что покрыто относительно ТЗ

Покрыт MVP раздела релиза из ТЗ (`регистрация/авторизация`, `лента мероприятий`, `QR`, `отметка посещения`) + расширенная схема данных из приложения Б, подготовка для следующих модулей (уведомления, файлы, аудит, история должностей).

## Mobile (Flutter)

```bash
cd mobile_app
flutter pub get
flutter run
```

По умолчанию Android-эмулятор использует API по адресу `http://10.0.2.2:8080`.

## Revoked tokens persistence

Blacklist токенов сохраняется в PostgreSQL в таблице `revoked_tokens`, поэтому revocation работает после перезапуска API-контейнера.

Очистка истекших записей выполняется отдельным контейнером `cleanup` (каждые 5 минут).
