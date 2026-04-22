import 'package:flutter/material.dart';
import '../models/event.dart';
import '../services/api_client.dart';

class EventsProvider extends ChangeNotifier {
  ApiClient _api;
  List<EventItem> _events = [];
  bool _isLoading = false;
  String? _error;
  String _searchQuery = '';
  String _selectedType = '';
  String? _lastToken;

  // Счётчик регистраций — увеличивается при каждой новой регистрации.
  // ProfileScreen следит за этим числом и перезагружает свои данные.
  int _registrationCounter = 0;

  EventsProvider({required ApiClient api}) : _api = api {
    loadEvents();
  }

  List<EventItem> get events => _events;
  bool get isLoading => _isLoading;
  String? get error => _error;
  String get selectedType => _selectedType;
  int get registrationCounter => _registrationCounter;

  void updateApiClient(ApiClient api) {
    _api = api;
    loadEvents();
  }

  void updateToken(String? token) {
    _api.accessToken = token;
    if (token == _lastToken) return;
    _lastToken = token;
    loadEvents();
  }

  Future<void> loadEvents() async {
    _isLoading = true;
    _error = null;
    notifyListeners();
    try {
      final fresh = await _api.events(
        type:   _selectedType.isEmpty ? null : _selectedType,
        search: _searchQuery.isEmpty  ? null : _searchQuery,
      );
      // ВАЖНО: при перезагрузке сохраняем статус регистрации из памяти
      // на случай если сервер ещё не вернул обновлённый статус (гонка)
      final merged = fresh.map((e) {
        final existing = _events.firstWhere(
              (old) => old.id == e.id,
          orElse: () => e,
        );
        // Если в памяти статус «registered/attended» а с сервера null —
        // сохраняем локальный статус (пользователь только что зарегистрировался)
        if (existing.userRegistrationStatus != null &&
            e.userRegistrationStatus == null) {
          return EventItem(
            id: e.id,
            title: e.title,
            description: e.description,
            eventDate: e.eventDate,
            startTime: e.startTime,
            endTime: e.endTime,
            location: e.location,
            levelCode: e.levelCode,
            typeCode: e.typeCode,
            statusCode: e.statusCode,
            isRegistrationRequired: e.isRegistrationRequired,
            maxParticipants: e.maxParticipants,
            participantsCount: e.participantsCount,
            userRegistrationStatus: existing.userRegistrationStatus,
          );
        }
        return e;
      }).toList();
      _events = merged;
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> refreshEvents() async => loadEvents();

  void setSearchQuery(String query) {
    _searchQuery = query;
    loadEvents();
  }

  void setTypeFilter(String type) {
    _selectedType = type;
    loadEvents();
  }

  /// Вызывается после успешной регистрации на мероприятие.
  /// Обновляет статус в памяти и увеличивает счётчик —
  /// ProfileScreen реагирует на счётчик и перезагружает регистрации.
  void updateEventRegistrationStatus(int eventId, String status) {
    final idx = _events.indexWhere((e) => e.id == eventId);
    if (idx != -1) {
      final old = _events[idx];
      _events[idx] = EventItem(
        id: old.id,
        title: old.title,
        description: old.description,
        eventDate: old.eventDate,
        startTime: old.startTime,
        endTime: old.endTime,
        location: old.location,
        levelCode: old.levelCode,
        typeCode: old.typeCode,
        statusCode: old.statusCode,
        isRegistrationRequired: old.isRegistrationRequired,
        maxParticipants: old.maxParticipants,
        participantsCount: status == 'registered'
            ? old.participantsCount + 1
            : old.participantsCount,
        userRegistrationStatus: status,
      );
    }
    // Увеличиваем счётчик — ProfileScreen подхватит изменение
    _registrationCounter++;
    notifyListeners();
    // Перезагружаем с сервера чтобы счётчик участников был актуальным
    Future.delayed(const Duration(milliseconds: 500), loadEvents);
  }
}