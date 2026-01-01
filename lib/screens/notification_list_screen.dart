import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/notification_provider.dart';
import '../providers/auth_provider.dart';

class NotificationListScreen extends StatefulWidget {
  const NotificationListScreen({super.key});

  @override
  State<NotificationListScreen> createState() => _NotificationListScreenState();
}

class _NotificationListScreenState extends State<NotificationListScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final user = context.read<AuthProvider>().currentUser?.username;
      context.read<NotificationProvider>().init(user);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Thông báo'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () =>
                context.read<NotificationProvider>().fetchNotifications(),
          ),
        ],
      ),
      body: Consumer<NotificationProvider>(
        builder: (context, provider, child) {
          if (provider.notifications.isEmpty) {
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.notifications_none, size: 64, color: Colors.grey),
                  SizedBox(height: 16),
                  Text(
                    'Chưa có thông báo nào',
                    style: TextStyle(color: Colors.grey),
                  ),
                ],
              ),
            );
          }

          return ListView.builder(
            itemCount: provider.notifications.length,
            itemBuilder: (context, index) {
              final item = provider.notifications[index];
              return _buildNotificationItem(item);
            },
          );
        },
      ),
    );
  }

  Widget _buildNotificationItem(dynamic item) {
    final type = item['type'] ?? 'INFO';
    final isRead = _isRead(item);
    final time = item['time'] ?? 'N/A';

    Color typeColor = Colors.blue;
    IconData typeIcon = Icons.info_outline;
    if (type == 'WARNING') {
      typeColor = Colors.orange;
      typeIcon = Icons.warning_amber_rounded;
    } else if (type == 'SUCCESS') {
      typeColor = Colors.green;
      typeIcon = Icons.check_circle_outline;
    } else if (type == 'RESOLVED') {
      typeColor = Colors.teal;
      typeIcon = Icons.verified_user_outlined;
    }

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      elevation: isRead ? 1 : 3,
      child: ListTile(
        leading: Icon(typeIcon, color: typeColor),
        title: Text(
          item['message'] ?? '',
          style: TextStyle(
            fontWeight: isRead ? FontWeight.normal : FontWeight.bold,
          ),
        ),
        subtitle: Text(time),
        onTap: () {
          if (!isRead) {
            context.read<NotificationProvider>().markAsRead(
              item['id'].toString(),
            );
          }
          // Handle specific actions if needed
        },
        trailing: isRead
            ? const Icon(Icons.check_circle, color: Colors.green, size: 16)
            : const Icon(Icons.circle, color: Colors.red, size: 12),
      ),
    );
  }

  bool _isRead(dynamic item) {
    final user = context.read<AuthProvider>().currentUser?.username;
    if (user == null) return true;
    final readBy = item['readBy'] as List? ?? [];
    return readBy.contains(user);
  }
}
