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

  EventsProvider({required ApiClient api}) : _api = api {
    // Загружаем события сразу при создании провайдера
    loadEvents();
  }

  List<EventItem> get events => _events;
  bool get isLoading => _isLoading;
  String? get error => _error;
  String get selectedType => _selectedType;

  void updateApiClient(ApiClient api) {
    _api = api;
    // Перезагружаем события при смене токена (после логина)
    loadEvents();
  }

  void updateToken(String? token) {
    _api.accessToken = token;
    // Перезагружаем чтобы обновить статус регистрации пользователя
    loadEvents();
  }

  Future<void> loadEvents() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      _events = await _api.events(
        type: _selectedType.isEmpty ? null : _selectedType,
        search: _searchQuery.isEmpty ? null : _searchQuery,
      );
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> refreshEvents() async {
    await loadEvents();
  }

  void setSearchQuery(String query) {
    _searchQuery = query;
    loadEvents();
  }

  void setTypeFilter(String type) {
    _selectedType = type;
    loadEvents();
  }

  // Обновить конкретное событие в списке после регистрации
  void updateEventRegistrationStatus(int eventId, String status) {
    final idx = _events.indexWhere((e) => e.id == eventId);
    if (idx == -1) return;
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
      participantsCount: old.participantsCount + 1,
      userRegistrationStatus: status,
    );
    notifyListeners();
  }
}