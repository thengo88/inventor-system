import 'package:flutter/material.dart';
import 'package:inventor/services/api_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SettingsProvider with ChangeNotifier {
  double _zoomLevel = 1.0;
  String _stockSource = 'anc-wms'; // 'anc-wms' or 'erp'

  double get zoomLevel => _zoomLevel;
  String get stockSource => _stockSource;

  SettingsProvider() {
    _loadSettings();
    fetchGlobalSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    _zoomLevel = prefs.getDouble('zoomLevel') ?? 1.0;
    notifyListeners();
  }

  Future<void> fetchGlobalSettings() async {
    try {
      final settings = await ApiService().getSystemSettings();
      if (settings.containsKey('stockSource')) {
        _stockSource = settings['stockSource'];
        notifyListeners();
      }
    } catch (e) {
      print('Fetch global settings error: $e');
    }
  }

  Future<void> setZoomLevel(double level) async {
    _zoomLevel = level;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('zoomLevel', level);
    notifyListeners();
  }

  Future<bool> setStockSource(String source) async {
    final success = await ApiService().updateSystemSetting(
      'stockSource',
      source,
    );
    if (success) {
      _stockSource = source;
      notifyListeners();
    }
    return success;
  }
}
