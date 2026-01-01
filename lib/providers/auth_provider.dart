
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/user.dart';
import '../models/log_entry.dart';
import '../services/api_service.dart';

class AuthProvider with ChangeNotifier {
  User? _currentUser;
  final ApiService _apiService = ApiService();

  User? get currentUser => _currentUser;
  bool get isAdmin => _currentUser?.role == UserRole.admin;

  Future<bool> login(String username, String password) async {
    final userData = await _apiService.login(username, password);
    if (userData != null) {
      _currentUser = User.fromMap(userData);
      
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('username', username);
      
      await logAction('Đăng nhập', 'Người dùng đăng nhập từ Client');
      notifyListeners();
      return true;
    }
    return false;
  }

  Future<void> logout() async {
    if (_currentUser != null) {
      await logAction('Đăng xuất', 'Người dùng thoát ứng dụng');
    }
    _currentUser = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('username');
    notifyListeners();
  }

  Future<void> logAction(String action, String details) async {
    if (_currentUser != null) {
      await _apiService.addLog(LogEntry(
        username: _currentUser!.username,
        action: action,
        details: details,
        timestamp: DateTime.now(),
      ));
    }
  }

  // User Management for Admin
  List<User> _allUsers = [];
  List<User> get allUsers => _allUsers;

  Future<void> refreshCurrentUser() async {
    if (_currentUser == null) return;
    try {
      final updatedUser = await _apiService.getCurrentUser(_currentUser!.username);
      if (updatedUser != null) {
        _currentUser = updatedUser;
        notifyListeners();
      }
    } catch (e) {
      print('Refresh user error: $e');
    }
  }

  Future<void> fetchAllUsers() async {
    if (!isAdmin) return;
    _allUsers = await _apiService.getUsers();
    notifyListeners();
  }

  Future<void> createUser(User user) async {
    final success = await _apiService.addUser(user);
    if (success) {
      await logAction('Tạo User', 'Đã thêm người dùng mới: ${user.username}');
      await fetchAllUsers();
    }
  }

  Future<void> removeUser(int id, String username) async {
    final success = await _apiService.deleteUser(id);
    if (success) {
      await logAction('Xóa User', 'Đã xóa người dùng: $username');
      await fetchAllUsers();
    }
  }

  Future<void> editUser(int id, String username, String? password, UserRole role, {
    String? recs, 
    String? typs, 
    String? ps, 
    String? oprs,
    String? tr,
    String? gate,
    String? line,
    String? zone,
    String? box,
  }) async {
    final success = await _apiService.updateUser(
      id, 
      password: password, 
      role: role.name,
      assignedRecs: recs,
      assignedTyps: typs,
      assignedPs: ps,
      assignedOprs: oprs,
      assignedTr: tr,
      assignedGate: gate,
      assignedLine: line,
      assignedZone: zone,
      assignedBox: box,
    );
    if (success) {
      await logAction('Sửa User', 'Đã cập nhật thông tin người dùng: $username');
      await fetchAllUsers();
    }
  }

  // Logs for Admin
  List<LogEntry> _logs = [];
  List<LogEntry> get logs => _logs;

  Future<void> fetchLogs() async {
    if (!isAdmin) return;
    _logs = await _apiService.getLogs();
    notifyListeners();
  }

  Future<void> removeLog(int id) async {
    final success = await _apiService.deleteLog(id);
    if (success) {
      _logs.removeWhere((l) => l.id == id);
      notifyListeners();
    }
  }

  Future<void> removeMultipleLogs(List<int> ids) async {
    final success = await _apiService.deleteMultipleLogs(ids);
    if (success) {
      _logs.removeWhere((l) => ids.contains(l.id));
      notifyListeners();
    }
  }

  Future<void> clearLogs() async {
    final success = await _apiService.deleteAllLogs();
    if (success) {
      _logs = [];
      notifyListeners();
    }
  }
}
