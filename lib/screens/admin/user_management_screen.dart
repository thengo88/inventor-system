import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../models/user.dart';
import '../../services/api_service.dart';

class UserManagementScreen extends StatefulWidget {
  const UserManagementScreen({super.key});

  @override
  State<UserManagementScreen> createState() => _UserManagementScreenState();
}

class _UserManagementScreenState extends State<UserManagementScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<AuthProvider>().fetchAllUsers();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AuthProvider>(
      builder: (context, auth, child) {
        return Scaffold(
          floatingActionButton: FloatingActionButton(
            onPressed: () => _showUserDialog(),
            backgroundColor: Theme.of(context).primaryColor,
            child: const Icon(
              Icons.person_add_alt_1_rounded,
              color: Colors.white,
            ),
          ),
          body: auth.allUsers.isEmpty
              ? const Center(child: CircularProgressIndicator())
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: auth.allUsers.length,
                  itemBuilder: (context, index) {
                    final staff = auth.allUsers[index];
                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        leading: CircleAvatar(
                          backgroundColor: staff.role == UserRole.admin
                              ? Colors.indigo[50]
                              : Colors.blue[50],
                          child: Icon(
                            staff.role == UserRole.admin
                                ? Icons.admin_panel_settings
                                : Icons.person,
                            color: staff.role == UserRole.admin
                                ? Colors.indigo
                                : Colors.blue,
                          ),
                        ),
                        title: Text(
                          staff.username,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              staff.role == UserRole.admin
                                  ? 'Quản trị viên'
                                  : 'Nhân viên',
                              style: TextStyle(
                                color: Colors.grey[600],
                                fontSize: 13,
                              ),
                            ),
                            if (staff.role == UserRole.user &&
                                ((staff.assignedRecs?.isNotEmpty ?? false) ||
                                    (staff.assignedTyps?.isNotEmpty ?? false) ||
                                    (staff.assignedPs?.isNotEmpty ?? false) ||
                                    (staff.assignedOprs?.isNotEmpty ?? false) ||
                                    (staff.assignedTr?.isNotEmpty ?? false) ||
                                    (staff.assignedGate?.isNotEmpty ?? false) ||
                                    (staff.assignedLine?.isNotEmpty ?? false) ||
                                    (staff.assignedZone?.isNotEmpty ?? false) ||
                                    (staff.assignedBox?.isNotEmpty ??
                                        false))) ...[
                              const SizedBox(height: 4),
                              Wrap(
                                spacing: 8,
                                runSpacing: 4,
                                children: [
                                  if (staff.assignedRecs?.isNotEmpty ?? false)
                                    _buildSmallTag(
                                      'REC: ${staff.assignedRecs}',
                                      Colors.purple,
                                    ),
                                  if (staff.assignedTyps?.isNotEmpty ?? false)
                                    _buildSmallTag(
                                      'TYP: ${staff.assignedTyps}',
                                      Colors.blue,
                                    ),
                                  if (staff.assignedPs?.isNotEmpty ?? false)
                                    _buildSmallTag(
                                      'PS: ${staff.assignedPs}',
                                      Colors.green,
                                    ),
                                  if (staff.assignedOprs?.isNotEmpty ?? false)
                                    _buildSmallTag(
                                      'OPR: ${staff.assignedOprs}',
                                      Colors.orange,
                                    ),
                                  if (staff.assignedTr?.isNotEmpty ?? false)
                                    _buildSmallTag(
                                      'TR: ${staff.assignedTr}',
                                      Colors.indigo,
                                    ),
                                  if (staff.assignedGate?.isNotEmpty ?? false)
                                    _buildSmallTag(
                                      'GATE: ${staff.assignedGate}',
                                      Colors.teal,
                                    ),
                                  if (staff.assignedLine?.isNotEmpty ?? false)
                                    _buildSmallTag(
                                      'LINE: ${staff.assignedLine}',
                                      Colors.deepOrange,
                                    ),
                                  if (staff.assignedZone?.isNotEmpty ?? false)
                                    _buildSmallTag(
                                      'ZONE: ${staff.assignedZone}',
                                      Colors.blueGrey,
                                    ),
                                  if (staff.assignedBox?.isNotEmpty ?? false)
                                    _buildSmallTag(
                                      'BOX: ${staff.assignedBox}',
                                      Colors.brown,
                                    ),
                                ],
                              ),
                            ],
                          ],
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(
                                Icons.edit_outlined,
                                color: Colors.blue,
                              ),
                              onPressed: () => _showUserDialog(user: staff),
                              tooltip: 'Sửa thông tin',
                            ),
                            if (staff.username != 'admin')
                              IconButton(
                                icon: const Icon(
                                  Icons.delete_outline,
                                  color: Colors.red,
                                ),
                                onPressed: () => _confirmDelete(staff),
                                tooltip: 'Xóa nhân viên',
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        );
      },
    );
  }

  Map<String, List<String>> _uniqueValues = {};

  Future<void> _loadUniqueValues() async {
    final values = await ApiService().getUniqueFilterValues();
    if (values != null) {
      if (mounted) {
        setState(() {
          _uniqueValues = {
            'recs': List<String>.from(values['recs'] ?? []),
            'typs': List<String>.from(values['typs'] ?? []),
            'ps': List<String>.from(values['ps'] ?? []),
            'oprs': List<String>.from(values['oprs'] ?? []),
            'tr': List<String>.from(values['tr'] ?? []),
            'gate': List<String>.from(values['gate'] ?? []),
            'line': List<String>.from(values['line'] ?? []),
            'zone': List<String>.from(values['zone'] ?? []),
            'box': List<String>.from(values['box'] ?? []),
          };
        });
      }
    }
  }

  void _showUserDialog({User? user}) async {
    await _loadUniqueValues();

    final usernameController = TextEditingController(text: user?.username);
    final passwordController = TextEditingController();

    // Convert string assignments to lists for easier chip management
    List<String> assignedRecs =
        user?.assignedRecs
            ?.split(',')
            .where((s) => s.trim().isNotEmpty)
            .map((s) => s.trim())
            .toList() ??
        [];
    List<String> assignedTyps =
        user?.assignedTyps
            ?.split(',')
            .where((s) => s.trim().isNotEmpty)
            .map((s) => s.trim())
            .toList() ??
        [];
    List<String> assignedPs =
        user?.assignedPs
            ?.split(',')
            .where((s) => s.trim().isNotEmpty)
            .map((s) => s.trim())
            .toList() ??
        [];
    List<String> assignedOprs =
        user?.assignedOprs
            ?.split(',')
            .where((s) => s.trim().isNotEmpty)
            .map((s) => s.trim())
            .toList() ??
        [];
    List<String> assignedTr =
        user?.assignedTr
            ?.split(',')
            .where((s) => s.trim().isNotEmpty)
            .map((s) => s.trim())
            .toList() ??
        [];
    List<String> assignedGate =
        user?.assignedGate
            ?.split(',')
            .where((s) => s.trim().isNotEmpty)
            .map((s) => s.trim())
            .toList() ??
        [];
    List<String> assignedLine =
        user?.assignedLine
            ?.split(',')
            .where((s) => s.trim().isNotEmpty)
            .map((s) => s.trim())
            .toList() ??
        [];
    List<String> assignedZone =
        user?.assignedZone
            ?.split(',')
            .where((s) => s.trim().isNotEmpty)
            .map((s) => s.trim())
            .toList() ??
        [];
    List<String> assignedBox =
        user?.assignedBox
            ?.split(',')
            .where((s) => s.trim().isNotEmpty)
            .map((s) => s.trim())
            .toList() ??
        [];

    UserRole selectedRole = user?.role ?? UserRole.user;

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          titlePadding: EdgeInsets.zero,
          title: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Theme.of(context).primaryColor,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(24),
                topRight: Radius.circular(24),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  user == null ? Icons.person_add : Icons.edit,
                  color: Colors.white,
                ),
                const SizedBox(width: 12),
                Text(
                  user == null ? 'Thêm nhân viên' : 'Sửa thông tin',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          content: SizedBox(
            width: MediaQuery.of(context).size.width * 0.9,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(height: 10),
                  TextField(
                    controller: usernameController,
                    decoration: InputDecoration(
                      labelText: 'Tên đăng nhập',
                      prefixIcon: const Icon(Icons.account_circle_outlined),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    enabled: user == null,
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: passwordController,
                    decoration: InputDecoration(
                      labelText: user == null ? 'Mật khẩu' : 'Mật khẩu mới',
                      helperText: user == null
                          ? null
                          : 'Để trống nếu không muốn đổi',
                      prefixIcon: const Icon(Icons.lock_outline),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    obscureText: true,
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<UserRole>(
                    initialValue: selectedRole,
                    items: UserRole.values
                        .map(
                          (r) => DropdownMenuItem(
                            value: r,
                            child: Text(
                              r == UserRole.admin
                                  ? 'Quản trị viên'
                                  : 'Nhân viên',
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (val) =>
                        setDialogState(() => selectedRole = val!),
                    decoration: InputDecoration(
                      labelText: 'Vai trò',
                      prefixIcon: const Icon(
                        Icons.admin_panel_settings_outlined,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                  if (selectedRole == UserRole.user) ...[
                    const Divider(height: 48),
                    _buildAssignmentSection(
                      context,
                      'GÁN REC',
                      assignedRecs,
                      _uniqueValues['recs'] ?? [],
                      Colors.purple,
                      (newList) => setDialogState(() => assignedRecs = newList),
                    ),
                    const SizedBox(height: 16),
                    _buildAssignmentSection(
                      context,
                      'GÁN TYP',
                      assignedTyps,
                      _uniqueValues['typs'] ?? [],
                      Colors.blue,
                      (newList) => setDialogState(() => assignedTyps = newList),
                    ),
                    const SizedBox(height: 16),
                    _buildAssignmentSection(
                      context,
                      'GÁN PS',
                      assignedPs,
                      _uniqueValues['ps'] ?? [],
                      Colors.green,
                      (newList) => setDialogState(() => assignedPs = newList),
                    ),
                    const SizedBox(height: 16),
                    _buildAssignmentSection(
                      context,
                      'GÁN OPR',
                      assignedOprs,
                      _uniqueValues['oprs'] ?? [],
                      Colors.orange,
                      (newList) => setDialogState(() => assignedOprs = newList),
                    ),
                    const SizedBox(height: 16),
                    _buildAssignmentSection(
                      context,
                      'GÁN TR.NO',
                      assignedTr,
                      _uniqueValues['tr'] ?? [],
                      Colors.indigo,
                      (newList) => setDialogState(() => assignedTr = newList),
                    ),
                    const SizedBox(height: 16),
                    _buildAssignmentSection(
                      context,
                      'GÁN GATE',
                      assignedGate,
                      _uniqueValues['gate'] ?? [],
                      Colors.teal,
                      (newList) => setDialogState(() => assignedGate = newList),
                    ),
                    const SizedBox(height: 16),
                    _buildAssignmentSection(
                      context,
                      'GÁN LINE',
                      assignedLine,
                      _uniqueValues['line'] ?? [],
                      Colors.deepOrange,
                      (newList) => setDialogState(() => assignedLine = newList),
                    ),
                    const SizedBox(height: 16),
                    _buildAssignmentSection(
                      context,
                      'GÁN ZONE',
                      assignedZone,
                      _uniqueValues['zone'] ?? [],
                      Colors.blueGrey,
                      (newList) => setDialogState(() => assignedZone = newList),
                    ),
                    const SizedBox(height: 16),
                    _buildAssignmentSection(
                      context,
                      'GÁN BOX',
                      assignedBox,
                      _uniqueValues['box'] ?? [],
                      Colors.brown,
                      (newList) => setDialogState(() => assignedBox = newList),
                    ),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(
                'HỦY',
                style: TextStyle(
                  color: Colors.grey[600],
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).primaryColor,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onPressed: () {
                if (usernameController.text.isNotEmpty &&
                    (user != null || passwordController.text.isNotEmpty)) {
                  final recs = assignedRecs.join(',');
                  final typs = assignedTyps.join(',');
                  final ps = assignedPs.join(',');
                  final oprs = assignedOprs.join(',');
                  final tr = assignedTr.join(',');
                  final gate = assignedGate.join(',');
                  final line = assignedLine.join(',');
                  final zone = assignedZone.join(',');
                  final box = assignedBox.join(',');

                  if (user == null) {
                    final newUser = User(
                      username: usernameController.text,
                      password: passwordController.text,
                      role: selectedRole,
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
                    context.read<AuthProvider>().createUser(newUser);
                  } else {
                    context.read<AuthProvider>().editUser(
                      user.id!,
                      user.username,
                      passwordController.text.isEmpty
                          ? null
                          : passwordController.text,
                      selectedRole,
                      recs: recs,
                      typs: typs,
                      ps: ps,
                      oprs: oprs,
                      tr: tr,
                      gate: gate,
                      line: line,
                      zone: zone,
                      box: box,
                    );
                  }
                  Navigator.pop(ctx);
                }
              },
              child: const Text(
                'LƯU THAY ĐỔI',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAssignmentSection(
    BuildContext context,
    String label,
    List<String> selectedValues,
    List<String> availableValues,
    Color color,
    Function(List<String>) onChanged,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 13,
                color: color,
              ),
            ),
            IconButton(
              icon: Icon(Icons.add_circle_outline, color: color, size: 20),
              onPressed: () => _openSelectionDialog(
                context,
                label,
                selectedValues,
                availableValues,
                onChanged,
              ),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: color.withOpacity(0.05),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color.withOpacity(0.15)),
          ),
          child: selectedValues.isEmpty
              ? Text(
                  'Chưa gán mục nào',
                  style: TextStyle(
                    fontSize: 12,
                    fontStyle: FontStyle.italic,
                    color: Colors.grey[500],
                  ),
                )
              : Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: selectedValues
                      .map(
                        (val) => Chip(
                          label: Text(
                            val,
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                          backgroundColor: color,
                          padding: EdgeInsets.zero,
                          materialTapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                          deleteIcon: const Icon(
                            Icons.close,
                            size: 14,
                            color: Colors.white,
                          ),
                          onDeleted: () {
                            final newList = List<String>.from(selectedValues)
                              ..remove(val);
                            onChanged(newList);
                          },
                        ),
                      )
                      .toList(),
                ),
        ),
      ],
    );
  }

  void _openSelectionDialog(
    BuildContext context,
    String title,
    List<String> selectedValues,
    List<String> availableValues,
    Function(List<String>) onChanged,
  ) {
    List<String> tempSelected = List<String>.from(selectedValues);
    final searchController = TextEditingController();
    List<String> filteredValues = List<String>.from(availableValues);

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setSelectionState) => AlertDialog(
          title: Text(
            'Chọn $title',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          content: SizedBox(
            width: double.maxFinite,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: searchController,
                  decoration: const InputDecoration(
                    hintText: 'Tìm kiếm...',
                    prefixIcon: Icon(Icons.search),
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (val) {
                    setSelectionState(() {
                      filteredValues = availableValues
                          .where(
                            (item) =>
                                item.toUpperCase().contains(val.toUpperCase()),
                          )
                          .toList();
                    });
                  },
                ),
                const SizedBox(height: 16),
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.of(context).size.height * 0.4,
                  ),
                  child: filteredValues.isEmpty
                      ? const Padding(
                          padding: EdgeInsets.all(20),
                          child: Text('Không tìm thấy dữ liệu'),
                        )
                      : ListView.builder(
                          shrinkWrap: true,
                          itemCount: filteredValues.length,
                          itemBuilder: (context, index) {
                            final val = filteredValues[index];
                            final isSelected = tempSelected.contains(val);
                            return CheckboxListTile(
                              title: Text(val),
                              value: isSelected,
                              onChanged: (checked) {
                                setSelectionState(() {
                                  if (checked!) {
                                    if (!tempSelected.contains(val))
                                      tempSelected.add(val);
                                  } else {
                                    tempSelected.remove(val);
                                  }
                                });
                              },
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('ĐÓNG'),
            ),
            ElevatedButton(
              onPressed: () {
                onChanged(tempSelected);
                Navigator.pop(ctx);
              },
              child: const Text('XÁC NHẬN'),
            ),
          ],
        ),
      ),
    );
  }

  void _confirmDelete(User user) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Xác nhận xóa'),
        content: Text('Bạn có chắc chắn muốn xóa nhân viên ${user.username}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('HỦY'),
          ),
          TextButton(
            onPressed: () {
              context.read<AuthProvider>().removeUser(user.id!, user.username);
              Navigator.pop(ctx);
            },
            child: const Text(
              'XÓA',
              style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSmallTag(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withOpacity(0.3)),
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
