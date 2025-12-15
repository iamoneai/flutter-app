import 'package:cloud_firestore/cloud_firestore.dart';

/// IIN Types
enum IINOwnerType {
  user,
  entity,
}

enum IINTypeEnum {
  personal,
  entityBrain,
  entityEmployee,
}

/// IIN Model - Stored in /iins/{iinId}
class IIN {
  final String iinId;
  final String iinType; // 'personal', 'entity_brain', 'entity_employee'
  final String ownerType; // 'user', 'entity'
  final String ownerId; // uid or entityId
  final String status; // 'active', 'suspended', 'deleted'
  final DateTime createdAt;
  final DateTime? updatedAt;

  IIN({
    required this.iinId,
    required this.iinType,
    required this.ownerType,
    required this.ownerId,
    required this.status,
    required this.createdAt,
    this.updatedAt,
  });

  factory IIN.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return IIN(
      iinId: doc.id,
      iinType: data['iinType'] ?? '',
      ownerType: data['ownerType'] ?? '',
      ownerId: data['ownerId'] ?? '',
      status: data['status'] ?? 'active',
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      updatedAt: (data['updatedAt'] as Timestamp?)?.toDate(),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'iinType': iinType,
      'ownerType': ownerType,
      'ownerId': ownerId,
      'status': status,
      'createdAt': Timestamp.fromDate(createdAt),
      if (updatedAt != null) 'updatedAt': Timestamp.fromDate(updatedAt!),
    };
  }

  bool get isPersonal => iinType == 'personal';
  bool get isEntityBrain => iinType == 'entity_brain';
  bool get isEntityEmployee => iinType == 'entity_employee';
  bool get isActive => status == 'active';
}
