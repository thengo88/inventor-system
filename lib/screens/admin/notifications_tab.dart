import 'package:flutter/material.dart';
import '../../services/api_service.dart';

class NotificationsTab extends StatefulWidget {
  const NotificationsTab({super.key});

  @override
  State<NotificationsTab> createState() => _NotificationsTabState();
}

class _NotificationsTabState extends State<NotificationsTab> {
  final ApiService _apiService = ApiService();
  bool _isLoading = false;
  List<dynamic> _notifications = [];
  final TextEditingController _messageController = TextEditingController();
  String _selectedType = 'INFO';

  @override
  void initState() {
    super.initState();
    _loadNotifications();
  }

  Future<void> _loadNotifications() async {
    setState(() => _isLoading = true);
    try {
      // For Admin, we don't pass a user to get all notifications
      final response = await _apiService.getNotifications();
      setState(() => _notifications = response);
    } catch (e) {
      debugPrint('Load notifications error: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _sendNotification() async {
    final msg = _messageController.text.trim();
    if (msg.isEmpty) return;

    setState(() => _isLoading = true);
    try {
      final success = await _apiService.sendNotification(
        message: msg,
        type: _selectedType,
        sender: 'Admin',
        metadata: {'action': 'GENERAL_ANNOUNCEMENT'},
      );
      if (success) {
        _messageController.clear();
        _loadNotifications();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Đã gửi thông báo thành công')),
          );
        }
      }
    } catch (e) {
      debugPrint('Send notification error: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _deleteNotification(int id) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Xác nhận xóa'),
        content: const Text('Xóa thông báo này cho tất cả các thiết bị?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Hủy'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Xóa'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      setState(() => _isLoading = true);
      try {
        final success = await _apiService.hideNotifications([id], 'admin');
        if (success) {
          _loadNotifications();
        }
      } catch (e) {
        debugPrint('Delete notification error: $e');
      } finally {
        if (mounted) setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _buildSendSection(),
        const Divider(height: 1),
        Expanded(
          child: _isLoading && _notifications.isEmpty
              ? const Center(child: CircularProgressIndicator())
              : RefreshIndicator(
                  onRefresh: _loadNotifications,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: _notifications.length,
                    itemBuilder: (context, index) {
                      return _buildNotificationCard(_notifications[index]);
                    },
                  ),
                ),
        ),
      ],
    );
  }

  Widget _buildSendSection() {
    return Container(
      padding: const EdgeInsets.all(16),
      color: Colors.grey[50],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Gửi thông báo mới',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _messageController,
                  decoration: const InputDecoration(
                    hintText: 'Nhập nội dung thông báo...',
                    border: OutlineInputBorder(),
                    filled: true,
                    fillColor: Colors.white,
                  ),
                  maxLines: 2,
                ),
              ),
              const SizedBox(width: 12),
              Column(
                children: [
                  DropdownButton<String>(
                    value: _selectedType,
                    items: const [
                      DropdownMenuItem(value: 'INFO', child: Text('Thông tin')),
                      DropdownMenuItem(
                        value: 'WARNING',
                        child: Text('Cảnh báo'),
                      ),
                      DropdownMenuItem(
                        value: 'SUCCESS',
                        child: Text('Thành công'),
                      ),
                    ],
                    onChanged: (val) {
                      if (val != null) setState(() => _selectedType = val);
                    },
                  ),
                  ElevatedButton.icon(
                    onPressed: _isLoading ? null : _sendNotification,
                    icon: const Icon(Icons.send),
                    label: const Text('Gửi'),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 12,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildNotificationCard(dynamic item) {
    final type = item['type'] ?? 'INFO';
    final readBy = item['readBy'] as List? ?? [];

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
      margin: const EdgeInsets.only(bottom: 12),
      child: ExpansionTile(
        leading: Icon(typeIcon, color: typeColor),
        title: Text(
          item['message'] ?? '',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Text('Thời gian: ${item['time'] ?? 'N/A'}'),
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Divider(),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Ai đã đọc: (${readBy.length})',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_forever, color: Colors.red),
                      onPressed: () => _deleteNotification(item['id']),
                      tooltip: 'Xóa cho tất cả user',
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                if (readBy.isEmpty)
                  const Text(
                    'Chưa có ai đọc',
                    style: TextStyle(
                      color: Colors.grey,
                      fontStyle: FontStyle.italic,
                    ),
                  )
                else
                  Wrap(
                    spacing: 8,
                    children: readBy
                        .map(
                          (user) => Chip(
                            label: Text(user.toString()),
                            backgroundColor: Colors.blue[50],
                            avatar: const Icon(Icons.person, size: 16),
                            labelStyle: const TextStyle(fontSize: 12),
                          ),
                        )
                        .toList(),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
