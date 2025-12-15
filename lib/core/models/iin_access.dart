import 'package:cloud_firestore/cloud_firestore.dart';

/// IIN Access Model - Stored in /iin_access/{docId}
/// Maps users to IINs with roles
class IINAccess {
  final String id;
  final String iinId;
  final String uid;
  final String role; // 'owner', 'admin', 'member', 'viewer'
  final bool active;
  final DateTime createdAt;
  final DateTime? updatedAt;

  IINAccess({
    required this.id,
    required this.iinId,
    required this.uid,
    required this.role,
    required this.active,
    required this.createdAt,
    this.updatedAt,
  });

  factory IINAccess.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return IINAccess(
      id: doc.id,
      iinId: data['iinId'] ?? '',
      uid: data['uid'] ?? '',
      role: data['role'] ?? 'member',
      active: data['active'] ?? true,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      updatedAt: (data['updatedAt'] as Timestamp?)?.toDate(),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'iinId': iinId,
      'uid': uid,
      'role': role,
      'active': active,
      'createdAt': Timestamp.fromDate(createdAt),
      if (updatedAt != null) 'updatedAt': Timestamp.fromDate(updatedAt!),
    };
  }

  bool get isOwner => role == 'owner';
  bool get isAdmin => role == 'admin';
  bool get isMember => role == 'member';
  bool get isViewer => role == 'viewer';
  bool get hasAdminAccess => isOwner || isAdmin;
}

/// Role hierarchy for permissions
class IINRoles {
  static const String owner = 'owner';
  static const String admin = 'admin';
  static const String member = 'member';
  static const String viewer = 'viewer';

  static const List<String> all = [owner, admin, member, viewer];

  static int priority(String role) {
    switch (role) {
      case owner:
        return 4;
      case admin:
        return 3;
      case member:
        return 2;
      case viewer:
        return 1;
      default:
        return 0;
    }
  }

  static bool canManageRole(String currentRole, String targetRole) {
    return priority(currentRole) > priority(targetRole);
  }
}
