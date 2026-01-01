import 'dart:math';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import 'scan_screen.dart';
import 'admin/admin_screen.dart';
import 'login_screen.dart';
import 'picking_screen.dart';
import 'stock_audit_screen.dart' hide Container, SizedBox, Center;
import 'admin/picking_history_screen.dart';
import 'admin/assignment_progress_screen.dart';
import '../widgets/date_header_widget.dart';
import '../providers/notification_provider.dart';
import '../providers/settings_provider.dart';
import 'notification_list_screen.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'app_info_screen.dart';
import 'anc_wms_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    WakelockPlus.enable(); // Force stay awake on home screen
    final auth = context.watch<AuthProvider>();
    final user = auth.currentUser;
    final notifications = context.watch<NotificationProvider>();

    // Initial load
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (user != null) {
        context.read<NotificationProvider>().init(user.username);
      }
    });

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'SMART INVENTORY',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            letterSpacing: 1.5,
            shadows: [
              Shadow(
                color: Colors.black.withOpacity(0.5),
                offset: const Offset(2, 2),
                blurRadius: 4,
              ),
            ],
          ),
        ),
        centerTitle: true,
      ),
      drawer: Drawer(
        child: SingleChildScrollView(
          child: Column(
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.only(top: 60, bottom: 30),
                decoration: BoxDecoration(
                  color: Theme.of(context).primaryColor,
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Theme.of(context).primaryColor,
                      Theme.of(context).primaryColor.withOpacity(0.8),
                    ],
                  ),
                ),
                child: Column(
                  children: [
                    const CircleAvatar(
                      radius: 40,
                      backgroundColor: Colors.white,
                      child: Icon(Icons.person, size: 50, color: Colors.blue),
                    ),
                    const SizedBox(height: 15),
                    Text(
                      user?.username ?? 'Người dùng',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        auth.isAdmin ? 'Quản trị viên' : 'Nhân viên',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    if (!auth.isAdmin &&
                        ((user?.assignedRecs?.isNotEmpty ?? false) ||
                            (user?.assignedPs?.isNotEmpty ?? false) ||
                            (user?.assignedOprs?.isNotEmpty ?? false))) ...[
                      const SizedBox(height: 12),
                      const Text(
                        'NHIỆM VỤ ĐƯỢC GIAO:',
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: Wrap(
                          alignment: WrapAlignment.center,
                          spacing: 6,
                          runSpacing: 4,
                          children: [
                            if (user?.assignedRecs?.isNotEmpty ?? false)
                              _buildDrawerTag(
                                'REC: ${user!.assignedRecs}',
                                Colors.purple,
                              ),
                            if (user?.assignedPs?.isNotEmpty ?? false)
                              _buildDrawerTag(
                                'PS: ${user!.assignedPs}',
                                Colors.green,
                              ),
                            if (user?.assignedOprs?.isNotEmpty ?? false)
                              _buildDrawerTag(
                                'OPR: ${user!.assignedOprs}',
                                Colors.orange,
                              ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              ListTile(
                leading: const Icon(Icons.qr_code_scanner),
                title: const Text('Nhập kho'),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const ScanScreen()),
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.checklist_rtl),
                title: const Text('Soạn hàng'),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const PickingScreen()),
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.inventory),
                title: const Text('Kiểm kê kho'),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const StockAuditScreen()),
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.history_edu),
                title: const Text('Lịch sử soạn hàng'),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const PickingHistoryScreen(),
                    ),
                  );
                },
              ),
              if (auth.isAdmin) ...[
                const Divider(),
                const Padding(
                  padding: EdgeInsets.only(left: 16, top: 8, bottom: 8),
                  child: Text(
                    'QUẢN TRỊ',
                    style: TextStyle(
                      color: Colors.grey,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.assignment_ind_outlined),
                  title: const Text('Danh sách chỉ định'),
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const AssignmentProgressScreen(),
                      ),
                    );
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.admin_panel_settings),
                  title: const Text('Bảng Quản trị'),
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const AdminScreen()),
                    );
                  },
                ),
              ],
              const Divider(),
              ListTile(
                leading: const Icon(Icons.info_outline, color: Colors.blueGrey),
                title: const Text('Thông tin ứng dụng'),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const AppInfoScreen()),
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.logout, color: Colors.red),
                title: const Text(
                  'Đăng xuất',
                  style: TextStyle(color: Colors.red),
                ),
                onTap: () {
                  auth.logout();
                  Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(builder: (_) => const LoginScreen()),
                  );
                },
              ),
              const Divider(),
              const Padding(
                padding: EdgeInsets.only(left: 16, top: 8),
                child: Text(
                  'THIẾT LẬP GIAO DIỆN',
                  style: TextStyle(
                    color: Colors.grey,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              Consumer<SettingsProvider>(
                builder: (context, settings, _) {
                  return Column(
                    children: [
                      ListTile(
                        leading: const Icon(Icons.zoom_in),
                        title: const Text('Phóng to giao diện'),
                        subtitle: Text(
                          'Cấp độ: ${(settings.zoomLevel * 100).toStringAsFixed(0)}%',
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.remove,
                              size: 16,
                              color: Colors.grey,
                            ),
                            Expanded(
                              child: Slider(
                                value: settings.zoomLevel,
                                min: 0.8,
                                max: 2.5,
                                divisions: 17, // (2.5 - 0.8) / 0.1 = 17
                                onChanged: (val) {
                                  settings.setZoomLevel(val);
                                },
                              ),
                            ),
                            const Icon(Icons.add, size: 16, color: Colors.grey),
                          ],
                        ),
                      ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Theme.of(context).colorScheme.primary.withOpacity(0.05),
              Theme.of(context).colorScheme.surface,
            ],
          ),
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 20),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      if (constraints.maxWidth < 700) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Xin chào, ${user?.username ?? "Người dùng"}',
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodyLarge
                                          ?.copyWith(
                                            color: Theme.of(
                                              context,
                                            ).colorScheme.primary,
                                            fontWeight: FontWeight.bold,
                                          ),
                                    ),
                                    Text(
                                      '${auth.isAdmin ? "Quản trị viên" : "Nhân viên"} hệ thống',
                                      style: TextStyle(
                                        color: Colors.grey[600],
                                        fontSize: 13,
                                      ),
                                    ),
                                  ],
                                ),
                                GestureDetector(
                                  onTap: () => Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) =>
                                          const NotificationListScreen(),
                                    ),
                                  ),
                                  child: Badge(
                                    isLabelVisible:
                                        notifications.unreadCount > 0,
                                    label: Text(
                                      notifications.unreadCount.toString(),
                                    ),
                                    child: CircleAvatar(
                                      backgroundColor: Theme.of(
                                        context,
                                      ).primaryColor.withOpacity(0.1),
                                      child: Icon(
                                        Icons.person_rounded,
                                        color: Theme.of(context).primaryColor,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            const Center(child: DateHeaderWidget()),
                          ],
                        );
                      } else {
                        return Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Xin chào, ${user?.username ?? "Người dùng"}',
                                    style: Theme.of(context).textTheme.bodyLarge
                                        ?.copyWith(
                                          color: Theme.of(
                                            context,
                                          ).colorScheme.primary,
                                          fontWeight: FontWeight.bold,
                                        ),
                                  ),
                                  Text(
                                    '${auth.isAdmin ? "Quản trị viên" : "Nhân viên"} hệ thống',
                                    style: TextStyle(
                                      color: Colors.grey[600],
                                      fontSize: 13,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 16),
                            const DateHeaderWidget(),
                          ],
                        );
                      }
                    },
                  ),
                  const SizedBox(height: 20),
                  // Khung châm ngôn nổi bật ở giữa
                  Center(child: _buildQuoteBox(context)),
                  const SizedBox(height: 32),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final zoom = context.watch<SettingsProvider>().zoomLevel;
                      int crossAxisCount = constraints.maxWidth > 900
                          ? 3
                          : constraints.maxWidth > 600
                          ? 2
                          : 1;

                      // Adjust aspect ratio based on zoom to prevent text overflow
                      double baseAspectRatio = constraints.maxWidth > 900
                          ? 1.5
                          : constraints.maxWidth > 600
                          ? 1.8
                          : 2.8;

                      // As zoom increases, we need more height (smaller aspect ratio)
                      double childAspectRatio =
                          baseAspectRatio /
                          (zoom > 1.0 ? (1.0 + (zoom - 1.0) * 1.5) : 1.0);

                      if (crossAxisCount > 1) {
                        return GridView.count(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          crossAxisCount: crossAxisCount,
                          crossAxisSpacing: 16,
                          mainAxisSpacing: 0,
                          childAspectRatio: childAspectRatio,
                          children: [
                            _buildActionCard(
                              context,
                              title: 'ANC-WMS',
                              subtitle: 'Quản lý kho & Tồn kho',
                              icon: Icons.warehouse_rounded,
                              color: Colors.purple,
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => const AncWmsScreen(),
                                  ),
                                );
                              },
                            ),
                            _buildActionCard(
                              context,
                              title: 'Soạn hàng',
                              subtitle: 'Thực hiện lấy hàng theo đơn',
                              icon: Icons.checklist_rtl_rounded,
                              color: Colors.orange,
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => const PickingScreen(),
                                  ),
                                );
                              },
                            ),
                            _buildActionCard(
                              context,
                              title: 'Kiểm kê kho',
                              subtitle: 'Tính toán và lưu dữ liệu tồn kho',
                              icon: Icons.inventory_outlined,
                              color: Colors.teal,
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => const StockAuditScreen(),
                                  ),
                                );
                              },
                            ),
                            if (auth.isAdmin)
                              _buildActionCard(
                                context,
                                title: 'Bảng Quản trị',
                                subtitle: 'Sản phẩm, Nhân viên & Nhật ký',
                                icon: Icons.admin_panel_settings_rounded,
                                color: Colors.indigo[400]!,
                                onTap: () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => const AdminScreen(),
                                  ),
                                ),
                              ),
                          ],
                        );
                      } else {
                        return Column(
                          children: [
                            _buildActionCard(
                              context,
                              title: 'ANC-WMS',
                              subtitle: 'Quản lý kho & Tồn kho',
                              icon: Icons.warehouse_rounded,
                              color: Colors.purple,
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => const AncWmsScreen(),
                                  ),
                                );
                              },
                            ),
                            _buildActionCard(
                              context,
                              title: 'Soạn hàng',
                              subtitle: 'Thực hiện lấy hàng theo đơn',
                              icon: Icons.checklist_rtl_rounded,
                              color: Colors.orange,
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => const PickingScreen(),
                                  ),
                                );
                              },
                            ),
                            _buildActionCard(
                              context,
                              title: 'Kiểm kê kho',
                              subtitle: 'Tính toán và lưu dữ liệu tồn kho',
                              icon: Icons.inventory_outlined,
                              color: Colors.teal,
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => const StockAuditScreen(),
                                  ),
                                );
                              },
                            ),
                            if (auth.isAdmin) ...[
                              _buildActionCard(
                                context,
                                title: 'Bảng Quản trị',
                                subtitle: 'Sản phẩm, Nhân viên & Nhật ký',
                                icon: Icons.admin_panel_settings_rounded,
                                color: Colors.indigo[400]!,
                                onTap: () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => const AdminScreen(),
                                  ),
                                ),
                              ),
                            ],
                          ],
                        );
                      }
                    },
                  ),
                  const SizedBox(height: 30),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildQuoteBox(BuildContext context) {
    final List<String> quotes = [
      "Thành công không phải là chìa khóa mở cửa hạnh phúc. Hạnh phúc mới là chìa khóa dẫn tới thành công.",
      "Đừng đợi cơ hội tự đến, hãy tự tạo ra nó.",
      "Hành trình ngàn dặm bắt đầu từ một bước chân nhỏ bé.",
      "Làm việc bằng cả trái tim, bạn sẽ thấy sự khác biệt.",
      "Mọi khó khăn đều mang trong mình hạt giống của sự thành công.",
      "Hãy làm những việc hôm nay để ngày mai bạn biết ơn chính mình.",
      "Kỷ luật là cầu nối giữa mục tiêu và thành tựu.",
      "Thái độ của bạn sẽ quyết định độ cao của bạn.",
      "Đam mê là ngọn lửa dẫn lối đến thành công.",
      "Hãy sống như thể hôm nay là ngày cuối cùng của bạn.",
    ];
    final String quote = quotes[Random().nextInt(quotes.length)];

    return Container(
      constraints: const BoxConstraints(maxWidth: 500),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            margin: const EdgeInsets.only(top: 15, right: 15),
            padding: const EdgeInsets.fromLTRB(25, 30, 25, 25),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Colors.white,
                  Theme.of(context).primaryColor.withOpacity(0.15),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(40),
                bottomLeft: Radius.circular(40),
                bottomRight: Radius.circular(40),
                topRight: Radius.circular(10),
              ),
              border: Border.all(
                color: Theme.of(context).primaryColor.withOpacity(0.5),
                width: 2,
              ),
              boxShadow: [
                BoxShadow(
                  color: Theme.of(context).primaryColor.withOpacity(0.25),
                  blurRadius: 30,
                  offset: const Offset(0, 15),
                  spreadRadius: 2,
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  quote,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.quicksand(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    fontStyle: FontStyle.italic,
                    color: Colors
                        .teal[800], // Dark Teal for high contrast but stylish
                    height: 1.5,
                    letterSpacing: 0.3,
                  ),
                ),
                const SizedBox(height: 15),
                Container(
                  width: 60,
                  height: 4,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Theme.of(context).primaryColor,
                        Colors.tealAccent,
                      ],
                    ),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ],
            ),
          ),
          Positioned(
            top: 0,
            right: 0,
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Theme.of(context).primaryColor,
                    Theme.of(context).primaryColor.withOpacity(0.8),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 4),
                boxShadow: [
                  BoxShadow(
                    color: Theme.of(context).primaryColor.withOpacity(0.5),
                    blurRadius: 15,
                    offset: const Offset(0, 5),
                  ),
                ],
              ),
              child: const Icon(
                Icons.format_quote_rounded,
                size: 24,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionCard(
    BuildContext context, {
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.15),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(24),
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: color.withOpacity(0.1)),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Colors.white, color.withOpacity(0.02)],
              ),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(20),
                    gradient: LinearGradient(
                      colors: [color.withOpacity(0.1), color.withOpacity(0.05)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                  child: Icon(icon, color: color, size: 32),
                ),
                const SizedBox(width: 20),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 19,
                          fontWeight: FontWeight.w900,
                          color: Color(0xFF1E293B),
                          letterSpacing: -0.5,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey[600],
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.grey[50],
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.arrow_forward_ios_rounded,
                    color: color.withOpacity(0.5),
                    size: 14,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDrawerTag(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.9),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}
