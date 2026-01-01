import 'package:flutter/material.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;
import '../services/api_service.dart';

class NotificationProvider with ChangeNotifier {
  List<dynamic> _notifications = [];
  int _unreadCount = 0;
  IO.Socket? _socket;
  final ApiService _apiService = ApiService();
  String? _currentUser;

  List<dynamic> get notifications => _notifications;
  int get unreadCount => _unreadCount;

  void init(String? username) {
    if (username == null || username == _currentUser) return;
    _currentUser = username;
    _connectSocket();
    fetchNotifications();
  }

  int _lastSystemUpdate = 0;
  int get lastSystemUpdate => _lastSystemUpdate;

  void _connectSocket() {
    _socket?.disconnect();
    try {
      _socket = IO.io(_apiService.uploadUrl, <String, dynamic>{
        'transports': ['websocket'],
        'autoConnect': true,
        // Add extra options to ensure robust connection
        'reconnection': true,
        'reconnectionAttempts': double.infinity,
        'reconnectionDelay': 1000,
        'timeout': 20000,
      });

      _socket!.onConnect((_) {
        debugPrint('Socket connected: ${_socket?.id}');
      });

      _socket!.on('system_data_change', (data) {
        debugPrint('System data changed: $data');
        _lastSystemUpdate = DateTime.now().millisecondsSinceEpoch;
        notifyListeners(); // This will trigger UI rebuilds or listeners
      });

      _socket!.on('notification', (data) {
        if (data != null) {
          // Skip internal scan notifications
          if (data['message']?.toString().toLowerCase().startsWith(
                'new scan:',
              ) ==
              true)
            return;

          _notifications.insert(0, data);
          _calculateUnread();
          notifyListeners();
        }
      });

      _socket!.on('notification_update', (data) {
        if (data != null && data['id'] != null) {
          final index = _notifications.indexWhere(
            (n) => n['id'].toString() == data['id'].toString(),
          );
          if (index != -1) {
            bool shouldRemove = false;

            if (data['type'] == 'RESOLVED') {
              _notifications[index]['type'] = 'RESOLVED';
              if (data['message'] != null)
                _notifications[index]['message'] = data['message'];
              if (data['metadata'] != null)
                _notifications[index]['metadata'] = data['metadata'];
            } else if (data['readBy'] != null) {
              _notifications[index]['readBy'] = data['readBy'];

              // EXCLUSIVE CLAIMING for WARNING
              final String nType = (_notifications[index]['type'] ?? '')
                  .toString()
                  .toUpperCase();
              if (nType == 'WARNING') {
                final List readers = data['readBy'] ?? [];
                if (readers.isNotEmpty &&
                    _currentUser != null &&
                    !readers.contains(_currentUser)) {
                  debugPrint(
                    "Notification ${data['id']} claimed by ${readers[0]}. Removing for $_currentUser.",
                  );
                  shouldRemove = true;
                }
              }
            }

            if (shouldRemove) {
              _notifications.removeAt(index);
            }

            _calculateUnread();
            notifyListeners();
          }
        }
      });

      _socket!.on('notifications_deleted', (data) {
        if (data != null && data['ids'] is List) {
          final List ids = data['ids'];
          _notifications.removeWhere((n) => ids.contains(n['id']));
          _calculateUnread();
          notifyListeners();
        }
      });
    } catch (e) {
      debugPrint("Socket connection error: $e");
    }
  }

  Future<void> fetchNotifications() async {
    if (_currentUser == null) return;
    try {
      final data = await _apiService.getNotifications(user: _currentUser);
      _notifications = data;
      _calculateUnread();
      notifyListeners();
    } catch (e) {
      debugPrint("Fetch notifications error: $e");
    }
  }

  void _calculateUnread() {
    if (_currentUser == null) {
      _unreadCount = 0;
      return;
    }
    _unreadCount = _notifications.where((n) {
      final readBy = n['readBy'] as List?;
      return readBy == null || !readBy.contains(_currentUser);
    }).length;
  }

  Future<bool> markAsRead(String id) async {
    if (_currentUser == null) return false;
    final success = await _apiService.markNotificationRead(id, _currentUser!);
    if (success) {
      final index = _notifications.indexWhere((n) => n['id'].toString() == id);
      if (index != -1) {
        final List readBy = List.from(_notifications[index]['readBy'] ?? []);
        if (!readBy.contains(_currentUser)) {
          readBy.add(_currentUser!);
          _notifications[index]['readBy'] = readBy;
          _calculateUnread();
          notifyListeners();
        }
      }
    }
    return success;
  }

  Future<void> resolveNotification(int id, String user, String note) async {
    final success = await _apiService.resolveNotification(id, user, note);
    if (success) {
      // Logic handled via socket: notification_update (RESOLVED)
    }
  }

  Future<void> deleteNotifications(List<int> ids) async {
    if (_currentUser == null) return;
    final success = await _apiService.hideNotifications(ids, _currentUser!);
    if (success) {
      _notifications.removeWhere((n) => ids.contains(n['id']));
      _calculateUnread();
      notifyListeners();
    }
  }

  Future<void> deleteNotificationsGlobal(List<int> ids) async {
    final success = await _apiService.deleteNotificationsGlobal(ids);
    if (success) {
      // Sockets will normally handle the removal, but we can do it locally too
      _notifications.removeWhere((n) => ids.contains(n['id']));
      _calculateUnread();
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _socket?.disconnect();
    super.dispose();
  }
}
