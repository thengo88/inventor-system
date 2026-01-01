import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/notification_provider.dart';
import '../providers/product_provider.dart';
import '../providers/picking_provider.dart';

class GlobalDataSync extends StatefulWidget {
  final Widget child;
  const GlobalDataSync({super.key, required this.child});

  @override
  State<GlobalDataSync> createState() => _GlobalDataSyncState();
}

class _GlobalDataSyncState extends State<GlobalDataSync> {
  int _lastUpdate = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Listen to NotificationProvider for system update signals
      // We use context.read because we are setting up a listener manually
      // avoiding a full rebuild of this widget tree just for logic trigger
      final notif = context.read<NotificationProvider>();
      notif.addListener(_onSystemUpdate);
    });
  }

  void _onSystemUpdate() {
    if (!mounted) return;
    final notif = context.read<NotificationProvider>();
    if (notif.lastSystemUpdate != _lastUpdate) {
      _lastUpdate = notif.lastSystemUpdate;
      _refreshAllData();
    }
  }

  void _refreshAllData() {
    debugPrint("[GlobalDataSync] Triggering global refresh...");
    try {
      // 1. Refresh Products & Stock
      context.read<ProductProvider>().fetchProducts();

      // 2. Refresh Picking Lists (silent to avoid full screen loader flicker if possible)
      // Note: silent=true parameter was added to PickingProvider
      context.read<PickingProvider>().fetchPickingLists(silent: true);

      // 3. Refresh Notifications explicitly (though socket handles it mostly)
      context.read<NotificationProvider>().fetchNotifications();
    } catch (e) {
      debugPrint("[GlobalDataSync] Error refreshing data: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}
