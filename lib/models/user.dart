enum UserRole { admin, user }

class User {
  final int? id;
  final String username;
  final String? password;
  final UserRole role;
  final String? assignedRecs;
  final String? assignedTyps;
  final String? assignedPs;
  final String? assignedOprs;
  final String? assignedTr;
  final String? assignedGate;
  final String? assignedLine;
  final String? assignedZone;
  final String? assignedBox;

  User({
    this.id,
    required this.username,
    this.password,
    required this.role,
    this.assignedRecs,
    this.assignedTyps,
    this.assignedPs,
    this.assignedOprs,
    this.assignedTr,
    this.assignedGate,
    this.assignedLine,
    this.assignedZone,
    this.assignedBox,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'username': username,
      'password': password,
      'role': role.name,
      'assignedRecs': assignedRecs,
      'assignedTyps': assignedTyps,
      'assignedPs': assignedPs,
      'assignedOprs': assignedOprs,
      'assignedTr': assignedTr,
      'assignedGate': assignedGate,
      'assignedLine': assignedLine,
      'assignedZone': assignedZone,
      'assignedBox': assignedBox,
    };
  }

  factory User.fromMap(Map<String, dynamic> map) {
    return User(
      id: map['id'],
      username: map['username'] ?? '',
      password: map['password'],
      role: UserRole.values.firstWhere(
        (e) => e.name == map['role'],
        orElse: () => UserRole.user,
      ),
      assignedRecs: map['assignedRecs'],
      assignedTyps: map['assignedTyps'],
      assignedPs: map['assignedPs'],
      assignedOprs: map['assignedOprs'],
      assignedTr: map['assignedTr'],
      assignedGate: map['assignedGate'],
      assignedLine: map['assignedLine'],
      assignedZone: map['assignedZone'],
      assignedBox: map['assignedBox'],
    );
  }

  bool isAllowedToPick(dynamic item) {
    if (role == UserRole.admin) return true;

    // 1. Check trip-specific assignment (Priority)
    String? itemAssignedUser;
    try {
      itemAssignedUser = item.assignedUser?.toString();
    } catch (_) {
      try {
        if (item is Map) {
          itemAssignedUser = (item['assigned_user'] ?? item['assignedUser'])
              ?.toString();
        }
      } catch (__) {}
    }

    if (itemAssignedUser != null && itemAssignedUser.isNotEmpty) {
      return itemAssignedUser.trim().toUpperCase() ==
          username.trim().toUpperCase();
    }

    // 2. Fallback to global attribute assignments (Category-based)
    // If no specific person is assigned to the item, check if it fits the user's general categories
    bool hasAnyAssignment =
        (assignedRecs != null && assignedRecs!.isNotEmpty) ||
        (assignedTyps != null && assignedTyps!.isNotEmpty) ||
        (assignedPs != null && assignedPs!.isNotEmpty) ||
        (assignedOprs != null && assignedOprs!.isNotEmpty) ||
        (assignedTr != null && assignedTr!.isNotEmpty) ||
        (assignedGate != null && assignedGate!.isNotEmpty) ||
        (assignedLine != null && assignedLine!.isNotEmpty) ||
        (assignedZone != null && assignedZone!.isNotEmpty) ||
        (assignedBox != null && assignedBox!.isNotEmpty);

    if (!hasAnyAssignment) return false;

    // Check REC
    if (assignedRecs != null && assignedRecs!.isNotEmpty) {
      final allowed = assignedRecs!
          .split(',')
          .map((e) => e.trim().toUpperCase())
          .toList();
      if (!allowed.contains(item.rec_hh?.toString().trim().toUpperCase()))
        return false;
    }

    // Check TYP
    if (assignedTyps != null && assignedTyps!.isNotEmpty) {
      final allowed = assignedTyps!
          .split(',')
          .map((e) => e.trim().toUpperCase())
          .toList();
      if (!allowed.contains(item.odr_typ?.toString().trim().toUpperCase()))
        return false;
    }

    // Check PS
    if (assignedPs != null && assignedPs!.isNotEmpty) {
      final allowed = assignedPs!
          .split(',')
          .map((e) => e.trim().toUpperCase())
          .toList();
      if (!allowed.contains(item.ps_cd?.toString().trim().toUpperCase()))
        return false;
    }

    // Check OPR
    if (assignedOprs != null && assignedOprs!.isNotEmpty) {
      final allowed = assignedOprs!
          .split(',')
          .map((e) => e.trim().toUpperCase())
          .toList();
      final itemOpr = item.rec_opr?.toString().trim().toUpperCase() ?? '';
      if (!allowed.any((o) => itemOpr.startsWith(o))) return false;
    }

    // Check TR
    if (assignedTr != null && assignedTr!.isNotEmpty) {
      final allowed = assignedTr!
          .split(',')
          .map((e) => e.trim().toUpperCase())
          .toList();
      if (!allowed.contains(item.tr_no?.toString().trim().toUpperCase()))
        return false;
    }

    // Check GATE
    if (assignedGate != null && assignedGate!.isNotEmpty) {
      final allowed = assignedGate!
          .split(',')
          .map((e) => e.trim().toUpperCase())
          .toList();
      if (!allowed.contains(item.gate?.toString().trim().toUpperCase()))
        return false;
    }

    // Check LINE
    if (assignedLine != null && assignedLine!.isNotEmpty) {
      final allowed = assignedLine!
          .split(',')
          .map((e) => e.trim().toUpperCase())
          .toList();
      if (!allowed.contains(item.line?.toString().trim().toUpperCase()))
        return false;
    }

    // Check ZONE
    if (assignedZone != null && assignedZone!.isNotEmpty) {
      final allowed = assignedZone!
          .split(',')
          .map((e) => e.trim().toUpperCase())
          .toList();
      if (!allowed.contains(item.zone?.toString().trim().toUpperCase()))
        return false;
    }

    // Check BOX
    if (assignedBox != null && assignedBox!.isNotEmpty) {
      final allowed = assignedBox!
          .split(',')
          .map((e) => e.trim().toUpperCase())
          .toList();
      if (!allowed.contains(item.box?.toString().trim().toUpperCase()))
        return false;
    }

    return true;
  }
}
