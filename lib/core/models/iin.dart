// IAMONEAI - Fresh Start
import 'package:cloud_firestore/cloud_firestore.dart';

/// IIN Model - Stored in /iins/{iinId}
/// Simplified: Only personal IIN type
class IIN {
  final String iinId;
  final String iinType;
  final String ownerType;
  final String ownerId;
  final String status;
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
      iinType: data['iinType'] ?? 'personal',
      ownerType: data['ownerType'] ?? 'user',
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
  bool get isActive => status == 'active';
}
