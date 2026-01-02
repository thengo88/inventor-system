import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/notification_provider.dart';
import '../providers/product_provider.dart';
import '../providers/picking_provider.dart';
import '../providers/settings_provider.dart';

class GlobalDataSync extends StatefulWidget {
  final Widget child;
  const GlobalDataSync({super.key, required this.child});

  static final StreamController<String> _refreshController =
      StreamController<String>.broadcast();
  static Stream<String> get onRefresh => _refreshController.stream;

  @override
  State<GlobalDataSync> createState() => _GlobalDataSyncState();
}

class _GlobalDataSyncState extends State<GlobalDataSync> {
  int _lastUpdate = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final notif = context.read<NotificationProvider>();
      notif.addListener(_onSystemUpdate);
    });
  }

  void _onSystemUpdate() {
    if (!mounted) return;
    final notif = context.read<NotificationProvider>();
    if (notif.lastSystemUpdate != _lastUpdate) {
      _lastUpdate = notif.lastSystemUpdate;
      _refreshAllData(notif.lastChangeCategory);
    }
  }

  void _refreshAllData(String category) {
    debugPrint(
      "[GlobalDataSync] Triggering global refresh for category: $category",
    );
    try {
      // 1. Refresh Products & Stock (Common for many actions)
      context.read<ProductProvider>().fetchProducts();

      // 2. Refresh Picking Lists
      context.read<PickingProvider>().fetchPickingLists(silent: true);

      // 3. Refresh Notifications
      context.read<NotificationProvider>().fetchNotifications();

      // 4. Refresh Settings (in case config changed)
      context.read<SettingsProvider>().fetchGlobalSettings();

      // 5. Broadcast to all listeners (Screens like PickingDetail, StockAudit, etc.)
      GlobalDataSync._refreshController.add(category);
    } catch (e) {
      debugPrint("[GlobalDataSync] Error refreshing data: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}
