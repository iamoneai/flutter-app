import 'package:cloud_firestore/cloud_firestore.dart';

/// Entity Employee Model - Stored in /entity_employees/{entityId}_{uid}
/// Links a user to an entity as an employee
class EntityEmployee {
  final String id; // entityId_uid
  final String entityId;
  final String uid;
  final String employeeIinId; // Their employee IIN
  final String status; // 'active', 'suspended', 'removed'
  final String role; // 'admin', 'member', 'viewer'
  final List<String> departmentIds;
  final DateTime createdAt;
  final DateTime? updatedAt;

  EntityEmployee({
    required this.id,
    required this.entityId,
    required this.uid,
    required this.employeeIinId,
    required this.status,
    required this.role,
    required this.departmentIds,
    required this.createdAt,
    this.updatedAt,
  });

  factory EntityEmployee.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return EntityEmployee(
      id: doc.id,
      entityId: data['entityId'] ?? '',
      uid: data['uid'] ?? '',
      employeeIinId: data['employeeIinId'] ?? '',
      status: data['status'] ?? 'active',
      role: data['role'] ?? 'member',
      departmentIds: List<String>.from(data['departmentIds'] ?? []),
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      updatedAt: (data['updatedAt'] as Timestamp?)?.toDate(),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'entityId': entityId,
      'uid': uid,
      'employeeIinId': employeeIinId,
      'status': status,
      'role': role,
      'departmentIds': departmentIds,
      'createdAt': Timestamp.fromDate(createdAt),
      if (updatedAt != null) 'updatedAt': Timestamp.fromDate(updatedAt!),
    };
  }

  bool get isActive => status == 'active';
  bool get isAdmin => role == 'admin';
  bool get isMember => role == 'member';

  static String createId(String entityId, String uid) => '${entityId}_$uid';
}

/// Employee Invitation Model - Stored in /entity_invitations/{inviteId}
class EntityInvitation {
  final String id;
  final String entityId;
  final String email;
  final String role;
  final String status; // 'pending', 'accepted', 'declined', 'expired'
  final String invitedByUid;
  final DateTime createdAt;
  final DateTime expiresAt;
  final DateTime? acceptedAt;

  EntityInvitation({
    required this.id,
    required this.entityId,
    required this.email,
    required this.role,
    required this.status,
    required this.invitedByUid,
    required this.createdAt,
    required this.expiresAt,
    this.acceptedAt,
  });

  factory EntityInvitation.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return EntityInvitation(
      id: doc.id,
      entityId: data['entityId'] ?? '',
      email: data['email'] ?? '',
      role: data['role'] ?? 'member',
      status: data['status'] ?? 'pending',
      invitedByUid: data['invitedByUid'] ?? '',
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      expiresAt: (data['expiresAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      acceptedAt: (data['acceptedAt'] as Timestamp?)?.toDate(),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'entityId': entityId,
      'email': email,
      'role': role,
      'status': status,
      'invitedByUid': invitedByUid,
      'createdAt': Timestamp.fromDate(createdAt),
      'expiresAt': Timestamp.fromDate(expiresAt),
      if (acceptedAt != null) 'acceptedAt': Timestamp.fromDate(acceptedAt!),
    };
  }

  bool get isPending => status == 'pending';
  bool get isExpired => DateTime.now().isAfter(expiresAt);
}
