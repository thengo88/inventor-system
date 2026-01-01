import 'package:flutter/material.dart';
import '../../services/api_service.dart';

class AssignmentProgressScreen extends StatefulWidget {
  const AssignmentProgressScreen({super.key});

  @override
  State<AssignmentProgressScreen> createState() =>
      _AssignmentProgressScreenState();
}

class _AssignmentProgressScreenState extends State<AssignmentProgressScreen> {
  final ApiService _apiService = ApiService();
  List<dynamic> _assignments = [];
  bool _isLoading = true;
  Map<String, List<String>> _uniqueValues = {};

  @override
  void initState() {
    super.initState();
    _loadData();
    _loadUniqueValues();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    final data = await _apiService.getAssignmentProgress();
    setState(() {
      _assignments = data;
      _isLoading = false;
    });
  }

  Future<void> _loadUniqueValues() async {
    final values = await _apiService.getUniqueFilterValues();
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Tiến độ chỉ định soạn hàng'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _loadData),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _assignments.isEmpty
          ? const Center(child: Text('Chưa có nhân viên nào được chỉ định'))
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _assignments.length,
              itemBuilder: (context, index) {
                final item = _assignments[index];
                final stats = item['stats'] ?? {};
                final totalQty = (stats['totalQtyRequired'] ?? 0).toDouble();
                final pickedQty = (stats['totalQtyPicked'] ?? 0).toDouble();
                final progress = totalQty > 0 ? (pickedQty / totalQty) : 0.0;

                return Card(
                  margin: const EdgeInsets.only(bottom: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  elevation: 4,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          spacing: 12,
                          runSpacing: 12,
                          alignment: WrapAlignment.spaceBetween,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                CircleAvatar(
                                  backgroundColor: Colors.blue[50],
                                  child: const Icon(
                                    Icons.person,
                                    color: Colors.blue,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      item['username'] ?? 'N/A',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 18,
                                      ),
                                    ),
                                    Text(
                                      'Vai trò: Nhân viên',
                                      style: TextStyle(
                                        color: Colors.grey[600],
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(width: 12),
                                IconButton(
                                  icon: const Icon(
                                    Icons.edit_note_rounded,
                                    color: Colors.blue,
                                  ),
                                  onPressed: () => _editAssignment(item),
                                  tooltip: 'Chỉnh sửa chỉ định',
                                ),
                              ],
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: _getProgressColor(
                                  progress,
                                ).withOpacity(0.1),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                '${(progress * 100).toStringAsFixed(1)}%',
                                style: TextStyle(
                                  color: _getProgressColor(progress),
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const Divider(height: 24),
                        const Text(
                          'NHIỆM VỤ ĐƯỢC GIAO:',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: Colors.grey,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            if (item['assignedRecs']?.toString().isNotEmpty ??
                                false)
                              _buildTag(
                                'REC: ${item['assignedRecs']}',
                                Colors.purple,
                              ),
                            if (item['assignedTyps']?.toString().isNotEmpty ??
                                false)
                              _buildTag(
                                'TYP: ${item['assignedTyps']}',
                                Colors.blue,
                              ),
                            if (item['assignedPs']?.toString().isNotEmpty ??
                                false)
                              _buildTag(
                                'PS: ${item['assignedPs']}',
                                Colors.green,
                              ),
                            if (item['assignedOprs']?.toString().isNotEmpty ??
                                false)
                              _buildTag(
                                'OPR: ${item['assignedOprs']}',
                                Colors.orange,
                              ),
                            if (item['assignedTr']?.toString().isNotEmpty ??
                                false)
                              _buildTag(
                                'TR: ${item['assignedTr']}',
                                Colors.indigo,
                              ),
                            if (item['assignedGate']?.toString().isNotEmpty ??
                                false)
                              _buildTag(
                                'GATE: ${item['assignedGate']}',
                                Colors.teal,
                              ),
                            if (item['assignedLine']?.toString().isNotEmpty ??
                                false)
                              _buildTag(
                                'LINE: ${item['assignedLine']}',
                                Colors.deepOrange,
                              ),
                            if (item['assignedZone']?.toString().isNotEmpty ??
                                false)
                              _buildTag(
                                'ZONE: ${item['assignedZone']}',
                                Colors.blueGrey,
                              ),
                            if (item['assignedBox']?.toString().isNotEmpty ??
                                false)
                              _buildTag(
                                'BOX: ${item['assignedBox']}',
                                Colors.brown,
                              ),
                            if (!(item['assignedRecs']?.toString().isNotEmpty ??
                                    false) &&
                                !(item['assignedTyps']?.toString().isNotEmpty ??
                                    false) &&
                                !(item['assignedPs']?.toString().isNotEmpty ??
                                    false) &&
                                !(item['assignedOprs']?.toString().isNotEmpty ??
                                    false) &&
                                !(item['assignedTr']?.toString().isNotEmpty ??
                                    false) &&
                                !(item['assignedGate']?.toString().isNotEmpty ??
                                    false) &&
                                !(item['assignedLine']?.toString().isNotEmpty ??
                                    false) &&
                                !(item['assignedZone']?.toString().isNotEmpty ??
                                    false) &&
                                !(item['assignedBox']?.toString().isNotEmpty ??
                                    false))
                              const Text(
                                'Chưa gán nhiệm vụ',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontStyle: FontStyle.italic,
                                  color: Colors.red,
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 20),
                        Wrap(
                          spacing: 16,
                          runSpacing: 16,
                          alignment: WrapAlignment.spaceBetween,
                          children: [
                            _buildStatItem(
                              'Tổng mặt hàng',
                              stats['totalItems']?.toString() ?? '0',
                              Icons.inventory_2_outlined,
                            ),
                            _buildStatItem(
                              'Tổng số lượng',
                              stats['totalQtyRequired']?.toString() ?? '0',
                              Icons.shopping_basket_outlined,
                            ),
                            _buildStatItem(
                              'Đã soạn',
                              stats['totalQtyPicked']?.toString() ?? '0',
                              Icons.check_circle_outline,
                              color: Colors.green,
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: LinearProgressIndicator(
                            value: progress,
                            minHeight: 10,
                            backgroundColor: Colors.grey[200],
                            valueColor: AlwaysStoppedAnimation<Color>(
                              _getProgressColor(progress),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }

  void _editAssignment(dynamic userItem) async {
    // Refresh unique values before showing dialog
    await _loadUniqueValues();

    // Parse current assignments
    List<String> assignedRecs =
        userItem['assignedRecs']
            ?.toString()
            .split(',')
            .where((s) => s.trim().isNotEmpty)
            .map((s) => s.trim())
            .toList() ??
        [];
    List<String> assignedTyps =
        userItem['assignedTyps']
            ?.toString()
            .split(',')
            .where((s) => s.trim().isNotEmpty)
            .map((s) => s.trim())
            .toList() ??
        [];
    List<String> assignedPs =
        userItem['assignedPs']
            ?.toString()
            .split(',')
            .where((s) => s.trim().isNotEmpty)
            .map((s) => s.trim())
            .toList() ??
        [];
    List<String> assignedOprs =
        userItem['assignedOprs']
            ?.toString()
            .split(',')
            .where((s) => s.trim().isNotEmpty)
            .map((s) => s.trim())
            .toList() ??
        [];
    List<String> assignedTr =
        userItem['assignedTr']
            ?.toString()
            .split(',')
            .where((s) => s.trim().isNotEmpty)
            .map((s) => s.trim())
            .toList() ??
        [];
    List<String> assignedGate =
        userItem['assignedGate']
            ?.toString()
            .split(',')
            .where((s) => s.trim().isNotEmpty)
            .map((s) => s.trim())
            .toList() ??
        [];
    List<String> assignedLine =
        userItem['assignedLine']
            ?.toString()
            .split(',')
            .where((s) => s.trim().isNotEmpty)
            .map((s) => s.trim())
            .toList() ??
        [];
    List<String> assignedZone =
        userItem['assignedZone']
            ?.toString()
            .split(',')
            .where((s) => s.trim().isNotEmpty)
            .map((s) => s.trim())
            .toList() ??
        [];
    List<String> assignedBox =
        userItem['assignedBox']
            ?.toString()
            .split(',')
            .where((s) => s.trim().isNotEmpty)
            .map((s) => s.trim())
            .toList() ??
        [];

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
                const Icon(Icons.assignment_ind, color: Colors.white),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Chỉ định cho: ${userItem['username']}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                    overflow: TextOverflow.ellipsis,
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
              onPressed: () async {
                final success = await ApiService().updateUser(
                  userItem['id'],
                  role: 'user',
                  assignedRecs: assignedRecs.join(','),
                  assignedTyps: assignedTyps.join(','),
                  assignedPs: assignedPs.join(','),
                  assignedOprs: assignedOprs.join(','),
                  assignedTr: assignedTr.join(','),
                  assignedGate: assignedGate.join(','),
                  assignedLine: assignedLine.join(','),
                  assignedZone: assignedZone.join(','),
                  assignedBox: assignedBox.join(','),
                );

                if (success) {
                  Navigator.pop(ctx);
                  _loadData(); // Refresh list to update stats and chips
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

  Color _getProgressColor(double progress) {
    if (progress >= 1.0) return Colors.green;
    if (progress >= 0.7) return Colors.blue;
    if (progress >= 0.3) return Colors.orange;
    return Colors.red;
  }

  Widget _buildTag(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildStatItem(
    String label,
    String value,
    IconData icon, {
    Color? color,
  }) {
    return Column(
      children: [
        Icon(icon, size: 20, color: color ?? Colors.grey[600]),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 16,
            color: color,
          ),
        ),
        Text(label, style: const TextStyle(fontSize: 10, color: Colors.grey)),
      ],
    );
  }
}
